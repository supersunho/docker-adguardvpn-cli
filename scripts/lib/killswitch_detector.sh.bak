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

readonly KS_MAX_WAIT_TIME="${ADGUARD_MAX_WAIT_TIME:-30}"
readonly KS_CHECK_INTERVAL="${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL:-15}"
readonly KS_MAX_LEAK_TOLERANCE="${ADGUARD_MAX_LEAK_TOLERANCE:-0}"
readonly KS_LEAK_WARNING_ONLY="${ADGUARD_LEAK_WARNING_ONLY:-false}"
readonly KS_IP_RETRY_COUNT="${ADGUARD_MAX_IP_DETECTION_RETRIES:-3}"
readonly KS_IP_RETRY_DELAY="${ADGUARD_IP_DETECTION_RETRY_DELAY:-10}"

# =============================================================================
# Detection functions
# =============================================================================

# Record the real IP before VPN connection.
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

# Wait for the VPN tunnel to become active.
# Polls every 2 seconds up to KS_MAX_WAIT_TIME seconds.
# Usage: ks_wait_for_vpn_tunnel
# Returns: 0 if tunnel is active, 1 on timeout
ks_wait_for_vpn_tunnel() {
    local elapsed=0 poll_interval=2

    log INFO "Waiting for VPN tunnel to activate (max ${KS_MAX_WAIT_TIME}s)..."

    while [ "$elapsed" -lt "$KS_MAX_WAIT_TIME" ]; do
        if check_adguard_vpn_status; then
            # Tunnel says connected -- verify IP has changed
            local temp_ip
            temp_ip=$(get_public_ip 2>/dev/null) || true
            if [ -n "$temp_ip" ] && [ "$temp_ip" != "ERROR" ] && \
               [ "$temp_ip" != "$KS_REAL_IP" ]; then
                log INFO "VPN tunnel active, IP changed to ${temp_ip}"
                KS_VPN_IP="$temp_ip"
                return 0
            fi
            log DEBUG "VPN connected but tunnel not ready yet..."
        else
            log DEBUG "VPN not connected yet..."
        fi

        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done

    log ERROR "Timed out waiting for VPN tunnel (${KS_MAX_WAIT_TIME}s)"
    return 1
}

# Detect the current public IP with retry logic.
# Usage: ks_detect_current_ip
# Returns: 0 on success, 1 on failure (all retries exhausted)
# Sets: KS_CURRENT_IP (global) with the detected IP
ks_detect_current_ip() {
    KS_CURRENT_IP=""
    local attempt=1

    while [ "$attempt" -le "$KS_IP_RETRY_COUNT" ]; do
        log DEBUG "IP detection attempt ${attempt}/${KS_IP_RETRY_COUNT}"
        local ip
        ip=$(get_public_ip 2>/dev/null) || true

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
# Usage: if ks_is_vpn_connected; then echo "VPN is up"; fi
ks_is_vpn_connected() {
    check_adguard_vpn_status
}

# Check if the current IP represents a leak (matches the original real IP).
# Usage: if ks_is_leak; then echo "LEAK DETECTED"; fi
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
        return 0  # IP changed
    fi
    return 1  # no change
}
