#!/bin/bash
set -euo pipefail

# =============================================================================
# AdGuard VPN Container Entry Point Script
# =============================================================================

source /opt/adguardvpn_cli/scripts/utils.sh

# Bootstrap configuration before any side effects
config_bootstrap

setup_traps

# =============================================================================
# Signal handling
# =============================================================================

_cleanup_and_exit() {
    local exit_code="${1:-0}"
    log INFO "Shutting down..."

    if [ -n "${TAIL_PID:-}" ]; then
        kill "${TAIL_PID}" 2>/dev/null || true
        [ -n "${TAIL_PID:-}" ] && wait "${TAIL_PID}" || true 2>/dev/null || true
    fi

    if [ -n "${KILL_PID:-}" ]; then
        kill "${KILL_PID}" 2>/dev/null || true
        wait "${KILL_PID}" 2>/dev/null || true
    fi

    exit "$exit_code"
}

_shutdown_handler() {
    _cleanup_and_exit 0
}

trap _shutdown_handler TERM INT

# =============================================================================
# Configuration Setup (bootstrapped above)
# =============================================================================

log INFO "AdGuard VPN Container Starting"
log INFO "Kill Switch: ${ADGUARD_USE_KILL_SWITCH}"
log INFO "Connection mode: ${ADGUARD_CONNECTION_TYPE}"

# =============================================================================
# Permission Setup
# =============================================================================

if [ -c /dev/net/tun ]; then
    if chmod 666 /dev/net/tun 2>/dev/null; then
        log DEBUG "/dev/net/tun permissions set to 666"
    else
        log INFO "/dev/net/tun already accessible"
    fi
else
    log WARN "/dev/net/tun not found — VPN may not work. Ensure device is mapped in docker-compose.yml"
fi

DATA_DIR="${HOME}/.local/share/adguardvpn-cli"
if [ ! -d "$DATA_DIR" ]; then
    if mkdir -p "$DATA_DIR" 2>/dev/null; then
        log INFO "Created data directory: ${DATA_DIR}"
    else
        log WARN "Could not create data directory: ${DATA_DIR}"
        log WARN "Verify volume mount permissions in docker-compose.yml"
    fi
fi

# Verify data directory is writable
if [ -d "$DATA_DIR" ] && [ ! -w "$DATA_DIR" ]; then
    log WARN "Data directory is not writable by current user ($(id -un 2>/dev/null || echo 'unknown'))"
    log WARN "OAuth tokens and VPN state will not persist across restarts"
fi

LOG_FILE="${DATA_DIR}/app.log"

# =============================================================================
# Pre-VPN IP detection (for kill switch)
# =============================================================================

REAL_IP="ERROR"

if [ "${ADGUARD_USE_KILL_SWITCH,,}" = "true" ]; then
    log INFO "Detecting current IP before VPN..."

    if [ "${ADGUARD_CONNECTION_TYPE,,}" = "socks" ]; then
        log INFO "SOCKS mode: using direct IP detection"
        REAL_IP=$(get_public_ip_direct 2>/dev/null) || REAL_IP="ERROR"
    else
        REAL_IP=$(get_public_ip 2>/dev/null) || REAL_IP="ERROR"
    fi

    if [ "$REAL_IP" = "ERROR" ] || [ -z "$REAL_IP" ]; then
        log ERROR "Failed to detect current IP before VPN connection"
        log ERROR "Ensure network connectivity before starting VPN with kill switch"
        exit 1
    fi

    log INFO "Real IP recorded: ${REAL_IP}"
fi

# =============================================================================
# VPN Initialization
# =============================================================================

log INFO "Starting VPN connection..."
/opt/adguardvpn_cli/scripts/init.sh

INIT_EXIT_CODE=$?

if [ "$INIT_EXIT_CODE" -ne 0 ]; then
    log ERROR "VPN initialization failed (exit code: ${INIT_EXIT_CODE})"
    exit "$INIT_EXIT_CODE"
fi

log INFO "VPN connected successfully"

# =============================================================================
# Log File Setup
# =============================================================================

log INFO "Waiting for AdGuard VPN log file..."

while [ ! -f "$LOG_FILE" ]; do
    sleep 1 &
    wait $!
done

log INFO "Log file ready"

if [ "${ADGUARD_SHOW_LOG,,}" = "true" ]; then
    if [ "${ADGUARD_SHOW_LOG_LEVEL,,}" = "debug" ]; then
        tail -F "$LOG_FILE" &
        TAIL_PID=$!
    else
        tail -F "$LOG_FILE" | grep --line-buffered -v -i -E '(debug|trace)' 2>/dev/null &
        TAIL_PID=$!
    fi
fi

# =============================================================================
# Kill Switch Setup
# =============================================================================

if [ "${ADGUARD_USE_KILL_SWITCH,,}" = "true" ]; then
    log INFO "Activating Kill Switch..."
    log INFO "Stabilizing VPN connection (5s)..."
    sleep 5 &
    wait $!

    if [ "$REAL_IP" = "ERROR" ]; then
        log ERROR "Failed to get IP address for kill switch"
        _cleanup_and_exit 1
    fi

    if [ ! -f /opt/adguardvpn_cli/scripts/killswitch.sh ]; then
        log ERROR "Kill switch script not found"
        _cleanup_and_exit 1
    fi

    [ ! -x /opt/adguardvpn_cli/scripts/killswitch.sh ] && chmod +x /opt/adguardvpn_cli/scripts/killswitch.sh

    export REAL_IP_BEFORE_VPN="$REAL_IP"

    /opt/adguardvpn_cli/scripts/killswitch.sh "$REAL_IP" &
    KILL_PID=$!

    if ! kill -0 "${KILL_PID}" 2>/dev/null; then
        log ERROR "Kill switch failed to start"
        _cleanup_and_exit 1
    fi

    log INFO "Kill switch activated (PID: ${KILL_PID})"
    log INFO "Kill switch monitoring active"

    while kill -0 "${KILL_PID}" 2>/dev/null; do
        sleep 60 &
        wait $!
        log INFO "Kill switch heartbeat — PID ${KILL_PID} running"
    done

    log WARN "Kill switch process exited — container shutting down"
    _cleanup_and_exit 1

else
    log WARN "Kill Switch DISABLED — container will continue even if VPN fails"
    log INFO "Monitoring AdGuard VPN log only"

    [ -n "${TAIL_PID:-}" ] && wait "${TAIL_PID}" || true
fi
