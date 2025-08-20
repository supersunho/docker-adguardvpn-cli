#!/bin/bash

# =============================================================================
# Public IP Detection and VPN Status Utilities
# =============================================================================
# This file contains utility functions for detecting public IP addresses and
# checking AdGuard VPN connection status. These functions are designed to be
# reliable, fault-tolerant, and provide multiple fallback options.
#
# Functions included:
# - get_public_ip(): Detects current public IP using multiple methods
# - check_adguard_vpn_status(): Verifies AdGuard VPN connection status
# =============================================================================

# =============================================================================
# Public IP Address Detection Function
# =============================================================================
# This function attempts to detect the current public IP address using multiple
# methods in order of reliability. It tries DNS-based methods first (faster and
# more reliable), then falls back to HTTP-based services if DNS is unavailable.
# 
# The function randomizes the order of service attempts to distribute load
# across different providers and avoid overwhelming any single service.
#
# Return values:
# - On success: Returns the detected IP address (e.g., "192.168.1.1")
# - On failure: Returns "ERROR" string
# =============================================================================
get_public_ip() {
    local ip=""
    
    # =========================================================================
    # DNS-Based IP Detection Methods (Most Reliable)
    # =========================================================================
    # DNS queries are generally faster and more reliable than HTTP requests
    # These services use DNS TXT records to return IP information
    local dns_methods=(
        # OpenDNS resolver - highly reliable, fast response
        "dig +short myip.opendns.com @resolver1.opendns.com"
        
        # Google DNS service - returns IP in quoted TXT record format
        "dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'\"' '{print \$2}'"
        
        # Cloudflare DNS service using 1.0.0.1 resolver
        "dig +short txt ch whoami.cloudflare @1.0.0.1 | tr -d '\"'"
        
        # Cloudflare DNS service using 1.1.1.1 resolver (backup)
        "dig +short txt ch whoami.cloudflare @1.1.1.1 | tr -d '\"'"
    )
    
    # =========================================================================
    # HTTP-Based IP Detection Services (Fallback Options)
    # =========================================================================
    # HTTP services that return the client's public IP address
    # These are used as fallback when DNS methods are unavailable
    local http_services=(
        # AWS-hosted service - very reliable due to AWS infrastructure
        "https://checkip.amazonaws.com"
        
        # Dedicated IP detection service - simple and fast
        "https://api.ipify.org"
        
        # Popular IP information service
        "https://ipinfo.io/ip"
        
        # Clean, minimal service with fast responses
        "https://ifconfig.co"
        
        # Long-running reliable service
        "https://icanhazip.com"
        
        # Simple plain text IP service
        "https://ipecho.net/plain"
        
        # Minimalist IP detection service
        "https://ident.me"
        
        # Dynamic DNS service IP detection
        "https://myip.dnsomatic.com"
        
        # Classic IP detection service (may be slower)
        "https://ifconfig.me/ip"
    )
    
    # =========================================================================
    # Array Randomization Function
    # =========================================================================
    # Randomizes the order of elements in an array to distribute load across
    # different services and avoid always hitting the same service first.
    # This helps with load balancing and improves reliability.
    #
    # Uses Fisher-Yates shuffle algorithm for uniform distribution
    shuffle_array() {
        local -n arr=$1  # Name reference to the array
        local i tmp size rand
        
        size=${#arr[*]}
        # Iterate backwards through array, swapping each element with random element
        for (( i=size-1; i>0; i-- )); do
            rand=$((RANDOM % (i+1)))  # Random index from 0 to i
            # Swap elements at positions i and rand
            tmp=${arr[i]}
            arr[i]=${arr[rand]}
            arr[rand]=$tmp
        done
    }
    
    # =========================================================================
    # DNS Method Attempts
    # =========================================================================
    # Try DNS-based methods first as they are generally more reliable and faster
    if command -v dig >/dev/null 2>&1; then
        echo " > [Utils] Using DNS-based IP detection methods" >&2
        
        # Randomize DNS methods to distribute load
        shuffle_array dns_methods
        
        # Attempt each DNS method until one succeeds
        for method in "${dns_methods[@]}"; do
            echo " > [Utils] Trying DNS method: ${method%% *}" >&2
            
            # Execute the DNS query and clean up the result
            ip=$(eval "$method" 2>/dev/null | head -n1 | tr -d '\n\r ')
            
            # Validate that result is a proper IPv4 address format
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo " > [Utils] ✓ DNS method succeeded: $ip" >&2
                echo "$ip"
                return 0  # Success - return immediately
            fi
            
            echo " > [Utils] ✗ DNS method failed or returned invalid format" >&2
        done
        
        echo " > [Utils] All DNS methods failed, falling back to HTTP services" >&2
    else
        echo " > [Utils] dig command not available, using HTTP services only" >&2
    fi
    
    # =========================================================================
    # HTTP Service Attempts (Fallback)
    # =========================================================================
    # If DNS methods failed or are unavailable, try HTTP services
    echo " > [Utils] Attempting HTTP-based IP detection" >&2
    
    # Randomize HTTP services to distribute load and avoid service limits
    shuffle_array http_services
    
    # Attempt each HTTP service until one succeeds
    for service in "${http_services[@]}"; do
        echo " > [Utils] Trying HTTP service: $service" >&2
        
        # Make HTTP request with reasonable timeouts to avoid hanging
        # --connect-timeout: Max time to establish connection (5 seconds)
        # --max-time: Max total time for entire operation (10 seconds)
        ip=$(curl -4 -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | head -n1 | tr -d '\n\r ')
        
        # Validate that result is a proper IPv4 address format
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo " > [Utils] ✓ HTTP service succeeded: $ip" >&2
            echo "$ip"
            return 0  # Success - return immediately
        fi
        
        echo " > [Utils] ✗ HTTP service failed or returned invalid format" >&2
    done
    
    # =========================================================================
    # Complete Failure Handling
    # =========================================================================
    # If we reach this point, all methods have failed
    echo " > [Utils] ✗ CRITICAL: All IP detection methods failed" >&2
    echo " > [Utils] Possible causes:" >&2
    echo " > [Utils] - No internet connectivity" >&2
    echo " > [Utils] - DNS resolution issues" >&2
    echo " > [Utils] - Firewall blocking requests" >&2
    echo " > [Utils] - All services temporarily unavailable" >&2
    
    echo "ERROR"
    return 1
}

# =============================================================================
# AdGuard VPN Status Verification Function
# =============================================================================
# This function checks whether AdGuard VPN is currently connected and active.
# It uses the adguardvpn-cli command to query the current connection status
# and determines if the VPN is properly routing traffic.
#
# The function supports both TUN and SOCKS modes of operation and provides
# detailed debugging information to help troubleshoot connection issues.
#
# Return values:
# - 0: VPN is connected and active
# - 1: VPN is not connected or CLI tool is unavailable
# =============================================================================
check_adguard_vpn_status() {
    # =========================================================================
    # CLI Tool Availability Check
    # =========================================================================
    # Verify that the AdGuard VPN command-line tool is installed and accessible
    if ! command -v adguardvpn-cli >/dev/null 2>&1; then
        echo " > [Utils] ERROR: adguardvpn-cli command not found" >&2
        echo " > [Utils] Please ensure AdGuard VPN CLI is properly installed" >&2
        echo " > [Utils] and available in the system PATH" >&2
        return 1
    fi
    
    # =========================================================================
    # VPN Status Query
    # =========================================================================
    # Execute the status command and capture its output
    # Redirect stderr to /dev/null to suppress any error messages from the CLI
    local status=$(adguardvpn-cli status 2>/dev/null)
    
    # Output raw status for debugging purposes
    # This helps troubleshoot issues when VPN status is not as expected
    # echo " > [Utils] AdGuard VPN raw status output: '$status'" >&2
    
    # =========================================================================
    # Connection Status Analysis
    # =========================================================================
    # Parse the status output to determine if VPN is connected
    # Expected formats:
    # - TUN mode: "Connected to TOKYO in TUN mode, running on tun0"
    # - SOCKS mode: "Connected to TOKYO in SOCKS mode, listening on 127.0.0.1:1080"
    # - Disconnected: "Disconnected" or other non-connected states
    
    # Use flexible pattern matching to catch both TUN and SOCKS modes
    if [[ $status =~ Connected.*mode ]]; then
        echo " > [Utils] ✓ AdGuard VPN status: CONNECTED" >&2
        
        # Additional parsing to identify connection mode (for informational purposes)
        if [[ $status =~ TUN\ mode ]]; then
            echo " > [Utils] Connection mode: TUN (tunnel mode)" >&2
        elif [[ $status =~ SOCKS\ mode ]]; then
            echo " > [Utils] Connection mode: SOCKS (proxy mode)" >&2
        fi
        
        return 0  # VPN is connected
    else
        echo " > [Utils] ✗ AdGuard VPN status: NOT CONNECTED" >&2
        echo " > [Utils] Current status indicates VPN is not active" >&2
        
        # Provide helpful information about possible states
        if [[ -z "$status" ]]; then
            echo " > [Utils] Status command returned empty result" >&2
            echo " > [Utils] This may indicate CLI communication issues" >&2
        else
            echo " > [Utils] Status suggests VPN is disconnected or in error state" >&2
        fi
        
        return 1  # VPN is not connected
    fi
}

# =============================================================================
# End of Utility Functions
# =============================================================================
# These functions provide robust IP detection and VPN status checking
# capabilities for the kill switch system. They are designed to handle
# various failure scenarios gracefully and provide detailed logging
# to assist with troubleshooting.
#
# Usage in other scripts:
# - Source this file: source /path/to/utils.sh
# - Call functions: get_public_ip, check_adguard_vpn_status
# =============================================================================
