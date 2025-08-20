#!/bin/bash

# =============================================================================
# AdGuard VPN Utility Functions - Minimal Logging Version
# =============================================================================
# Functions for IP detection and VPN status checking with concise logging
# - get_public_ip(): Detects public IP using DNS/HTTP methods  
# - check_adguard_vpn_status(): Checks AdGuard VPN connection status
# =============================================================================
log() { echo -e "[$(basename "${BASH_SOURCE[1]}" .sh)] $1"; }
# =============================================================================
# Public IP Detection Function
# =============================================================================
get_public_ip() {
    local ip=""
    
    # DNS methods (fastest)
    local dns_methods=(
        "OpenDNS|dig +short myip.opendns.com @resolver1.opendns.com"
        "Google DNS|dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'\"' '{print \$2}'"
        "Cloudflare 1.0.0.1|dig +short txt ch whoami.cloudflare @1.0.0.1 | tr -d '\"'"
        "Cloudflare 1.1.1.1|dig +short txt ch whoami.cloudflare @1.1.1.1 | tr -d '\"'"
    )
    
    # HTTP services (backup)
    local http_services=(
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
    
    # Shuffle array function
    shuffle_array() {
        local -n arr=$1
        local i tmp size rand
        size=${#arr[*]}
        for (( i=size-1; i>0; i-- )); do
            rand=$((RANDOM % (i+1)))
            tmp=${arr[i]}; arr[i]=${arr[rand]}; arr[rand]=$tmp
        done
    }
    
    # Try DNS methods first
    if command -v dig >/dev/null 2>&1; then
        log "📡 Trying DNS methods..." >&2
        shuffle_array dns_methods
        
        for method in "${dns_methods[@]}"; do
            IFS='|' read -r name command <<< "$method"
            log "🔍 $name" >&2
            
            ip=$(eval "$command" 2>/dev/null | head -n1 | tr -d '\n\r ')
            
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log "✅ $name: $ip" >&2
                echo "$ip"
                return 0
            else
                log "❌ $name failed" >&2
            fi
        done
        
        log "⚠️ DNS methods failed, trying HTTP..." >&2
    else
        log "⚠️ dig not available, using HTTP only" >&2
    fi
    
    # Try HTTP services
    log "🌐 Trying HTTP services..." >&2
    shuffle_array http_services
    
    for service in "${http_services[@]}"; do
        IFS='|' read -r name url <<< "$service"
        log "🔍 $name" >&2
        
        ip=$(curl -4 -s --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | head -n1 | tr -d '\n\r ')
        
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log "✅ $name: $ip" >&2
            echo "$ip"
            return 0
        else
            log "❌ $name failed" >&2
        fi
    done
    
    # All methods failed
    log "🚨 All IP detection methods failed!" >&2
    log "🔌 Check network connectivity" >&2
    
    echo "ERROR"
    return 1
}

# =============================================================================
# AdGuard VPN Status Check Function
# =============================================================================
check_adguard_vpn_status() {
    # Check if CLI tool exists
    if ! command -v adguardvpn-cli >/dev/null 2>&1; then
        log "🚨 adguardvpn-cli not found!" >&2
        return 1
    fi
    
    # Get VPN status
    local status=$(adguardvpn-cli status 2>/dev/null)
    
    # Check if connected
    if [[ $status =~ Connected.*mode ]]; then
        # Determine mode
        if [[ $status =~ TUN\ mode ]]; then
            log "✅ VPN connected (TUN mode)" >&2
        elif [[ $status =~ SOCKS\ mode ]]; then
            log "✅ VPN connected (SOCKS mode)" >&2
        else
            log "✅ VPN connected" >&2
        fi
        return 0
    else
        log "❌ VPN not connected" >&2
        [ -z "$status" ] && log "⚠️ Empty status response" >&2
        return 1
    fi
}

# =============================================================================
# End of Utility Functions
# =============================================================================
