#!/bin/bash
#
# AdGuard VPN -- Network utilities
#
# Provides safe, array-based wrappers around curl and dig that avoid eval.
# All commands are built as bash arrays and executed directly.
#
# Functions:
#   curl_get <url>              -- Perform an HTTP GET with curl
#   dig_get <method_args...>    -- Perform a DNS query with dig
#   socks5_curl_get <url>       -- Perform an HTTP GET via SOCKS5 proxy
#   network_init_socks          -- Initialize SOCKS5 listen and auth settings
#   is_socks_mode               -- Check if connection mode is SOCKS

# =============================================================================
# Utility
# =============================================================================

# Build base curl arguments common to all direct HTTP requests
_curl_base_args() {
    echo '-4' '-s' '--connect-timeout' '5' '--max-time' '10'
}

# Build curl arguments for SOCKS5 proxied requests
_curl_socks5_args() {
    local proxy_url="socks5://${ADGUARD_SOCKS5_HOST:-127.0.0.1}:${ADGUARD_SOCKS5_PORT:-1080}"
    local args=('-4' '-s' '--connect-timeout' '5' '--max-time' '10' '-x' "$proxy_url")

    if [ -n "${ADGUARD_SOCKS5_USERNAME:-}" ] && [ -n "${ADGUARD_SOCKS5_PASSWORD:-}" ]; then
        args+=('-U' "${ADGUARD_SOCKS5_USERNAME}:${ADGUARD_SOCKS5_PASSWORD}")
    fi

    echo "${args[@]}"
}

# =============================================================================
# Public functions
# =============================================================================

# Perform a direct HTTP GET request
# Usage: curl_get <url>
# Returns: the response body on stdout
curl_get() {
    local url="${1:?curl_get: url required}"
    local -a args
    read -ra args <<< "$(_curl_base_args)"
    args+=("$url")
    curl "${args[@]}" 2>/dev/null
}

# Perform a SOCKS5-proxied HTTP GET request
# Usage: socks5_curl_get <url>
# Returns: the response body on stdout
socks5_curl_get() {
    local url="${1:?socks5_curl_get: url required}"
    local -a args
    read -ra args <<< "$(_curl_socks5_args)"
    args+=("$url")
    curl "${args[@]}" 2>/dev/null
}

# Perform a DNS TXT/CH query to discover the public IP
# Usage: dig_get <dig arguments...>
# Example: dig_get +short myip.opendns.com @resolver1.opendns.com
# Returns: the query result on stdout
dig_get() {
    if [ $# -eq 0 ]; then
        log ERROR "dig_get: at least one argument required"
        return 1
    fi
    dig "$@" 2>/dev/null | head -n1 | tr -d '\n\r '
}

# Shuffle an array in-place (Fisher-Yates).
# Usage: shuffle_array <array_name>
# Example: shuffle_array myarr
shuffle_array() {
    local -n arr=$1
    local i tmp size rand
    size=${#arr[*]}
    for (( i=size-1; i>0; i-- )); do
        rand=$((RANDOM % (i+1)))
        tmp=${arr[i]}; arr[i]=${arr[rand]}; arr[rand]=$tmp
    done
}

# Check if connection mode is SOCKS
# Returns 0 (true) if SOCKS, 1 (false) otherwise
is_socks_mode() {
    local mode="${ADGUARD_CONNECTION_TYPE,,}"
    [ "$mode" = "socks" ]
}

# Initialize SOCKS5 listen and authentication settings.
# Usage: network_init_socks
network_init_socks() {
    if ! is_socks_mode; then
        log DEBUG "Skipping SOCKS init: connection type is TUN"
        return 0
    fi

    log INFO "Initializing SOCKS5 proxy configuration"

    adguardvpn-cli config set-socks-host "127.0.0.1"
    adguardvpn-cli config clear-socks-auth

    if [ -n "${ADGUARD_SOCKS5_USERNAME:-}" ]; then
        adguardvpn-cli config set-socks-username "$ADGUARD_SOCKS5_USERNAME"
    fi
    if [ -n "${ADGUARD_SOCKS5_PASSWORD:-}" ]; then
        adguardvpn-cli config set-socks-password "$ADGUARD_SOCKS5_PASSWORD"
    fi
    if [ -n "${ADGUARD_SOCKS5_PORT:-}" ]; then
        adguardvpn-cli config set-socks-port "$ADGUARD_SOCKS5_PORT"
    fi
    if [ -n "${ADGUARD_SOCKS5_HOST:-}" ]; then
        adguardvpn-cli config set-socks-host "$ADGUARD_SOCKS5_HOST"
    fi

    log INFO "SOCKS5 proxy configuration complete"
}
