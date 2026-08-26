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
        wait "${TAIL_PID}" 2>/dev/null || true
    fi

    if [ -n "${KILL_PID:-}" ]; then
        kill "${KILL_PID}" 2>/dev/null || true
        wait "${KILL_PID}" 2>/dev/null || true
    fi

    if [ -n "${SUPERVISE_PID:-}" ]; then
        kill "${SUPERVISE_PID}" 2>/dev/null || true
        wait "${SUPERVISE_PID}" 2>/dev/null || true
    fi

    exit "$exit_code"
}

# shellcheck disable=SC2329  # invoked via trap TERM/INT
_shutdown_handler() {
    _cleanup_and_exit 0
}

trap _shutdown_handler TERM INT

# =============================================================================
# VPN Supervisor (used when kill switch is disabled)
# =============================================================================

# Keep the container alive by periodically checking VPN status.
# Runs in the background so the container stays up even when
# ADGUARD_SHOW_LOG=false and ADGUARD_USE_KILL_SWITCH=false.
supervise_vpn() {
    # Tunnel establishment takes a few seconds after the connect child
    # spawns; treat early status checks as "still connecting" instead of
    # failing the supervisor and shutting the container down.
    # Cap each tick at 5s and the final wait at the remaining grace so a
    # user-supplied ADGUARD_VPN_STARTUP_GRACE_SECONDS=1 actually finishes in
    # ~1s rather than 5s, and grace=6 finishes in ~6s rather than 10s.
    local grace="${ADGUARD_VPN_STARTUP_GRACE_SECONDS:-30}"
    local waited=0
    local sleep_for
    while [ "${waited}" -lt "${grace}" ]; do
        if check_adguard_vpn_status; then
            break
        fi
        sleep_for=$((grace - waited))
        if [ "${sleep_for}" -gt 5 ]; then
            sleep_for=5
        fi
        sleep "${sleep_for}" &
        wait "$!"
        waited=$((waited + sleep_for))
    done

    while true; do
        if ! check_adguard_vpn_status; then
            log ERROR "VPN status check failed — supervisor exiting"
            return 1
        fi
        sleep 60 &
        wait "$!"
    done
}

# Wait for the primary runtime process while treating log output as auxiliary.
# Bash 5.1+ is available in the supported Ubuntu base images.
wait_for_runtime() {
    if [ -n "${TAIL_PID:-}" ]; then
        local completed_pid=""

        set +e
        wait -n -p completed_pid "${SUPERVISE_PID}" "${TAIL_PID}"
        set -e

        if [ "$completed_pid" = "$SUPERVISE_PID" ]; then
            log WARN "VPN supervisor exited — container shutting down"
            _cleanup_and_exit 1
        fi

        log WARN "VPN log tail exited — continuing with VPN supervisor"
        TAIL_PID=""
    fi

    # Block on supervisor (returns when VPN status check fails).
    wait "${SUPERVISE_PID}" 2>/dev/null || true
    log WARN "VPN supervisor exited — container shutting down"
    _cleanup_and_exit 1
}

# Wait for the kill switch process directly.  The child exits as soon as it
# detects a VPN failure or IP leak, so polling it with a long sleep would leave
# the container alive after protection has already failed.
wait_for_kill_switch() {
    local kill_switch_exit_code=0

    if wait "${KILL_PID}"; then
        kill_switch_exit_code=0
    else
        kill_switch_exit_code=$?
    fi

    log WARN "Kill switch process exited (code: ${kill_switch_exit_code}) — container shutting down"
    _cleanup_and_exit 1
}

# =============================================================================
# Configuration Setup (bootstrapped above)
# =============================================================================

log INFO "AdGuard VPN Container Starting"
log INFO "Kill Switch: ${ADGUARD_USE_KILL_SWITCH}"
log INFO "Connection mode: ${ADGUARD_CONNECTION_TYPE}"

ensure_data_dir() {
    local data_dir="$1"

    if [ ! -d "$data_dir" ]; then
        if mkdir -p "$data_dir" 2>/dev/null; then
            log INFO "Created data directory: ${data_dir}"
        else
            log_force ERROR "Could not create data directory: ${data_dir}"
            log_force ERROR "Verify volume mount permissions in docker-compose.yml"
            exit 78
        fi
    fi

    # Fail fast to prevent silent OAuth loss.
    if [ ! -w "$data_dir" ]; then
        local current_uid current_gid
        current_uid=$(id -u)
        current_gid=$(id -g)
        log_force ERROR "Data directory is not writable: ${data_dir}"
        log_force ERROR "Run: sudo chown -R ${current_uid}:${current_gid} ${data_dir}"
        exit 78
    fi
}

DATA_DIR="${HOME}/.local/share/adguardvpn-cli"
# Export the mounted data root so the persistent_identity module and any child
# shells derive AUTH_* / DATA_DIR consistently.
export DATA_DIR
ensure_data_dir "$DATA_DIR"

# Apply the opt-in persistent container identity before any network or CLI
# startup side effect.  The helper preserves the original exit code (78 on
# failure) so OAuth/CLI side effects are never reached.  Default
# ADGUARD_PERSISTENT_IDENTITY=false makes this a no-op that does not touch
# the filesystem or call `ip` / `sudo`.
_persistent_identity_apply_main() {
    if persistent_identity_apply; then
        return 0
    fi
    log_force ERROR "Persistent container identity initialization failed"
    return 78
}

identity_rc=0
_persistent_identity_apply_main || identity_rc=$?
if [ "${identity_rc}" -ne 0 ]; then
    exit "${identity_rc}"
fi
unset identity_rc

# =============================================================================
# Permission Setup
#
# Moved here so persistent_identity_apply (above) can fail closed at
# exit 78 BEFORE any /dev/net/tun mode change.  When the opt-in identity
# fails, neither this block nor any subsequent step (IP detection,
# init.sh, OAuth/config/connect) runs.
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

LOG_FILE="${DATA_DIR}/app.log"

# =============================================================================
# Pre-VPN IP detection (for kill switch)
# =============================================================================

REAL_IP="ERROR"

if [ "${ADGUARD_USE_KILL_SWITCH,,}" = "true" ]; then
    log INFO "Detecting current IP before VPN..."
    # Retry IP detection up to 3 times with 5s delay to tolerate transient
    # network unavailability at container startup (e.g. Docker bridge not ready).
    REAL_IP="ERROR"
    for _attempt in 1 2 3; do
        if [ "${ADGUARD_CONNECTION_TYPE,,}" = "socks" ]; then
            REAL_IP=$(get_public_ip_direct 2>/dev/null) || REAL_IP="ERROR"
        else
            REAL_IP=$(get_public_ip 2>/dev/null) || REAL_IP="ERROR"
        fi
        if [ -n "$REAL_IP" ] && [ "$REAL_IP" != "ERROR" ]; then
            break
        fi
        [ "$_attempt" -lt 3 ] && sleep 5
    done

    if [ "$REAL_IP" = "ERROR" ] || [ -z "$REAL_IP" ]; then
        log ERROR "Failed to detect current IP before VPN connection (3 attempts)"
        log ERROR "Ensure network connectivity before starting VPN with kill switch"
        exit 1
    fi

    log INFO "Real IP recorded: ${REAL_IP}"
fi

# =============================================================================
# VPN Initialization
# =============================================================================

log INFO "Starting VPN connection..."
if /opt/adguardvpn_cli/scripts/init.sh; then
    INIT_EXIT_CODE=0
else
    INIT_EXIT_CODE=$?
fi

if [ "$INIT_EXIT_CODE" -ne 0 ]; then
    log ERROR "VPN initialization failed (exit code: ${INIT_EXIT_CODE})"
    exit "$INIT_EXIT_CODE"
fi

log INFO "VPN connected successfully"

# =============================================================================
# Log File Setup
# =============================================================================

log INFO "Waiting for AdGuard VPN log file..."

_LOG_WAIT_MAX="${ADGUARD_MAX_WAIT_TIME:-60}"
_LOG_WAITED=0
while [ ! -f "$LOG_FILE" ]; do
    if [ "$_LOG_WAITED" -ge "$_LOG_WAIT_MAX" ]; then
        log WARN "Log file did not appear within ${_LOG_WAIT_MAX}s — continuing without log tail"
        break
    fi
    sleep 1 &
    wait $!
    _LOG_WAITED=$((_LOG_WAITED + 1))
done
unset _LOG_WAIT_MAX _LOG_WAITED

if [ -f "$LOG_FILE" ]; then
    log INFO "Log file ready"

    if [ "${ADGUARD_SHOW_LOG,,}" = "true" ]; then
        if [ "${ADGUARD_SHOW_LOG_LEVEL,,}" = "debug" ]; then
            tail -F --pid="$$" "$LOG_FILE" &
            TAIL_PID=$!
        else
            # --pid ensures the tail child exits when PID 1 shuts down, even
            # though the filtered mode uses a pipeline.
            tail -F --pid="$$" "$LOG_FILE" | grep --line-buffered -v -i -E '(debug|trace)' 2>/dev/null &
            TAIL_PID=$!
        fi
    fi
else
    log WARN "Continuing without AdGuard VPN log tail"
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
    wait_for_kill_switch

else
    log WARN "Kill Switch DISABLED — container will continue even if VPN fails"

    # Start VPN supervisor in background to keep container alive
    supervise_vpn &
    SUPERVISE_PID=$!
    log INFO "VPN supervisor started (PID: ${SUPERVISE_PID})"

    wait_for_runtime
fi
