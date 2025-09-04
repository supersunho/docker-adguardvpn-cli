#!/bin/bash

# =============================================================================
# AdGuard VPN Utility Functions
# =============================================================================
log() { echo -e "[$(basename "${BASH_SOURCE[1]}" .sh)] $1"; }

# =============================================================================
# Public IP Detection Function with Persistent Method Storage
# ============================================================================= 
get_public_ip() {
    local IP_METHOD_FILE="/tmp/adguard_ip_method.txt"
    local dns_ip=""
    local http_ip=""
    local dns_method=""
    local http_method=""
    
    # DNS and HTTP method arrays
    local dns_methods=(
        "OpenDNS|dig +short myip.opendns.com @resolver1.opendns.com"
        "Google DNS|dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'\"' '{print \$2}'"
        "Cloudflare 1.0.0.1|dig +short txt ch whoami.cloudflare @1.0.0.1 | tr -d '\"'"
        "Cloudflare 1.1.1.1|dig +short txt ch whoami.cloudflare @1.1.1.1 | tr -d '\"'"
    )
    
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
    
    shuffle_array() {
        local -n arr=$1
        local i tmp size rand
        size=${#arr[*]}
        for (( i=size-1; i>0; i-- )); do
            rand=$((RANDOM % (i+1)))
            tmp=${arr[i]}; arr[i]=${arr[rand]}; arr[rand]=$tmp
        done
    }
    
    # =========================================================================
    # Load saved methods or use discovery
    # =========================================================================
    local saved_dns_method=""
    local saved_http_method=""
    
    if [ -f "$IP_METHOD_FILE" ]; then
        while IFS='|' read -r type name command; do
            if [ "$type" = "dns" ]; then
                saved_dns_method="$name|$command"
            elif [ "$type" = "http" ]; then
                saved_http_method="$name|$command"
            fi
        done < "$IP_METHOD_FILE"
    fi
    
    # =========================================================================
    # DNS Method Detection
    # =========================================================================
    if [ -n "$saved_dns_method" ]; then
        IFS='|' read -r name command <<< "$saved_dns_method"
        # log "🔄 DNS: Reusing saved method ($name)" >&2
        dns_ip=$(eval "$command" 2>/dev/null | head -n1 | tr -d '\n\r ')
        
        if [[ $dns_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            dns_method="$name"
            # log "✅ DNS: $name -> $dns_ip" >&2
        else
            log "⚠️ DNS: Saved method failed, discovering new..." >&2
            dns_ip=""
        fi
    fi
    
    # =========================================================================
    # DNS discovery if no saved method or saved method failed
    # =========================================================================
    if [ -z "$dns_ip" ] && command -v dig >/dev/null 2>&1; then
        # log "📡 DNS: Discovering reliable method..." >&2
        shuffle_array dns_methods
        
        for method in "${dns_methods[@]}"; do
            IFS='|' read -r name command <<< "$method"
            # log "🔍 DNS: Testing $name" >&2
            
            local ip=$(eval "$command" 2>/dev/null | head -n1 | tr -d '\n\r ')
            
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                dns_ip="$ip"
                dns_method="$name"
                # log "✅ DNS: $name -> $ip" >&2
                break
            else
                log "❌ DNS: $name failed" >&2
            fi
        done
    fi
    
    # =========================================================================
    # HTTP discovery if no saved method or saved method failed
    # =========================================================================
    if [ -n "$saved_http_method" ]; then
        IFS='|' read -r name command <<< "$saved_http_method"
        # log "🔄 HTTP: Reusing saved method ($name)" >&2
        http_ip=$(eval "$command" 2>/dev/null | head -n1 | tr -d '\n\r ')
        
        if [[ $http_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            http_method="$name"
            # log "✅ HTTP: $name -> $http_ip" >&2
        else
            log "⚠️ HTTP: Saved method failed, discovering new..." >&2
            http_ip=""
        fi
    fi

    # =========================================================================
    # HTTP Method Detection
    # =========================================================================
    if [ -z "$http_ip" ]; then
        # log "🌐 HTTP: Discovering reliable method..." >&2
        shuffle_array http_services
        
        for service in "${http_services[@]}"; do
            IFS='|' read -r name url <<< "$service"
            log "🔍 HTTP: Testing $name" >&2
            
            local ip=$(curl -4 -s --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | head -n1 | tr -d '\n\r ')
            
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                http_ip="$ip"
                http_method="$name"
                # log "✅ HTTP: $name -> $ip" >&2
                break
            else
                log "❌ HTTP: $name failed" >&2
            fi
        done
    fi
    
    # =========================================================================
    # Results Analysis and Comparison
    # =========================================================================
    if [ -n "$dns_ip" ] && [ -n "$http_ip" ]; then
        # Both methods successful
        if [ "$dns_ip" = "$http_ip" ]; then
            # log "🎯 IP Consistency: DNS & HTTP both report $dns_ip" >&2
            # Save both successful methods
            echo "dns|$dns_method|$(get_dns_command "$dns_method")" > "$IP_METHOD_FILE"
            echo "http|$http_method|$(get_http_command "$http_method")" >> "$IP_METHOD_FILE"
            echo "$dns_ip"  # Return consistent IP
            return 0
        else
            # log "⚠️ IP Mismatch: DNS=$dns_ip, HTTP=$http_ip" >&2
            # log "📊 This could indicate network routing differences" >&2
            # Return DNS result as primary but log the difference
            echo "$dns_ip"
            return 0
        fi
        
    elif [ -n "$dns_ip" ]; then
        # Only DNS successful
        # log "📡 Only DNS method successful: $dns_ip" >&2
        echo "dns|$dns_method|$(get_dns_command "$dns_method")" > "$IP_METHOD_FILE"
        echo "$dns_ip"
        return 0
        
    elif [ -n "$http_ip" ]; then
        # Only HTTP successful
        # log "🌐 Only HTTP method successful: $http_ip" >&2
        echo "http|$http_method|$(get_http_command "$http_method")" > "$IP_METHOD_FILE"
        echo "$http_ip"
        return 0
        
    else
        # Both methods failed
        log "🚨 All IP detection methods failed!" >&2
        log "🔌 Check network connectivity" >&2
        rm -f "$IP_METHOD_FILE"  # Clear saved methods
        echo "ERROR"
        return 1
    fi
}

# Helper functions to reconstruct commands
get_dns_command() {
    case "$1" in
        "OpenDNS")              echo "dig +short myip.opendns.com @resolver1.opendns.com" ;;
        "Google DNS")           echo "dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'\"' '{print \$2}'" ;;
        "Cloudflare 1.0.0.1")   echo "dig +short txt ch whoami.cloudflare @1.0.0.1 | tr -d '\"'" ;;
        "Cloudflare 1.1.1.1")   echo "dig +short txt ch whoami.cloudflare @1.1.1.1 | tr -d '\"'" ;;
    esac
}

get_http_command() {
    case "$1" in
        "AWS")         echo "curl -4 -s --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com" ;;
        "IPify")       echo "curl -4 -s --connect-timeout 5 --max-time 10 https://api.ipify.org" ;;
        "IPinfo")      echo "curl -4 -s --connect-timeout 5 --max-time 10 https://ipinfo.io/ip" ;;
        "ifconfig.co") echo "curl -4 -s --connect-timeout 5 --max-time 10 https://ifconfig.co" ;;
        "icanhazip")   echo "curl -4 -s --connect-timeout 5 --max-time 10 https://icanhazip.com" ;;
        "IPecho")      echo "curl -4 -s --connect-timeout 5 --max-time 10 https://ipecho.net/plain" ;;
        "ident.me")    echo "curl -4 -s --connect-timeout 5 --max-time 10 https://ident.me" ;;
        "DNS-O-Matic") echo "curl -4 -s --connect-timeout 5 --max-time 10 https://myip.dnsomatic.com" ;;
        "ifconfig.me") echo "curl -4 -s --connect-timeout 5 --max-time 10 https://ifconfig.me/ip" ;;
        *)             echo "curl -4 -s --connect-timeout 5 --max-time 10 https://ipinfo.io/ip" ;;
    esac
}


# =============================================================================
# AdGuard VPN Status Check Function
# =============================================================================
check_adguard_vpn_status() {
    # Check if CLI tool exists
    if ! command -v adguardvpn-cli >/dev/null 2>&1; then
        log "🚨 adguardvpn-cli  not found!" >&2
        return 1
    fi
    
    # Get VPN status
    local status=$(adguardvpn-cli status 2>/dev/null)
    
    # Check if connected
    if [[ $status =~ Connected.*mode ]]; then
        # Determine mode
        # if [[ $status =~ TUN\ mode ]]; then
        #     log "✅ VPN connected (TUN mode)" >&2
        # elif [[ $status =~ SOCKS\ mode ]]; then
        #     log "✅ VPN connected (SOCKS mode)" >&2
        # else
        #     log "✅ VPN connected" >&2
        # fi
        return 0
    else
        log "❌ VPN not connected" >&2
        [ -z "$status" ] && log "⚠️ Empty status response" >&2
        return 1
    fi
} 