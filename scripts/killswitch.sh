#!/bin/bash
#
# AdGuard VPN -- Kill Switch Main Loop
#
# A four-state machine (STANDBY → PROTECTED → LEAK_WARNING → TERMINATING)
# that monitors VPN status and terminates the container on IP leaks.
#
# Usage: killswitch.sh <real_ip_before_vpn>

set -euo pipefail

source /opt/adguardvpn_cli/scripts/utils.sh

# Bootstrap configuration before any side effects
config_bootstrap

setup_traps

# =============================================================================
# Signal handling
# =============================================================================

_ks_shutdown() {
    log INFO "Kill switch received shutdown signal"
    ks_set_state "$KS_TERMINATING"
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

ks_set_state "$KS_PROTECTED"

# =============================================================================
# Tracking variables
# =============================================================================

TOTAL_CHECKS=0
SCRIPT_START=$(date +%s)

# =============================================================================
# Main monitoring loop
# =============================================================================

while true; do
    sleep "$KS_CHECK_INTERVAL" &
    wait $!
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    UPTIME=$(( $(date +%s) - SCRIPT_START ))

    # 1. Check VPN service
    if ! ks_is_vpn_connected; then
        ks_log_vpn_failure
        ks_terminate "VPN service disconnected"
    fi

    # 2. Detect current IP
    if ! ks_detect_current_ip; then
        ks_terminate "IP detection failed after ${KS_IP_RETRY_COUNT} attempts"
    fi

    # 3. Detect IP change (new VPN endpoint)
    ks_detect_ip_change

    # 4. State machine logic
    if ks_is_leak; then
        # ---- LEAK SCENARIO ----
        # Record the leak — ks_record_leak compares count vs tolerance
        # and returns non-zero when termination is required.
        if ! ks_record_leak "$KS_MAX_LEAK_TOLERANCE" "$KS_LEAK_WARNING_ONLY"; then
            ks_terminate "Leak tolerance exceeded (${_KS_LEAK_COUNT} > ${KS_MAX_LEAK_TOLERANCE})"
        fi

        # Leak is within tolerance — transition state if needed
        case "$_KS_CURRENT_STATE" in
            "$KS_PROTECTED")
                ks_set_state "$KS_LEAK_WARNING"
                ks_log_leak "$_KS_LEAK_COUNT"
                ;;
            "$KS_LEAK_WARNING")
                # Already in warning, leak persists — logged by ks_record_leak
                ks_log_leak "$_KS_LEAK_COUNT"
                ;;
            "$KS_STANDBY")
                ks_terminate "Original IP detected before VPN established"
                ;;
        esac
    else
        # ---- PROTECTED SCENARIO ----
        case "$_KS_CURRENT_STATE" in
            "$KS_LEAK_WARNING")
                ks_clear_leak_count
                ks_log_recovery
                ks_set_state "$KS_PROTECTED"
                ;;
            "$KS_STANDBY")
                # First time we see a non-real IP after initial wait
                if [ -n "$KS_CURRENT_IP" ] && [ "$KS_CURRENT_IP" != "$KS_REAL_IP" ]; then
                    ks_set_state "$KS_PROTECTED"
                fi
                ;;
        esac
    fi

    # 5. Heartbeat / periodic logging
    if [ "${ADGUARD_SHOW_LOG:-true}" = "true" ]; then
        if [ "$TOTAL_CHECKS" -eq 1 ] || [ $((TOTAL_CHECKS % 4)) -eq 0 ]; then
            ks_heartbeat "$TOTAL_CHECKS" "$UPTIME"
        fi
    fi

    if [ $((TOTAL_CHECKS % 20)) -eq 0 ]; then
        ks_print_summary "$TOTAL_CHECKS" "$_KS_LEAK_COUNT" "$UPTIME"
    fi
done
