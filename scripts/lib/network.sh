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

# Track temporary netrc files for automatic cleanup on container exit.
# Used by _curl_socks5_args() to avoid credential exposure in ps(1).
_NETRC_FILES=()
_NETRC_CLEANUP_REGISTERED=false

_cleanup_netrc_files() {
    local f
    for f in "${_NETRC_FILES[@]:-}"; do
        rm -f "$f" 2>/dev/null || true
    done
    _NETRC_FILES=()
}

# Build base curl arguments common to all direct HTTP requests
_curl_base_args() {
    echo '-4' '-s' '--connect-timeout' '5' '--max-time' '10'
}

# Build curl arguments for SOCKS5 proxied requests
# Uses a temporary .netrc file for credentials instead of -U to prevent
# credential exposure in process listings (fixes M-1).
_curl_socks5_args() {
    local proxy_url="socks5://${ADGUARD_SOCKS5_HOST:-127.0.0.1}:${ADGUARD_SOCKS5_PORT:-1080}"
    local args=('-4' '-s' '--connect-timeout' '5' '--max-time' '10' '-x' "$proxy_url")

    if [ -n "${ADGUARD_SOCKS5_USERNAME:-}" ] && [ -n "${ADGUARD_SOCKS5_PASSWORD:-}" ]; then
        # Write credentials to a temporary netrc file (chmod 600) to avoid
        # leaking them via ps(1) or /proc/*/cmdline within the container.
        local _netrc_file
        _netrc_file="$(mktemp /tmp/curl-socks-netrc-XXXXXX 2>/dev/null)" || return 0
        chmod 600 "$_netrc_file"
        printf 'default login %s password %s\n' \
            "${ADGUARD_SOCKS5_USERNAME}" "${ADGUARD_SOCKS5_PASSWORD}" > "$_netrc_file"
        args+=('--netrc-file' "$_netrc_file")

        # Track for automatic cleanup (one-time registration).
        _NETRC_FILES+=("$_netrc_file")
        if ! "${_NETRC_CLEANUP_REGISTERED:-false}"; then
            _NETRC_CLEANUP_REGISTERED=true
            trap _cleanup_netrc_files EXIT
        fi
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
