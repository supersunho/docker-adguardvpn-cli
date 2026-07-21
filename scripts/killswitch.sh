#!/bin/bash
#
# AdGuard VPN -- Kill Switch Main Loop
#
# A four-state machine (STANDBY → PROTECTED → LEAK_WARNING → TERMINATING)
# that monitors VPN status and terminates the container on IP leaks.
#
# Operational parameters:
#   CHECK_INTERVAL=15s        IP check every 15 seconds
#   Heartbeat every 60s       (every 4th check)
#   MAX_WAIT_TIME=30s         Initial VPN tunnel activation timeout
#
# Usage: killswitch.sh <real_ip_before_vpn>

set -euo pipefail

# =============================================================================
# Initialisation
# =============================================================================

source /opt/adguardvpn_cli/scripts/utils.sh
setup_traps

# =============================================================================
# Signal handling
# =============================================================================

_ks_shutdown() {
    log INFO "Kill switch received shutdown signal"
    ks_set_state $KS_TERMINATING
    exit 0
}

trap _ks_shutdown TERM INT

# =============================================================================
# Validate arguments
# =============================================================================

KS_REAL_IP="${1:-$REAL_IP_BEFORE_VPN}"

if [ -z "$KS_REAL_IP" ]; then
    log ERROR "Real IP not provided. Usage: $0 <real_ip_before_vpn>"
    exit 1
fi

log INFO "Kill switch starting — real IP: ${KS_REAL_IP}"
ks_reset

# =============================================================================
# Wait for VPN tunnel activation
# =============================================================================

if ! ks_wait_for_vpn_tunnel; then
    ks_terminate "VPN tunnel did not activate within ${KS_MAX_WAIT_TIME}s"
fi

ks_set_state $KS_PROTECTED

# =============================================================================
# Tracking variables
# =============================================================================

TOTAL_CHECKS=0
SCRIPT_START=$(date +%s)

# =============================================================================
# Main monitoring loop (with wait $! for immediate signal response)
# =============================================================================

while true; do
    sleep "$KS_CHECK_INTERVAL" &
    wait $!
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    UPTIME=$(( $(date +%s) - SCRIPT_START ))

    # --------------------------------------------------------------------------
    # 1. Check VPN service
    # --------------------------------------------------------------------------
    if ! ks_is_vpn_connected; then
        ks_log_vpn_failure
        ks_terminate "VPN service disconnected"
    fi

    # --------------------------------------------------------------------------
    # 2. Detect current IP
    # --------------------------------------------------------------------------
    if ! ks_detect_current_ip; then
        ks_terminate "IP detection failed after ${KS_IP_RETRY_COUNT} attempts"
    fi

    # --------------------------------------------------------------------------
    # 3. Detect IP change (new VPN endpoint)
    # --------------------------------------------------------------------------
    ks_detect_ip_change

    # --------------------------------------------------------------------------
    # 4. State machine logic
    # --------------------------------------------------------------------------

    if ks_is_leak; then
        # ---- LEAK SCENARIO ----
        _KS_LEAK_COUNT=$((_KS_LEAK_COUNT + 1))
        ks_log_leak "$_KS_LEAK_COUNT"

        case "$_KS_CURRENT_STATE" in
            $KS_PROTECTED)
                ks_set_state $KS_LEAK_WARNING
                ;;
            $KS_LEAK_WARNING)
                # Already in warning — check tolerance
                if [ "${KS_LEAK_WARNING_ONLY,,}" = "true" ]; then
                    log WARN "Warning-only mode: leak persists"
                elif [ "$_KS_LEAK_COUNT" -gt "$KS_MAX_LEAK_TOLERANCE" ]; then
                    ks_terminate "Leak tolerance exceeded (${_KS_LEAK_COUNT} > ${KS_MAX_LEAK_TOLERANCE})"
                fi
                ;;
            $KS_STANDBY)
                # Tunnel never fully activated — treat as leak
                ks_terminate "Original IP detected before VPN established"
                ;;
        esac
    else
        # ---- PROTECTED SCENARIO ----
        case "$_KS_CURRENT_STATE" in
            $KS_LEAK_WARNING)
                ks_log_recovery
                ks_set_state $KS_PROTECTED
                ;;
            $KS_STANDBY)
                # First time we see a non-real IP after initial wait
                # (fallback in case ks_wait_for_vpn_tunnel didn't catch it)
                if [ -n "$KS_CURRENT_IP" ] && [ "$KS_CURRENT_IP" != "$KS_REAL_IP" ]; then
                    ks_set_state $KS_PROTECTED
                fi
                ;;
        esac
    fi

    # --------------------------------------------------------------------------
    # 5. Heartbeat / periodic logging
    # --------------------------------------------------------------------------
    if [ $((TOTAL_CHECKS % 4)) -eq 0 ]; then
        ks_heartbeat "$TOTAL_CHECKS" "$UPTIME"
    fi

    if [ $((TOTAL_CHECKS % 20)) -eq 0 ]; then
        ks_print_summary "$TOTAL_CHECKS" "$_KS_LEAK_COUNT" "$UPTIME"
    fi
done
