#!/bin/bash

# =============================================================================
# AdGuard VPN Kill Switch Script
# =============================================================================
# This script monitors the AdGuard VPN connection and automatically terminates
# the container if the VPN connection is lost or the IP address changes unexpectedly.
# It ensures that no traffic can leak through the original network connection
# if the VPN becomes unavailable.
#
# Requirements:
# - adguardvpn-cli must be installed and available
# - utils.sh must contain get_public_ip() and check_adguard_vpn_status() functions
# - Real IP address before VPN connection must be provided as parameter
#
# Usage:
#   ./killswitch.sh <real_ip_before_vpn>
#   or
#   REAL_IP_BEFORE_VPN=<ip> ./killswitch.sh
# =============================================================================

# Source utility functions for IP detection and VPN status checking
source /opt/adguardvpn_cli/scripts/utils.sh

# =============================================================================
# Input Parameter Validation
# =============================================================================

# Accept real IP either as command line parameter or environment variable
# This IP represents the user's actual IP address before VPN connection
REAL_IP_BEFORE_VPN=${1:-$REAL_IP_BEFORE_VPN}

# Validate that real IP was provided - this is critical for proper operation
if [ -z "$REAL_IP_BEFORE_VPN" ]; then
    echo " > [Kill Switch] ERROR: Real IP before VPN not provided!"
    echo " > [Kill Switch] Usage: $0 <real_ip_before_vpn>"
    echo " > [Kill Switch] This IP should be obtained before connecting to VPN"
    exit 1
fi

echo " > [Kill Switch] Real IP before VPN: $REAL_IP_BEFORE_VPN"

# =============================================================================
# Configuration and Environment Setup
# =============================================================================

# Set monitoring interval (default: 30 seconds)
# This can be overridden by setting ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
export ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL=${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL:-30}

echo " > [Kill Switch] Monitoring interval set to: ${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL} seconds"

# =============================================================================
# Initial VPN Connection Verification
# =============================================================================

echo " > [Kill Switch] Verifying VPN connection status..."

# Check if AdGuard VPN is properly connected using CLI status command
# This function should detect both TUN and SOCKS mode connections
if ! check_adguard_vpn_status; then
    echo " > [Kill Switch] ERROR: AdGuard VPN is not connected!"
    echo " > [Kill Switch] Please ensure VPN is connected before running this script"
    exit 1
fi

echo " > [Kill Switch] ✓ AdGuard VPN connection confirmed"

# =============================================================================
# VPN IP Address Detection and Validation
# =============================================================================

# Get current public IP address (should be VPN IP if connection is working)
echo " > [Kill Switch] Detecting current public IP address..."
CURRENT_IP=$(get_public_ip)

# Handle IP detection failure
if [ "$CURRENT_IP" = "ERROR" ]; then
    echo " > [Kill Switch] CRITICAL: Failed to detect current IP address"
    echo " > [Kill Switch] This could indicate network connectivity issues"
    exit 1
fi

echo " > [Kill Switch] Current IP detected: $CURRENT_IP"

# =============================================================================
# VPN Effectiveness Verification
# =============================================================================

# Verify that VPN is actually working by comparing current IP with real IP
# If they match, VPN is not routing traffic properly
if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
    echo " > [Kill Switch] WARNING: Current IP ($CURRENT_IP) matches real IP!"
    echo " > [Kill Switch] This indicates VPN may not be routing traffic correctly"
    echo " > [Kill Switch] Possible causes:"
    echo " > [Kill Switch] - VPN connection established but routing failed"
    echo " > [Kill Switch] - DNS leakage"
    echo " > [Kill Switch] - Split tunneling enabled"
    echo " > [Kill Switch] TERMINATING for security reasons"
    exit 1
fi

# Store VPN IP for continuous monitoring
VPN_IP="$CURRENT_IP"
echo " > [Kill Switch] ✓ VPN is working correctly"
echo " > [Kill Switch] VPN IP confirmed: $VPN_IP"
echo " > [Kill Switch] Starting continuous monitoring..."

# =============================================================================
# Continuous Monitoring Loop
# =============================================================================

# This loop continuously monitors VPN status and IP address
# Any deviation from expected state will trigger container termination
echo " > [Kill Switch] Monitoring started (Real IP: $REAL_IP_BEFORE_VPN, VPN IP: $VPN_IP)"

while true; do
    # Wait for specified interval before next check
    sleep $ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
    
    echo " > [Kill Switch] Performing routine VPN health check..."
    
    # =========================================================================
    # VPN Service Status Check
    # =========================================================================
    
    # Check if AdGuard VPN service is still running and connected
    if ! check_adguard_vpn_status; then
        echo " > [Kill Switch] ALERT: AdGuard VPN service disconnected!"
        echo " > [Kill Switch] VPN service is no longer running or connected"
        echo " > [Kill Switch] TERMINATING container to prevent traffic leakage"
        exit 1
    fi
    
    # =========================================================================
    # IP Address Monitoring
    # =========================================================================
    
    # Get current public IP for comparison
    CURRENT_IP=$(get_public_ip)
    
    # Handle temporary IP detection failures (retry logic)
    if [ "$CURRENT_IP" = "ERROR" ]; then
        echo " > [Kill Switch] WARNING: Failed to get current IP address"
        echo " > [Kill Switch] This might be a temporary network issue"
        echo " > [Kill Switch] Retrying in 10 seconds..."
        sleep 10
        continue
    fi
    
    # Log current monitoring status
    echo " > [Kill Switch] Status check: VPN IP: $VPN_IP => Current IP: $CURRENT_IP"
    
    # =========================================================================
    # VPN IP Change Detection
    # =========================================================================
    
    # Detect if VPN IP has changed (could indicate VPN server switch or connection reset)
    if [ "$CURRENT_IP" != "$VPN_IP" ]; then
        echo " > [Kill Switch] ALERT: VPN IP address has changed!"
        echo " > [Kill Switch] Expected: $VPN_IP"
        echo " > [Kill Switch] Current:  $CURRENT_IP"
        echo " > [Kill Switch] Possible causes:"
        echo " > [Kill Switch] - VPN server reconnection"
        echo " > [Kill Switch] - VPN service restart" 
        echo " > [Kill Switch] - Network configuration change"
        echo " > [Kill Switch] TERMINATING container for security"
        exit 1
    fi
    
    # =========================================================================
    # Traffic Leak Detection
    # =========================================================================
    
    # Check if traffic has reverted to real IP (VPN bypass/failure)
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        echo " > [Kill Switch] CRITICAL: IP reverted to real IP address!"
        echo " > [Kill Switch] Current IP: $CURRENT_IP"
        echo " > [Kill Switch] Real IP:   $REAL_IP_BEFORE_VPN"
        echo " > [Kill Switch] This indicates VPN connection has failed"
        echo " > [Kill Switch] Traffic is now flowing through original connection"
        echo " > [Kill Switch] TERMINATING container immediately"
        exit 1
    fi
    
    # =========================================================================
    # Health Check Confirmation
    # =========================================================================
    
    # Log successful monitoring cycle
    echo " > [Kill Switch] ✓ All checks passed - VPN connection stable"
    echo " > [Kill Switch] Next check in ${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL} seconds"
done

# =============================================================================
# Script End
# =============================================================================
# This point should never be reached during normal operation
# The script is designed to run continuously until VPN failure is detected
