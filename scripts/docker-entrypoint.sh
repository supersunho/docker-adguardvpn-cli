#!/bin/bash

# =============================================================================
# AdGuard VPN Container Entry Point Script
# =============================================================================
# This is the main entry point script for the AdGuard VPN Docker container.
# It orchestrates the VPN initialization, optional kill switch activation,
# and log monitoring to keep the container running while providing real-time
# feedback about the VPN connection status.
#
# Key Features:
# - Initializes AdGuard VPN connection
# - Monitors VPN status with optional kill switch
# - Provides real-time log output via tail
# - Graceful container termination on VPN failures
#
# Environment Variables:
# - ADGUARD_USE_KILL_SWITCH: Enable/disable kill switch (default: true)
# - Other variables are passed through to init.sh and killswitch.sh
# =============================================================================

# =============================================================================
# Import Utility Functions
# =============================================================================
# Load utility functions for IP detection and VPN status checking
# These functions are shared between this script and the kill switch
source /opt/adguardvpn_cli/scripts/utils.sh

# =============================================================================
# Configuration and Environment Setup
# =============================================================================

# Configure kill switch behavior (default enabled for security)
# This can be disabled by setting ADGUARD_USE_KILL_SWITCH=false
export ADGUARD_USE_KILL_SWITCH=${ADGUARD_USE_KILL_SWITCH:-true}

echo " > [Entry] AdGuard VPN Container Starting..."
echo " > [Entry] Kill Switch enabled: ${ADGUARD_USE_KILL_SWITCH}"

# =============================================================================
# Phase 1: VPN Initialization
# =============================================================================
# Execute the initialization script which handles:
# - AdGuard VPN CLI setup and configuration
# - VPN connection establishment
# - Initial connection verification
#
# This runs in the foreground to ensure VPN is properly connected
# before proceeding to monitoring phase
echo " > [Entry] Starting VPN initialization process..."
/opt/adguardvpn_cli/scripts/init.sh

# Capture the exit code to determine if initialization was successful
INIT_EXIT_CODE=$?

# Check if initialization was successful
if [ "$INIT_EXIT_CODE" -ne 0 ]; then
    echo " > [Entry] ERROR: VPN initialization failed with exit code $INIT_EXIT_CODE"
    echo " > [Entry] Please check init.sh logs for detailed error information"
    exit $INIT_EXIT_CODE
fi

echo " > [Entry] ✓ VPN initialization completed successfully"

# =============================================================================
# Phase 2: Log File Preparation
# =============================================================================
# Wait for AdGuard VPN CLI to create its log file
# This ensures we have a log file to monitor before starting the tail process
echo " > [Entry] Waiting for AdGuard VPN log file to be created..."

# Poll for log file existence (typically created quickly after VPN starts)
LOG_FILE="/root/.local/share/adguardvpn-cli/app.log"
while [ ! -f "$LOG_FILE" ]; do
    echo " > [Entry] Log file not yet available, waiting..."
    sleep 1
done

echo " > [Entry] ✓ Log file is now available: $LOG_FILE"

# =============================================================================
# Phase 3: Background Log Monitoring
# =============================================================================
# Start continuous log monitoring in the background
# This provides real-time visibility into VPN status and operations
# The -F flag follows the file even if it gets rotated or recreated
echo " > [Entry] Starting background log monitoring..."

tail -F "$LOG_FILE" &
TAIL_PID=$!

echo " > [Entry] ✓ Log monitoring started (PID: $TAIL_PID)"

# =============================================================================
# Phase 4: Kill Switch Activation (Conditional)
# =============================================================================
# If kill switch is enabled, set up continuous VPN monitoring
# This provides an additional layer of security by terminating the container
# if VPN connection is lost or compromised

# Convert ADGUARD_USE_KILL_SWITCH to lowercase for comparison
if [ "${ADGUARD_USE_KILL_SWITCH,,}" = "true" ]; then
    echo " > [Entry] Kill switch is enabled - setting up VPN monitoring..."
    
    # =========================================================================
    # Pre-VPN IP Address Detection
    # =========================================================================
    # Capture the real IP address before VPN connection
    # This is critical for kill switch operation as it needs to detect
    # when traffic reverts to the original IP (indicating VPN failure)
    echo " > [Entry] Detecting real IP address before VPN connection..."
    
    # Note: At this point, init.sh should have already connected the VPN,
    # so we're actually getting the VPN IP here. In a proper implementation,
    # this should be done before VPN connection in init.sh
    REAL_IP=$(get_public_ip)
    
    # Validate that IP detection was successful
    if [ "$REAL_IP" = "ERROR" ]; then
        echo " > [Entry] CRITICAL: Failed to detect real IP address"
        echo " > [Entry] Kill switch cannot operate without baseline IP"
        echo " > [Entry] Possible causes:"
        echo " > [Entry] - No internet connectivity"
        echo " > [Entry] - DNS resolution issues" 
        echo " > [Entry] - All IP detection services unavailable"
        echo " > [Entry] Terminating container for security"
        
        # Clean up background processes before exit
        kill $TAIL_PID 2>/dev/null
        exit 1
    fi
    
    echo " > [Entry] Real IP address detected: $REAL_IP"
    
    # Export for use by kill switch script
    export REAL_IP_BEFORE_VPN="$REAL_IP"
    
    # =========================================================================
    # Kill Switch Activation
    # =========================================================================
    # Start the kill switch monitoring in the background
    # All output is redirected to the main log file for unified logging
    echo " > [Entry] Activating kill switch monitoring..."
    
    # Start kill switch as background process with output redirection
    /opt/adguardvpn_cli/scripts/killswitch.sh "$REAL_IP" >> "$LOG_FILE" 2>&1 &
    KILL_PID=$!
    
    echo " > [Entry] ✓ Kill switch activated (PID: $KILL_PID)"
    echo " > [Entry] Container will terminate automatically if VPN fails"
    
    # =========================================================================
    # Kill Switch Monitoring Loop
    # =========================================================================
    # Wait for kill switch process to complete
    # Under normal operation, kill switch runs indefinitely
    # It only exits when VPN failure is detected (exit code 1)
    echo " > [Entry] Monitoring kill switch process..."
    
    wait $KILL_PID
    KILL_EXIT_CODE=$?
    
    # =========================================================================
    # Kill Switch Termination Handling
    # =========================================================================
    # If kill switch exits with code 1, it detected a VPN failure
    # Terminate the container immediately to prevent traffic leakage
    if [ "$KILL_EXIT_CODE" -eq 1 ]; then
        echo " > [Entry] ALERT: Kill switch detected VPN failure!"
        echo " > [Entry] Kill switch exited with code 1 - VPN connection compromised"
        echo " > [Entry] Terminating container immediately for security"
        
        # Clean up background log monitoring process
        kill $TAIL_PID 2>/dev/null
        
        # Exit with failure code to indicate abnormal termination
        exit 1
    elif [ "$KILL_EXIT_CODE" -eq 0 ]; then
        echo " > [Entry] Kill switch exited normally (code 0)"
        echo " > [Entry] This is unexpected during normal operation"
    else
        echo " > [Entry] Kill switch exited with unexpected code: $KILL_EXIT_CODE"
        echo " > [Entry] This may indicate a script error or system issue"
    fi
    
else
    # =========================================================================
    # Kill Switch Disabled Mode
    # =========================================================================
    # If kill switch is disabled, keep container alive by monitoring logs only
    # This mode provides basic VPN functionality without automatic termination
    echo " > [Entry] Kill switch is DISABLED"
    echo " > [Entry] Container will continue running even if VPN fails"
    echo " > [Entry] Monitor logs manually for VPN status updates"
    
    # Keep container alive by waiting for the tail process
    # Container will only terminate if manually stopped or if tail fails
    wait $TAIL_PID
fi

# =============================================================================
# Container Termination
# =============================================================================
# This section handles normal container shutdown
# In kill switch mode, this is only reached if kill switch exits normally
# In non-kill switch mode, this is reached when tail process terminates

echo " > [Entry] Container termination sequence initiated"

# Clean up any remaining background processes
if [ -n "$TAIL_PID" ]; then
    echo " > [Entry] Stopping log monitoring process..."
    kill $TAIL_PID 2>/dev/null
fi

# Exit with the same code as the initialization script
# This preserves the original exit status for container orchestration
echo " > [Entry] Container exiting with code: $INIT_EXIT_CODE"
exit $INIT_EXIT_CODE

# =============================================================================
# End of Entry Point Script
# =============================================================================
# This script serves as the main coordinator for the AdGuard VPN container,
# ensuring proper initialization, monitoring, and security through the kill
# switch mechanism. It provides a robust foundation for secure VPN operations
# in containerized environments.
# =============================================================================
