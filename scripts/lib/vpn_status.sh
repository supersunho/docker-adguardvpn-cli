#!/bin/bash
#
# AdGuard VPN -- VPN status check
#
# Provides a function to check whether the AdGuard VPN CLI reports
# an active VPN connection.

# =============================================================================
# Public: check_adguard_vpn_status
# =============================================================================

# Check whether the VPN is currently connected.
# Usage: if check_adguard_vpn_status; then echo "VPN is up"; fi
# Returns: 0 if connected, 1 otherwise
check_adguard_vpn_status() {
    if ! command -v adguardvpn-cli >/dev/null 2>&1; then
        log ERROR "adguardvpn-cli not found"
        return 1
    fi

    local status
    status=$(adguardvpn-cli status 2>/dev/null) || true

    if [[ $status =~ Connected.*mode ]]; then
        log DEBUG "VPN is connected"
        return 0
    fi

    log DEBUG "VPN is not connected"
    return 1
}
