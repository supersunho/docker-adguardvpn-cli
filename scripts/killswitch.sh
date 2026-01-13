#!/bin/bash

# =============================================================================
# AdGuard VPN Kill Switch Script
# =============================================================================

# Source utility functions for IP detection and VPN status checking
source /opt/adguardvpn_cli/scripts/utils.sh

# =============================================================================
# Input Parameter Validation
# =============================================================================

REAL_IP_BEFORE_VPN=${1:-$REAL_IP_BEFORE_VPN}

if [ -z "$REAL_IP_BEFORE_VPN" ]; then
    log "🚨 Kill Switch ERROR: Real IP not provided!"
    log " > Usage: $0 <real_ip_before_vpn>"
    exit 1
fi

log "🏠 Original IP: $REAL_IP_BEFORE_VPN"

# =============================================================================
# Configuration Setup
# =============================================================================

export ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL=${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL:-30}

# VPN Leak detection configurations
export ADGUARD_MAX_LEAK_TOLERANCE=${ADGUARD_MAX_LEAK_TOLERANCE:-0}  # 0 = immediate termination on first leak
export ADGUARD_LEAK_WARNING_ONLY=${ADGUARD_LEAK_WARNING_ONLY:-false}  # true = warning only, false = terminate

# IP detection retry settings
export ADGUARD_MAX_IP_DETECTION_RETRIES=${ADGUARD_MAX_IP_DETECTION_RETRIES:-3}
export ADGUARD_IP_DETECTION_RETRY_DELAY=${ADGUARD_IP_DETECTION_RETRY_DELAY:-10}

# Display configuration information
log "⚙️ Configuration:"
log "   └── Check Interval: ${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL}s"
log "   └── Leak Tolerance: ${ADGUARD_MAX_LEAK_TOLERANCE} (warning only: ${ADGUARD_LEAK_WARNING_ONLY})"
log "   └── Focus: Original IP → VPN IP → Original IP detection"

# =============================================================================
# Initial VPN Verification
# =============================================================================

log "🔍 Checking initial VPN connection..."

if ! check_adguard_vpn_status; then
    log "🚨 VPN not connected at startup!"
    exit 1
fi

log "✅ VPN service is running"

# =============================================================================
# Wait for VPN tunnel to be active
# =============================================================================

log "⏳ Waiting for VPN tunnel to become active..."

# Wait for VPN to be connected and tunnel to be active
elapsed_time=0
CHECK_INTERVAL=2
MAX_WAIT_TIME=30

while [ $elapsed_time -lt $MAX_WAIT_TIME ]; do
    if check_adguard_vpn_status; then
        # Additional check: try to get IP to ensure tunnel is active
        temp_ip=$(get_public_ip)
        if [ "$temp_ip" != "ERROR" ] && [ "$temp_ip" != "$REAL_IP_BEFORE_VPN" ]; then
            log "✅ VPN tunnel is active and IP has changed: $temp_ip"
            break
        else
            log "⏳ VPN connected but tunnel may not be ready, checking again in $CHECK_INTERVAL seconds..."
        fi
    else
        log "⏳ VPN not connected yet, checking again in $CHECK_INTERVAL seconds..."
    fi
    
    sleep $CHECK_INTERVAL
    elapsed_time=$((elapsed_time + CHECK_INTERVAL))
done

if [ $elapsed_time -ge $MAX_WAIT_TIME ]; then
    log "🚨 Timed out waiting for VPN tunnel to become active!"
    log "🚨 Please ensure VPN is properly connected before running Kill Switch"
    exit 1
fi

# =============================================================================
# Initial IP Detection and Validation
# =============================================================================

log "📡 Getting current IP with enhanced validation..."
CURRENT_IP=$(get_public_ip)

if [ "$CURRENT_IP" = "ERROR" ]; then
    log "🚨 Failed to get initial IP address"
    exit 1
fi

if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
    log "🚨 VPN not working! Current IP matches original IP"
    log "🚨 Please ensure VPN is properly connected before running Kill Switch"
    exit 1
fi

# =============================================================================
# Initialize Tracking Variables
# =============================================================================

CURRENT_VPN_IP="$CURRENT_IP"

# Essential counters only
LEAK_DETECTION_COUNT=0       # VPN → Real IP leak detection count
TOTAL_HEALTH_CHECKS=0        # Total health check performed

# Status flags
VPN_WAS_ACTIVE=true          # Whether VPN was in active state
LEAK_WARNING_SENT=false      # Whether leak warning was sent
SCRIPT_START_TIME=$(date +%s)

log "🌐 Initial VPN IP: $CURRENT_VPN_IP"
log "🛡️ Kill Switch monitoring started - VPN leak detection"
log "🎯 Monitoring: Original IP ($REAL_IP_BEFORE_VPN) exposure after VPN activation"

# =============================================================================
# Simplified Monitoring Loop - Focus on VPN Leak Detection Only
# =============================================================================

while true; do
    sleep $ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
    TOTAL_HEALTH_CHECKS=$((TOTAL_HEALTH_CHECKS + 1))
    
    log "💓 Health check #$TOTAL_HEALTH_CHECKS..."
    
    # =========================================================================
    # VPN Service Status Check
    # =========================================================================
    if ! check_adguard_vpn_status; then
        log "🚨 VPN service disconnected! Kill Switch terminating..."
        log "🚨 Service failure detected after $TOTAL_HEALTH_CHECKS checks"
        exit 1
    fi
    
    # =========================================================================
    # Enhanced IP Detection with Robust Retry Logic
    # =========================================================================
    RETRY_COUNT=0
    CURRENT_IP=""
    
    while [ "$RETRY_COUNT" -lt "$ADGUARD_MAX_IP_DETECTION_RETRIES" ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "🔍 IP detection attempt $RETRY_COUNT/$ADGUARD_MAX_IP_DETECTION_RETRIES..."
        
        CURRENT_IP=$(get_public_ip)
        
        if [ "$CURRENT_IP" != "ERROR" ]; then
            log "✅ IP detected: $CURRENT_IP"
            break
        fi
        
        if [ "$RETRY_COUNT" -lt "$ADGUARD_MAX_IP_DETECTION_RETRIES" ]; then
            log "⚠️ IP detection failed, retrying in ${ADGUARD_IP_DETECTION_RETRY_DELAY}s..."
            sleep $ADGUARD_IP_DETECTION_RETRY_DELAY
        fi
    done
    
    if [ "$CURRENT_IP" = "ERROR" ]; then
        log "🚨 All IP detection methods failed after $ADGUARD_MAX_IP_DETECTION_RETRIES attempts!"
        log "🚨 Network connectivity issues detected - terminating for safety"
        exit 1
    fi
    
    # =========================================================================
    # Simplified Core Logic: Only VPN Leak Detection
    # =========================================================================
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        # Current IP matches original IP - potential leak
        
        if [ "$VPN_WAS_ACTIVE" = "true" ]; then
            # VPN was active but now showing original IP = LEAK!
            LEAK_DETECTION_COUNT=$((LEAK_DETECTION_COUNT + 1))
            
            log "🚨🚨🚨 VPN LEAK DETECTED! 🚨🚨🚨"
            log "🚨 Leak Event #$LEAK_DETECTION_COUNT"
            log "🚨 VPN was active but traffic reverted to Original IP: $CURRENT_IP"
            log "🚨 Your traffic is now EXPOSED through your real IP!"
            
            # Check leak tolerance limit
            if [ "$ADGUARD_MAX_LEAK_TOLERANCE" -ge 0 ] && [ "$LEAK_DETECTION_COUNT" -gt "$ADGUARD_MAX_LEAK_TOLERANCE" ]; then
                log "🛑 LEAK TOLERANCE EXCEEDED!"
                log "🛑 Detected $LEAK_DETECTION_COUNT leaks (limit: $ADGUARD_MAX_LEAK_TOLERANCE)"
                log "🛑 KILL SWITCH ACTIVATED - IMMEDIATE TERMINATION"
                exit 1
            fi
            
            # Check warning-only mode
            if [ "${ADGUARD_LEAK_WARNING_ONLY,,}" = "true" ]; then
                log "⚠️ WARNING MODE: Leak detected but continuing monitoring"
                log "⚠️ Set ADGUARD_LEAK_WARNING_ONLY=false for immediate termination"
                LEAK_WARNING_SENT=true
            else
                if [ "$ADGUARD_MAX_LEAK_TOLERANCE" -eq 0 ]; then
                    log "🛑 ZERO TOLERANCE MODE: IMMEDIATE TERMINATION"
                    exit 1
                else
                    log "🚨 Leak detected but within tolerance ($LEAK_DETECTION_COUNT/$ADGUARD_MAX_LEAK_TOLERANCE)"
                fi
            fi
        else
            # Original IP detected but VPN was never active
            log "ℹ️ Original IP detected, but VPN was never active - continuing monitoring"
        fi
        
        # Mark VPN as inactive when showing original IP
        VPN_WAS_ACTIVE=false
        
    else
        # Current IP is different from original - VPN is working
        VPN_WAS_ACTIVE=true
        LEAK_WARNING_SENT=false  # Reset warning flag when VPN is active
        
        # Update current VPN IP (for display purposes only)
        if [ "$CURRENT_IP" != "$CURRENT_VPN_IP" ]; then
            log "🔄 VPN IP changed: $CURRENT_VPN_IP → $CURRENT_IP"
            CURRENT_VPN_IP="$CURRENT_IP"
        fi
    fi
    
    # =========================================================================
    # Simplified Status Information Output
    # =========================================================================
    uptime=$(($(date +%s) - SCRIPT_START_TIME))
    status_msg="🛡️ Status:"
    
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        status_msg="${status_msg} ⚠️ ORIGINAL IP EXPOSED"
        status_msg="${status_msg} | IP: $CURRENT_IP"
        status_msg="${status_msg} | Leaks: $LEAK_DETECTION_COUNT"
        if [ "$LEAK_WARNING_SENT" = "true" ]; then
            status_msg="${status_msg} (⚠️ WARNING)"
        fi
    else
        status_msg="${status_msg} 🔒 VPN PROTECTED"
        status_msg="${status_msg} | VPN IP: $CURRENT_IP"
    fi
    
    # Essential status information
    status_msg="${status_msg} | Checks: $TOTAL_HEALTH_CHECKS | Uptime: ${uptime}s"
    
    # Kill Switch status display
    if [ "$VPN_WAS_ACTIVE" = "true" ]; then
        if [ "${ADGUARD_LEAK_WARNING_ONLY,,}" = "true" ]; then
            status_msg="${status_msg} | Kill Switch: 🔕 WARNING MODE"
        else
            status_msg="${status_msg} | Kill Switch: 🔥 RUNNING"
        fi
    else
        status_msg="${status_msg} | Kill Switch: ⏳ STANDBY"
    fi
    
    log "$status_msg"
    
    # =========================================================================
    # Simplified System Status Summary (every 20 times)
    # =========================================================================
    if [ $((TOTAL_HEALTH_CHECKS % 20)) -eq 0 ]; then
        log "📊 System Summary (every 20 checks):"
        log "   └── Total Health Checks: $TOTAL_HEALTH_CHECKS"
        log "   └── Leak Detections: $LEAK_DETECTION_COUNT"
        log "   └── Current Protection: $([ "$VPN_WAS_ACTIVE" = "true" ] && echo "🔒 VPN Active" || echo "⚠️ Original IP Exposed")"
        log "   └── Monitoring Pattern: Original IP ($REAL_IP_BEFORE_VPN) → VPN → Original IP"
        log "   └── Uptime: ${uptime}s"
    fi
    
    # =========================================================================
    # Memory Usage Optimization (every 100 times)
    # =========================================================================
    if [ $((TOTAL_HEALTH_CHECKS % 100)) -eq 0 ]; then
        log "🧹 Performing periodic cleanup..."
        
        # Clean up temporary variables to free memory
        unset TEMP_VAR
        
        # Sync filesystems to ensure data integrity
        sync
        
        # Log memory usage
        if command -v free >/dev/null 2>&1; then
            log "📊 Memory usage:"
            free -h | grep -E '^(Mem:|Swap:)' | while read -r line; do
                log "   └── $line"
            done
        fi
    fi
    
done