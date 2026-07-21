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
readonly KS_CHECK_INTERVAL="${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL:-15}"
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
        # Locked method failed — treat as ERROR (kill switch will retry via caller)
        echo "ERROR"
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
            local temp_ip
            temp_ip=$(ks_detect_ip_consistent 2>/dev/null) || true
            if [ -n "$temp_ip" ] && [ "$temp_ip" != "ERROR" ] && \
               [ "$temp_ip" != "$KS_REAL_IP" ]; then
                log INFO "VPN tunnel active, IP changed to ${temp_ip}"
                KS_VPN_IP="$temp_ip"
                return 0
            fi

            if [ $((elapsed % 5)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
                if [ "${ADGUARD_SHOW_LOG:-true}" = "true" ]; then
                    log INFO "Waiting for tunnel propagation... (${elapsed}s / ${KS_MAX_WAIT_TIME}s max)"
                fi
            fi
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
    check_adguard_vpn_status
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
