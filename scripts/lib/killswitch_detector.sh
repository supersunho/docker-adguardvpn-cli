#!/bin/bash
#
# AdGuard VPN -- Kill Switch Detection Functions
#
# Pure detection logic for the kill switch state machine.
# These functions have no side effects -- they only inspect
# the environment and return results.
#
# Functions:
#   ks_detect_initial_ip        -- Record the real IP before VPN connects
#   ks_wait_for_vpn_tunnel      -- Wait up to MAX_WAIT_TIME for tunnel activation
#   ks_detect_current_ip        -- Get current public IP with retries
#   ks_is_vpn_connected         -- Check if VPN service is running
#   ks_is_leak                  -- Compare current IP to original IP
#   ks_detect_ip_change         -- Detect if VPN IP has changed

# =============================================================================
# Configuration (from environment or defaults)
# =============================================================================

readonly KS_MAX_WAIT_TIME="${ADGUARD_MAX_WAIT_TIME:-60}"
# Default check interval is 8s (reduced from 15s to limit unprotected traffic window).
# During LEAK_WARNING state, the interval halves for faster detection.
# Override via ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL environment variable.
readonly KS_CHECK_INTERVAL="${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL:-8}"
# Optional SOCKS-mode check interval. Each iteration probes the public IP
# through the proxy, so a longer interval reduces external call frequency in
# SOCKS mode. Falls back to KS_CHECK_INTERVAL when unset or invalid.
KS_SOCKS_CHECK_INTERVAL_CANDIDATE="${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL:-${KS_CHECK_INTERVAL}}"
if ! [[ "$KS_SOCKS_CHECK_INTERVAL_CANDIDATE" =~ ^[1-9][0-9]*$ ]]; then
    log WARN "Invalid ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL=${KS_SOCKS_CHECK_INTERVAL_CANDIDATE}, falling back to ${KS_CHECK_INTERVAL}"
    KS_SOCKS_CHECK_INTERVAL_CANDIDATE="$KS_CHECK_INTERVAL"
fi
readonly KS_SOCKS_CHECK_INTERVAL="$KS_SOCKS_CHECK_INTERVAL_CANDIDATE"
unset KS_SOCKS_CHECK_INTERVAL_CANDIDATE
readonly KS_MAX_LEAK_TOLERANCE="${ADGUARD_MAX_LEAK_TOLERANCE:-0}"
readonly KS_LEAK_WARNING_ONLY="${ADGUARD_LEAK_WARNING_ONLY:-false}"
readonly KS_IP_RETRY_COUNT="${ADGUARD_MAX_IP_DETECTION_RETRIES:-3}"
readonly KS_IP_RETRY_DELAY="${ADGUARD_IP_DETECTION_RETRY_DELAY:-10}"

# Locked IP detection method ID — once set, all subsequent checks reuse the same
# HTTP method for consistent results (no shuffle, no DNS/HTTP mismatch).
KS_LOCKED_HTTP_ID=""

# =============================================================================
# Consistent IP detection for kill switch monitoring
# =============================================================================

# First call discovers a working HTTP method (tried in fixed order, no shuffle)
# and locks to it for all subsequent calls.
# DNS is intentionally skipped: in TUN mode DNS may bypass the VPN tunnel
# and return a different IP than tunneled HTTP traffic.
# Usage: ip=$(ks_detect_ip_consistent)
# Returns: IP on stdout, or "ERROR" on failure
ks_detect_ip_consistent() {
    local use_socks5=false
    if is_socks_mode; then
        use_socks5=true
    fi

    if [ -n "$KS_LOCKED_HTTP_ID" ]; then
        # Locked — use the same method every time
        local ip
        ip=$(_ip_run_http_method "$KS_LOCKED_HTTP_ID" "$use_socks5" 2>/dev/null) || ip=""
        if _is_valid_ipv4 "$ip"; then
            echo "$ip"
            return 0
        fi
        ## Locked method failed -- drop the lock so the next call will
        ## re-discover a working HTTP method.  Without this, a transient
        ## outage of the locked service makes every subsequent detection
        ## return ERROR until the kill switch is restarted, which causes
        ## the tunnel to be torn down even though other services still work.
        log WARN "Locked HTTP method ${KS_LOCKED_HTTP_ID} failed; re-discovering on next call"
        KS_LOCKED_HTTP_ID=""
        return 1
    fi

    # First call — discover a working HTTP method in fixed order (no shuffle).
    for id in "${_IP_HTTP_SERVICES[@]}"; do
        local ip
        ip=$(_ip_run_http_method "$id" "$use_socks5" 2>/dev/null) || ip=""
        if _is_valid_ipv4 "$ip"; then
            KS_LOCKED_HTTP_ID="$id"
            log INFO "IP detection locked to HTTP method ${id} — IP: ${ip}"
            echo "$ip"
            return 0
        fi
    done

    echo "ERROR"
    return 1
}

# =============================================================================
# Record the real IP before VPN connection
# =============================================================================

# Usage: ks_detect_initial_ip
# Returns: 0 on success, 1 on failure
# Sets: KS_REAL_IP (global) on success
ks_detect_initial_ip() {
    KS_REAL_IP=""

    if is_socks_mode; then
        log DEBUG "SOCKS mode: using direct IP detection"
        KS_REAL_IP=$(get_public_ip_direct 2>/dev/null) || true
    else
        local ip
        ip=$(get_public_ip 2>/dev/null) || true
        KS_REAL_IP="$ip"
    fi

    if [ -z "$KS_REAL_IP" ] || [ "$KS_REAL_IP" = "ERROR" ]; then
        log ERROR "Failed to detect initial real IP"
        return 1
    fi

    log INFO "Real IP recorded: ${KS_REAL_IP}"
    return 0
}

# =============================================================================
# Wait for VPN tunnel activation
# =============================================================================

# Polls every 2 seconds up to KS_MAX_WAIT_TIME seconds.
# Every 5 seconds during the wait, logs a progress message so the user
# can see the kill switch is actively waiting for the tunnel.
# Usage: ks_wait_for_vpn_tunnel
# Returns: 0 if tunnel is active, 1 on timeout
ks_wait_for_vpn_tunnel() {
    local elapsed=0 poll_interval=2

    log INFO "Waiting for VPN tunnel to activate (max ${KS_MAX_WAIT_TIME}s)..."

    while [ "$elapsed" -lt "$KS_MAX_WAIT_TIME" ]; do
        if check_adguard_vpn_status; then
            if is_socks_mode; then
                if ks_socks_port_listening; then
                    log INFO "VPN tunnel active (SOCKS5 proxy listening, status=Connected)"
                    ## Set KS_VPN_IP to a sentinel (KS_REAL_IP) so
                    ## downstream callers can safely inspect it before the
                    ## first real proxy egress probe in the main loop.
                    KS_VPN_IP="$KS_REAL_IP"
                    return 0
                fi
                log DEBUG "VPN status is Connected; waiting for SOCKS5 listener..."
            else
                local temp_ip
                temp_ip=$(ks_detect_ip_consistent 2>/dev/null) || true
                if [ -n "$temp_ip" ] && [ "$temp_ip" != "ERROR" ]; then
                    if [ "$temp_ip" != "$KS_REAL_IP" ]; then
                        log INFO "VPN tunnel active, IP changed to ${temp_ip}"
                        KS_VPN_IP="$temp_ip"
                        return 0
                    fi
                    ## VPN status reports Connected but the detected IP
                    ## still matches the pre-VPN real IP.  This is the
                    ## classic TUN propagation race; keep polling until the
                    ## route has actually changed.
                    log INFO "VPN status reports Connected; waiting for IP to change (${elapsed}s elapsed)"
                fi
            fi

            if [ $((elapsed % 5)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
                if [ "${ADGUARD_SHOW_LOG:-true}" = "true" ]; then
                    log INFO "Waiting for tunnel propagation... (${elapsed}s / ${KS_MAX_WAIT_TIME}s max)"
                fi
            fi
        ## In SOCKS mode, the adguardvpn-cli status output is unstable:
        ## 5-8 seconds after the initial Connected message, the daemon
        ## can report Disconnected in steady state even though the SOCKS5
        ## proxy is still actively listening.  When the status check fails
        ## in SOCKS mode, fall back to the most authoritative signal we
        ## have: a "Successfully Connected" line in the tunnel log
        ## (proves the tunnel was up at least once) AND the SOCKS5 port
        ## still listening on the configured ADGUARD_SOCKS5_PORT (proves
        ## the tunnel is up right now).  Both conditions must hold;
        ## otherwise the tunnel truly is down and we keep waiting.
        elif is_socks_mode && ks_tunnel_connected_in_log && ks_socks_port_listening; then
            log INFO "VPN tunnel active (SOCKS5 proxy listening, status=Disconnected in steady state)"
            ## Keep the same sentinel used by the Connected-status branch so
            ## callers running with `set -u` can safely inspect KS_VPN_IP.
            KS_VPN_IP="$KS_REAL_IP"
            return 0
        else
            log DEBUG "VPN not connected yet..."
        fi


        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done

    log ERROR "Timed out waiting for VPN tunnel (${KS_MAX_WAIT_TIME}s)"
    return 1
}

# =============================================================================
# Detect current IP with retry logic
# =============================================================================

# Usage: ks_detect_current_ip
# Returns: 0 on success, 1 on failure (all retries exhausted)
# Sets: KS_CURRENT_IP (global) with the detected IP
ks_detect_current_ip() {
    #### In SOCKS mode, a Connected status or listening port is only a
    #### liveness hint.  Always probe through the configured proxy so the
    #### kill switch can detect both proxy failure and direct-IP fallback.
    #### The retry loop below provides transient-startup tolerance.
    if is_socks_mode && ! ks_socks_port_listening; then
        log ERROR "SOCKS5 proxy port is not listening"
        return 1
    fi

    KS_CURRENT_IP=""
    local attempt=1

    while [ "$attempt" -le "$KS_IP_RETRY_COUNT" ]; do
        log DEBUG "IP detection attempt ${attempt}/${KS_IP_RETRY_COUNT}"
        local ip
        ip=$(ks_detect_ip_consistent 2>/dev/null) || true

        if [ -n "$ip" ] && [ "$ip" != "ERROR" ]; then
            KS_CURRENT_IP="$ip"
            log DEBUG "IP detected: ${KS_CURRENT_IP}"
            return 0
        fi

        if [ "$attempt" -lt "$KS_IP_RETRY_COUNT" ]; then
            log WARN "IP detection failed, retrying in ${KS_IP_RETRY_DELAY}s..."
            sleep "$KS_IP_RETRY_DELAY"
        fi
        attempt=$((attempt + 1))
    done

    log ERROR "All IP detection retries exhausted"
    return 1
}

# Check if the VPN service is currently connected.
ks_is_vpn_connected() {
    #### In SOCKS mode, adguardvpn-cli status output is unstable after the
    #### initial Connected message — it can report Disconnected in steady
    #### state even though the SOCKS5 proxy is still listening.  We treat
    #### the local SOCKS5 listener as authoritative when configured for
    #### SOCKS mode; the HTTP status check is the fallback for TUN.
    if is_socks_mode && ks_socks_port_listening; then
        return 0
    fi
    check_adguard_vpn_status
}

# Check if the configured SOCKS5 port is currently listening on localhost.
# Returns 0 if a TCP listener is observed on the port, 1 otherwise.
ks_socks_port_listening() {
    local port="${ADGUARD_SOCKS5_PORT:-1080}"
    case "$(uname -s)" in
        Linux)
            _ks_port_listening_linux "$port"
            ;;
        Darwin)
            _ks_port_listening_darwin "$port"
            ;;
        *)
            log WARN "ks_socks_port_listening: unsupported OS $(uname -s); failing closed"
            return 1
            ;;
    esac
}

# Linux implementation: parse /proc/net/tcp and /proc/net/tcp6 for state 0A (LISTEN).
_ks_port_listening_linux() {
    local port="$1"
    local proc_net_dir="${KS_PROC_NET_DIR:-/proc/net}"
    local hex_port
    hex_port=$(printf '%04X' "$port")
    awk -v want="$hex_port" \
        '$2 ~ /:'"$hex_port"'$/ && $4 == "0A" {found=1; exit} END{exit !found}' \
        "${proc_net_dir}/tcp" "${proc_net_dir}/tcp6" 2>/dev/null
}

# Darwin (macOS) implementation: use lsof to find a LISTEN socket on the port.
# `lsof` is shipped with macOS by default and is available without extra deps.
_ks_port_listening_darwin() {
    local port="$1"
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

# Check if the adguardvpn-cli tunnel log contains a successful Connected
# entry.  Used as a one-shot liveness check for SOCKS mode: the SOCKS5
# port listening proves the tunnel is up right now, and the log check
# proves it has been up at least once (so we are not just hitting a
# port that some other process is squatting on).
# Returns: 0 if "Successfully Connected" line found, 1 otherwise.
ks_tunnel_connected_in_log() {
    local log_path="${ADGUARD_TUNNEL_LOG_PATH:-/home/appuser/.local/share/adguardvpn-cli/tunnel.log}"
    [ -r "$log_path" ] || return 1
    grep -q "Successfully Connected" "$log_path" 2>/dev/null
}
# Check if the current IP represents a leak (matches the original real IP).
ks_is_leak() {
    [ "$KS_CURRENT_IP" = "$KS_REAL_IP" ]
}

# Detect if the VPN IP has changed since last check.
# Sets: KS_VPN_IP (global) when appropriate
ks_detect_ip_change() {
    if [ -n "$KS_CURRENT_IP" ] && [ "$KS_CURRENT_IP" != "$KS_VPN_IP" ] && \
       [ "$KS_CURRENT_IP" != "$KS_REAL_IP" ]; then
        log INFO "VPN IP changed: ${KS_VPN_IP:-none} -> ${KS_CURRENT_IP}"
        KS_VPN_IP="$KS_CURRENT_IP"
        return 0
    fi
    return 0
}
