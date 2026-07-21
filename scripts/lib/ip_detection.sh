#!/bin/bash
#
# AdGuard VPN -- IP Detection
#
# Unified public IP detection supporting direct and SOCKS5 modes.
# Merges the previous duplicate get_public_ip(), get_public_ip_direct(),
# and associated HTTP-command helpers from utils.sh.
#
# Functions:
#   get_public_ip           -- Detect public IP using DNS + HTTP methods
#   get_public_ip_direct    -- Detect public IP via direct HTTP (no proxy)
#   _ip_detect_dns          -- Internal: DNS-based IP detection
#   _ip_detect_http         -- Internal: HTTP-based IP detection

# =============================================================================
# Configuration
# =============================================================================

# Ordered list of DNS-based discovery methods.
# Post-processing (quote stripping for TXT records) is handled uniformly
# in _ip_detect_dns — no need for inline awk/tr pipelines.
_IP_DNS_METHODS=(
    "OpenDNS|dig_get +short myip.opendns.com @resolver1.opendns.com"
    "Google|dig_get TXT +short o-o.myaddr.l.google.com @ns1.google.com"
    "Cloudflare1001|dig_get +short txt ch whoami.cloudflare @1.0.0.1"
    "Cloudflare1111|dig_get +short txt ch whoami.cloudflare @1.1.1.1"
)

# Ordered list of HTTP-based discovery services
_IP_HTTP_SERVICES=(
    "AWS|https://checkip.amazonaws.com"
    "IPify|https://api.ipify.org"
    "IPinfo|https://ipinfo.io/ip"
    "ifconfig.co|https://ifconfig.co"
    "icanhazip|https://icanhazip.com"
    "IPecho|https://ipecho.net/plain"
    "ident.me|https://ident.me"
    "DNS-O-Matic|https://myip.dnsomatic.com"
    "ifconfig.me|https://ifconfig.me/ip"
)

# =============================================================================
# IP address validation
# =============================================================================

_is_valid_ipv4() {
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# =============================================================================
# Internal: DNS-based detection
# =============================================================================

# Returns: IP on stdout, or empty string on failure
_ip_detect_dns() {
    local method_name method_command ip

    # Only works in TUN mode (DNS queries bypass SOCKS proxy)
    if is_socks_mode; then
        return 0  # empty = no result
    fi

    if ! command -v dig >/dev/null 2>&1; then
        log DEBUG "dig not available, skipping DNS detection"
        return 0
    fi

    local -a methods=("${_IP_DNS_METHODS[@]}")
    shuffle_array methods

    for entry in "${methods[@]}"; do
        IFS='|' read -r method_name method_command <<< "$entry"
        log DEBUG "DNS: testing ${method_name}"

        # Split command string into array for safe execution without eval.
        # The command is a function call (dig_get) with its arguments, e.g.
        #   "dig_get +short myip.opendns.com @resolver1.opendns.com"
        local -a cmd_parts=()
        read -ra cmd_parts <<< "$method_command"
        ip=$("${cmd_parts[@]}" 2>/dev/null)

        # Strip quotes for TXT-record results (e.g. Cloudflare, Google)
        if ! _is_valid_ipv4 "$ip"; then
            ip=$(echo "$ip" | tr -d '"')
        fi

        if _is_valid_ipv4 "$ip"; then
            log DEBUG "DNS: ${method_name} -> ${ip}"
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
# If use_socks5 is true, routes through SOCKS5 proxy
_ip_detect_http() {
    local use_socks5="${1:-false}"
    local name url ip

    local -a services=("${_IP_HTTP_SERVICES[@]}")
    shuffle_array services

    for entry in "${services[@]}"; do
        IFS='|' read -r name url <<< "$entry"
        log DEBUG "HTTP: testing ${name} $([ "$use_socks5" = true ] && echo '[via SOCKS5]' || echo '[direct]')"

        if [ "$use_socks5" = true ]; then
            ip=$(socks5_curl_get "$url")
        else
            ip=$(curl_get "$url")
        fi

        if _is_valid_ipv4 "$ip"; then
            log DEBUG "HTTP: ${name} -> ${ip}"
            echo "$ip"
            return 0
        fi
    done

    return 0  # no result found
}

# =============================================================================
# Save / load persistent method for faster subsequent lookups
# =============================================================================

_IP_METHOD_FILE="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"

_ip_save_method() {
    local type="$1" name="$2" data="$3"
    mkdir -p "$(dirname "$_IP_METHOD_FILE")" 2>/dev/null || true
    echo "${type}|${name}|${data}" >> "$_IP_METHOD_FILE"
}

_ip_load_methods() {
    local saved_dns="" saved_http=""
    if [ ! -f "$_IP_METHOD_FILE" ]; then
        echo "" ""
        return
    fi
    while IFS='|' read -r type name data; do
        if [ "$type" = "dns" ]; then
            saved_dns="${name}|${data}"
        elif [ "$type" = "http" ]; then
            saved_http="${name}|${data}"
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

    # Try saved methods first (fast path)
    local saved_dns saved_http
    read -r saved_dns saved_http <<< "$(_ip_load_methods)"

    # --- DNS detection --------------------------------------------------------
    if [ -n "$saved_dns" ] && [ "$use_socks5" = false ]; then
        IFS='|' read -r _ saved_cmd <<< "$saved_dns"
        # Execute saved command via array (no eval)
        local -a cmd_parts=()
        read -ra cmd_parts <<< "$saved_cmd"
        dns_ip=$("${cmd_parts[@]}" 2>/dev/null)
        # Strip quotes for TXT-record results
        if ! _is_valid_ipv4 "$dns_ip"; then
            dns_ip=$(echo "$dns_ip" | tr -d '"')
        fi
        if _is_valid_ipv4 "$dns_ip"; then
            log DEBUG "DNS: reused saved method -> ${dns_ip}"
        else
            dns_ip=""
        fi
    fi

    if [ -z "$dns_ip" ] && [ "$use_socks5" = false ]; then
        dns_ip=$(_ip_detect_dns)
    fi

    # --- HTTP detection -------------------------------------------------------
    if [ -n "$saved_http" ]; then
        if [ "$use_socks5" = true ]; then
            http_ip=$(socks5_curl_get "$(echo "$saved_http" | cut -d'|' -f3)" 2>/dev/null)
        else
            http_ip=$(curl_get "$(echo "$saved_http" | cut -d'|' -f3)" 2>/dev/null)
        fi
        if _is_valid_ipv4 "$http_ip"; then
            log DEBUG "HTTP: reused saved method -> ${http_ip}"
        else
            http_ip=""
        fi
    fi

    if [ -z "$http_ip" ]; then
        http_ip=$(_ip_detect_http "$use_socks5")
    fi

    # --- Result reconciliation ------------------------------------------------
    rm -f "$_IP_METHOD_FILE"

    if [ -n "$dns_ip" ] && [ -n "$http_ip" ]; then
        if [ "$dns_ip" = "$http_ip" ]; then
            # Consistent -- save both methods
            _ip_save_method "dns"  "${_IP_DNS_METHODS[0]%%|*}" "${_IP_DNS_METHODS[0]#*|}"
            _ip_save_method "http" "${_IP_HTTP_SERVICES[0]%%|*}" "${_IP_HTTP_SERVICES[0]#*|}"
            echo "$dns_ip"
            return 0
        else
            # Mismatch -- prefer HTTP in SOCKS mode, DNS in TUN mode
            if [ "$use_socks5" = true ]; then
                echo "$http_ip"
            else
                echo "$dns_ip"
            fi
            return 0
        fi
    elif [ -n "$dns_ip" ]; then
        _ip_save_method "dns" "${_IP_DNS_METHODS[0]%%|*}" "${_IP_DNS_METHODS[0]#*|}"
        echo "$dns_ip"
        return 0
    elif [ -n "$http_ip" ]; then
        _ip_save_method "http" "${_IP_HTTP_SERVICES[0]%%|*}" "${_IP_HTTP_SERVICES[0]#*|}"
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
    ip=$(_ip_detect_http false)

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
