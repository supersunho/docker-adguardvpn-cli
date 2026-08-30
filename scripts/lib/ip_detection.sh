#!/bin/bash
#
# AdGuard VPN -- IP Detection
#
# Unified public IP detection supporting direct and SOCKS5 modes.
# Uses fixed method registries with dispatch by allowlisted ID.
# The persisted cache stores only v1|type|id records, never command strings.
#
# Functions:
#   get_public_ip           -- Detect public IP using DNS + HTTP methods
#   get_public_ip_direct    -- Detect public IP via direct HTTP (no proxy)
#   _ip_detect_dns          -- Internal: DNS-based IP detection
#   _ip_detect_http         -- Internal: HTTP-based IP detection

# =============================================================================
# Configuration
# =============================================================================

# Ordered list of DNS-based discovery method IDs.
_IP_DNS_METHODS=("opendns" "google" "cloudflare1001" "cloudflare1111")

# Ordered list of HTTP-based discovery service IDs.
_IP_HTTP_SERVICES=("aws" "ipify" "ipinfo" "ifconfig" "ident")

# Detection tracking (set by _ip_detect_* functions, consumed by caller)
_IP_LAST_DNS_ID=""
_IP_LAST_HTTP_ID=""
_IP_DETECTED_IP=""

# =============================================================================
# IP address validation
# =============================================================================

_is_valid_ipv4() {
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# =============================================================================
# Fixed dispatch: DNS method by allowlisted ID
# =============================================================================

# Usage: _ip_run_dns_method <id>
# Returns: IP on stdout, or empty string on failure
_ip_run_dns_method() {
    local id="$1"

    case "$id" in
        opendns)     dig_get +short myip.opendns.com @resolver1.opendns.com 2>/dev/null ;;
        google)
            local result
            result=$(dig_get TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null)
            echo "$result" | tr -d '"' ;;
        cloudflare1001) dig_get +short txt ch whoami.cloudflare @1.0.0.1 2>/dev/null ;;
        cloudflare1111) dig_get +short txt ch whoami.cloudflare @1.1.1.1 2>/dev/null ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# Fixed dispatch: HTTP method by allowlisted ID
# =============================================================================

# Usage: _ip_run_http_method <id> [use_socks5]
# Returns: IP on stdout, or empty string on failure
_ip_run_http_method() {
    local id="$1"
    local use_socks5="${2:-false}"

    local url=""
    case "$id" in
        aws)      url="https://checkip.amazonaws.com" ;;
        ipify)    url="https://api.ipify.org" ;;
        ipinfo)   url="https://ipinfo.io/ip" ;;
        ifconfig) url="https://ifconfig.co/ip" ;;
        ident)    url="https://ident.me" ;;
        *) return 1 ;;
    esac

    if [ "$use_socks5" = true ]; then
        socks5_curl_get "$url" 2>/dev/null
    else
        curl_get "$url" 2>/dev/null
    fi
}

# =============================================================================
# Internal: DNS-based detection
# =============================================================================

# Returns: IP on stdout, or empty string on failure
# Sets: _IP_LAST_DNS_ID to the successful method ID
_ip_detect_dns() {
    local id ip
    _IP_DETECTED_IP=""

    if is_socks_mode; then
        return 0  # DNS not available in SOCKS mode
    fi

    if ! command -v dig >/dev/null 2>&1; then
        log DEBUG "dig not available, skipping DNS detection"
        return 0
    fi

    local -a methods=("${_IP_DNS_METHODS[@]}")
    shuffle_array methods

    for id in "${methods[@]}"; do
        log DEBUG "DNS: testing ${id}"

        ip=$(_ip_run_dns_method "$id") || ip=""
        if ! _is_valid_ipv4 "$ip"; then
            # Strip quotes for TXT-record results (Cloudflare, Google)
            ip=$(echo "$ip" | tr -d '"')
        fi

        if _is_valid_ipv4 "$ip"; then
            _IP_LAST_DNS_ID="$id"
            _IP_DETECTED_IP="$ip"
            log DEBUG "DNS: ${id} -> ${ip}"
            echo "$ip"
            return 0
        fi
    done

    return 0  # no result found
}

# =============================================================================
# Internal: HTTP-based detection
# =============================================================================

# Returns: IP on stdout, or empty string on failure
# Sets: _IP_LAST_HTTP_ID to the successful method ID
_ip_detect_http() {
    local use_socks5="${1:-false}"
    local id ip
    _IP_DETECTED_IP=""

    local -a services=("${_IP_HTTP_SERVICES[@]}")
    shuffle_array services

    for id in "${services[@]}"; do
        log DEBUG "HTTP: testing ${id} $([ "$use_socks5" = true ] && echo '[via SOCKS5]' || echo '[direct]')"

        ip=$(_ip_run_http_method "$id" "$use_socks5") || ip=""

        if _is_valid_ipv4 "$ip"; then
            _IP_LAST_HTTP_ID="$id"
            _IP_DETECTED_IP="$ip"
            log DEBUG "HTTP: ${id} -> ${ip}"
            echo "$ip"
            return 0
        fi
    done

    return 0  # no result found
}

# =============================================================================
# Save / load persistent method for faster subsequent lookups
# =============================================================================
#
# Format: v1|type|id  (e.g. v1|dns|opendns, v1|http|aws)
# Never stores command strings or executable data.
# Writes are atomic: mktemp → write → chmod 600 → mv.

_IP_METHOD_FILE="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"

# Usage: _ip_save_methods <dns_id> <http_id>
#   dns_id:  allowlisted DNS method ID, or empty
#   http_id: allowlisted HTTP method ID, or empty
_ip_save_methods() {
    local dns_id="${1:-}" http_id="${2:-}"
    local dir
    dir="$(dirname "$_IP_METHOD_FILE")"

    mkdir -p "$dir" 2>/dev/null || return 1
    chmod 700 "$dir" 2>/dev/null || return 1

    # Atomic write: mktemp in the same directory, write, chmod 600, then mv
    umask 077
    local tmpfile
    tmpfile="$(mktemp "${dir}/ip_method.XXXXXX" 2>/dev/null)" || return 1

    {
        if [ -n "$dns_id" ]; then
            printf 'v1|dns|%s\n' "$dns_id"
        fi
        if [ -n "$http_id" ]; then
            printf 'v1|http|%s\n' "$http_id"
        fi
    } > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    if ! chmod 600 "$tmpfile" || ! mv -f "$tmpfile" "$_IP_METHOD_FILE"; then
        rm -f "$tmpfile"
        return 1
    fi
}

# Load saved method IDs.
# Ignores lines that don't match v1|type|id format or unknown IDs.
# Usage: read -r saved_dns saved_http <<< "$(_ip_load_methods)"
_ip_load_methods() {
    local saved_dns="" saved_http=""

    if [ ! -f "$_IP_METHOD_FILE" ]; then
        echo "" ""
        return
    fi

    while IFS='|' read -r version type id; do
        [ "$version" != "v1" ] && continue

        if [ "$type" = "dns" ]; then
            for m in "${_IP_DNS_METHODS[@]}"; do
                [ "$id" = "$m" ] && { saved_dns="$id"; break; }
            done
        elif [ "$type" = "http" ]; then
            for m in "${_IP_HTTP_SERVICES[@]}"; do
                [ "$id" = "$m" ] && { saved_http="$id"; break; }
            done
        fi
    done < "$_IP_METHOD_FILE"

    echo "$saved_dns" "$saved_http"
}

# =============================================================================
# Public: get_public_ip
# =============================================================================

# Detect the current public IP using DNS and HTTP methods.
# In SOCKS mode, only HTTP via SOCKS5 proxy is attempted.
#
# Usage: get_public_ip
# Returns: IP address on stdout, or "ERROR" on failure
get_public_ip() {
    local dns_ip="" http_ip=""
    local use_socks5=false

    if is_socks_mode; then
        use_socks5=true
        log DEBUG "IP Detection Mode: SOCKS5 Proxy"
    else
        log DEBUG "IP Detection Mode: TUN (Direct)"
    fi

    # Reset tracking
    _IP_LAST_DNS_ID=""
    _IP_LAST_HTTP_ID=""

    # Try saved methods first (fast path)
    local saved_dns saved_http
    read -r saved_dns saved_http <<< "$(_ip_load_methods)"

    # --- DNS detection --------------------------------------------------------
    if [ -n "$saved_dns" ] && [ "$use_socks5" = false ]; then
        dns_ip=$(_ip_run_dns_method "$saved_dns" 2>/dev/null) || dns_ip=""
        if _is_valid_ipv4 "$dns_ip"; then
            _IP_LAST_DNS_ID="$saved_dns"
            log DEBUG "DNS: reused saved method ${saved_dns} -> ${dns_ip}"
        else
            dns_ip=""
        fi
    fi

    if [ -z "$dns_ip" ] && [ "$use_socks5" = false ]; then
        _ip_detect_dns >/dev/null
        dns_ip="$_IP_DETECTED_IP"
    fi

    # --- HTTP detection -------------------------------------------------------
    if [ -n "$saved_http" ]; then
        http_ip=$(_ip_run_http_method "$saved_http" "$use_socks5" 2>/dev/null) || http_ip=""
        if _is_valid_ipv4 "$http_ip"; then
            _IP_LAST_HTTP_ID="$saved_http"
            log DEBUG "HTTP: reused saved method ${saved_http} -> ${http_ip}"
        else
            http_ip=""
        fi
    fi

    if [ -z "$http_ip" ]; then
        _ip_detect_http "$use_socks5" >/dev/null
        http_ip="$_IP_DETECTED_IP"
    fi

    # --- Result reconciliation ------------------------------------------------
    rm -f "$_IP_METHOD_FILE"

    if [ -n "$dns_ip" ] && [ -n "$http_ip" ]; then
        if [ "$dns_ip" = "$http_ip" ]; then
            # Consistent -- save both methods that succeeded
            _ip_save_methods "$_IP_LAST_DNS_ID" "$_IP_LAST_HTTP_ID" || \
                log WARN "Could not persist IP detection methods"
            echo "$dns_ip"
            return 0
        else
            # Mismatch -- prefer HTTP in SOCKS mode, DNS in TUN mode
            if [ "$use_socks5" = true ]; then
                _ip_save_methods "" "$_IP_LAST_HTTP_ID" || \
                    log WARN "Could not persist IP detection method"
                echo "$http_ip"
            else
                _ip_save_methods "$_IP_LAST_DNS_ID" "" || \
                    log WARN "Could not persist IP detection method"
                echo "$dns_ip"
            fi
            return 0
        fi
    elif [ -n "$dns_ip" ]; then
        _ip_save_methods "$_IP_LAST_DNS_ID" "" || \
            log WARN "Could not persist IP detection method"
        echo "$dns_ip"
        return 0
    elif [ -n "$http_ip" ]; then
        _ip_save_methods "" "$_IP_LAST_HTTP_ID" || \
            log WARN "Could not persist IP detection method"
        echo "$http_ip"
        return 0
    fi

    if [ "$use_socks5" = true ]; then
        log ERROR "All IP detection methods failed via SOCKS5 proxy"
        log ERROR "Check SOCKS5 proxy connectivity and credentials"
    else
        log ERROR "All IP detection methods failed"
        log ERROR "Check network connectivity"
    fi
    rm -f "$_IP_METHOD_FILE"
    echo "ERROR"
    return 1
}

# =============================================================================
# Public: get_public_ip_direct
# =============================================================================

# Detect public IP using direct HTTP connections (no proxy).
# Used before VPN connection in SOCKS mode to record the real IP.
#
# Usage: get_public_ip_direct
# Returns: IP address on stdout, or "ERROR" on failure
get_public_ip_direct() {
    local ip
    _ip_detect_http false >/dev/null
    ip="$_IP_DETECTED_IP"

    if [ -n "$ip" ]; then
        log DEBUG "Direct IP detection: ${ip}"
        echo "$ip"
        return 0
    fi

    log ERROR "All direct IP detection methods failed"
    log ERROR "Check network connectivity"
    echo "ERROR"
    return 1
}
