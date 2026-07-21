#!/bin/bash
#
# AdGuard VPN -- Kill Switch Side Effects
#
# Functions that perform actions (logging, termination, cleanup)
# driven by the state machine.  Kept separate from pure detection
# so that detection logic remains unit-testable without side effects.

# =============================================================================
# Action functions
# =============================================================================

# Log a periodic heartbeat status line.
# Called every KS_HEARTBEAT_INTERVAL checks.
# Usage: ks_heartbeat <total_checks> <uptime_seconds>
ks_heartbeat() {
    local checks="$1" uptime="$2"
    local state_name
    state_name=$(ks_get_state_name)

    local status_icon
    case "$_KS_CURRENT_STATE" in
        "$KS_STANDBY")      status_icon="⏳ STANDBY" ;;
        "$KS_PROTECTED")    status_icon="🔒 PROTECTED" ;;
        "$KS_LEAK_WARNING") status_icon="⚠️  LEAK WARNING" ;;
        "$KS_TERMINATING")  status_icon="🛑 TERMINATING" ;;
        *)                  status_icon="❓ UNKNOWN" ;;
    esac

    log INFO "Kill switch | ${status_icon} | VPN IP: ${KS_VPN_IP:-unknown} | Checks: ${checks} | Uptime: ${uptime}s"
}

# Log a detailed leak-warning message.
# Usage: ks_log_leak <leak_count>
ks_log_leak() {
    local count="$1"

    log WARN "--- VPN LEAK DETECTED (event #${count}) ---"
    log WARN "Real IP exposed: ${KS_CURRENT_IP}"
    log WARN "VPN was protecting: ${KS_VPN_IP:-unknown}"

    if [ "${KS_LEAK_WARNING_ONLY,,}" = "true" ]; then
        log WARN "Warning-only mode: continuing to monitor"
    else
        log WARN "Termination pending if leak persists"
    fi
}

# Log the recovery when VPN IP is restored after a leak.
ks_log_recovery() {
    log INFO "VPN IP restored: ${KS_CURRENT_IP}"
    log INFO "Leak resolved, returning to protected state"
}

# Log VPN service failure.
ks_log_vpn_failure() {
    log ERROR "VPN service disconnected unexpectedly"
    log ERROR "Kill switch triggering termination"
}

# Terminate the container with an appropriate exit code.
# Usage: ks_terminate <reason>
ks_terminate() {
    local reason="${1:-Unknown reason}"
    log ERROR "KILL SWITCH ACTIVATED — ${reason}"
    log ERROR "Container terminating for safety"
    exit 1
}

# Summary log every N checks (e.g. every 20 checks for periodic summary).
# Usage: ks_print_summary <total_checks> <leak_count> <uptime>
ks_print_summary() {
    local checks="$1" leaks="$2" uptime="$3"
    local state_name
    state_name=$(ks_get_state_name)

    log INFO "System summary (check #${checks}):"
    log INFO "  State: ${state_name}"
    log INFO "  Health checks: ${checks}"
    log INFO "  Leak events: ${leaks}"
    log INFO "  Real IP: ${KS_REAL_IP}"
    log INFO "  VPN IP: ${KS_VPN_IP:-none}"
    log INFO "  Uptime: ${uptime}s"
}
