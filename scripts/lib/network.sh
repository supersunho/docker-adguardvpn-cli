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

# Track temporary curl config files for automatic cleanup on container exit.
# Used by _curl_socks5_args() to avoid credential exposure in ps(1).
_CURL_CONFIG_FILES=()
_CURL_CONFIG_CLEANUP_REGISTERED=false

_cleanup_curl_config_files() {
    local f
    for f in "${_CURL_CONFIG_FILES[@]:-}"; do
        rm -f "$f" 2>/dev/null || true
    done
    _CURL_CONFIG_FILES=()
}

# Escape a value for a double-quoted curl config-file parameter.
# Curl config files support the same escapes as the command-line parser. Keep
# credentials out of process arguments while preserving characters that would
# otherwise change the config-file syntax.
_curl_config_escape() {
    local value="${1-}" escaped='' char i
    for ((i=0; i<${#value}; i++)); do
        char="${value:i:1}"
        case "$char" in
            $'\n') escaped+=$'\\n' ;;
            $'\r') escaped+=$'\\r' ;;
            $'\t') escaped+=$'\\t' ;;
            $'\v') escaped+=$'\\v' ;;
            \\) escaped+=$'\\\\' ;;
            '"') escaped+=$'\\"' ;;
            *) escaped+="$char" ;;
        esac
    done
    printf '%s' "$escaped"
}

# Build base curl arguments common to all direct HTTP requests
_curl_base_args() {
    echo '-4' '-s' '--connect-timeout' '5' '--max-time' '10'
}

# Build curl arguments for SOCKS5 proxied requests using bash nameref.
# Usage: _curl_socks5_args <array_name>
#   _curl_socks5_args myarr
#   curl "${myarr[@]}"
#
# Uses a temporary curl config file for proxy credentials instead of -U to
# prevent credential exposure in process listings (fixes M-1). The proxy-user
# directive is deliberately used instead of netrc: curl netrc credentials
# authenticate the origin, not the SOCKS proxy.
# Uses nameref to avoid echo/read-ra round-trip that would mangle
# credentials with special characters (fixes M-2).
_curl_socks5_args() {
    local -n _out=$1
    local _proxy_url="socks5://${ADGUARD_SOCKS5_HOST:-127.0.0.1}:${ADGUARD_SOCKS5_PORT:-1080}"
    _out=('-4' '-s' '--connect-timeout' '5' '--max-time' '10' '-x' "$_proxy_url")

    if [ -n "${ADGUARD_SOCKS5_USERNAME:-}" ] && [ -n "${ADGUARD_SOCKS5_PASSWORD:-}" ]; then
        # Write proxy credentials to a temporary curl config file (chmod 600)
        # to avoid leaking them via ps(1) or /proc/*/cmdline within the
        # container. curl's --proxy-user is the proxy-auth mechanism;
        # --netrc-file would incorrectly apply these credentials to the
        # origin request.
        local _config_file _proxy_auth _escaped_auth
        _config_file="$(mktemp /tmp/curl-socks-config-XXXXXX 2>/dev/null)" || return 0
        if ! chmod 600 "$_config_file"; then
            rm -f "$_config_file" 2>/dev/null || true
            return 0
        fi
        _proxy_auth="${ADGUARD_SOCKS5_USERNAME}:${ADGUARD_SOCKS5_PASSWORD}"
        _escaped_auth="$(_curl_config_escape "$_proxy_auth")"
        if ! printf 'proxy-user = "%s"\n' "$_escaped_auth" > "$_config_file"; then
            rm -f "$_config_file" 2>/dev/null || true
            return 0
        fi
        _out+=('--config' "$_config_file")

        # Track for automatic cleanup (one-time registration).
        _CURL_CONFIG_FILES+=("$_config_file")
        if ! "${_CURL_CONFIG_CLEANUP_REGISTERED:-false}"; then
            _CURL_CONFIG_CLEANUP_REGISTERED=true
            trap _cleanup_curl_config_files EXIT
        fi
    fi
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
    _curl_socks5_args args
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
