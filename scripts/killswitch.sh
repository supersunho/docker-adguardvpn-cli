#!/bin/bash

# =============================================================================
# AdGuard VPN Kill Switch Script - Enhanced with VPN Leak Detection
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
export ADGUARD_ALLOW_VPN_IP_CHANGE=${ADGUARD_ALLOW_VPN_IP_CHANGE:-true}
export ADGUARD_MAX_IP_CHANGES=${ADGUARD_MAX_IP_CHANGES:-10}

# VPN Leak related new configurations
export ADGUARD_MAX_LEAK_TOLERANCE=${ADGUARD_MAX_LEAK_TOLERANCE:-0}  # 0 = immediate termination on first leak
export ADGUARD_LEAK_WARNING_ONLY=${ADGUARD_LEAK_WARNING_ONLY:-false}  # true = warning only, false = terminate

# IP detection retry settings
export ADGUARD_MAX_IP_DETECTION_RETRIES=${ADGUARD_MAX_IP_DETECTION_RETRIES:-3}
export ADGUARD_IP_DETECTION_RETRY_DELAY=${ADGUARD_IP_DETECTION_RETRY_DELAY:-10}

# Display configuration information
log "⚙️ Configuration:"
log "   └── Check Interval: ${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL}s"
log "   └── VPN Server Changes: ${ADGUARD_ALLOW_VPN_IP_CHANGE} (max: ${ADGUARD_MAX_IP_CHANGES})"
log "   └── Leak Tolerance: ${ADGUARD_MAX_LEAK_TOLERANCE} (warning only: ${ADGUARD_LEAK_WARNING_ONLY})"

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

VPN_IP="$CURRENT_IP"
PREVIOUS_IP="$CURRENT_IP"

# Counters
VPN_SERVER_CHANGE_COUNT=0    # Normal changes between VPN servers
LEAK_DETECTION_COUNT=0       # VPN → Real IP leak detection count
TOTAL_HEALTH_CHECKS=0        # Total health check performed

# Status flags
VPN_WAS_ACTIVE=true          # Whether VPN was in active state
LEAK_WARNING_SENT=false      # Whether leak warning was sent
SCRIPT_START_TIME=$(date +%s)

log "🌐 Initial VPN IP: $VPN_IP"
log "🛡️ Kill Switch monitoring started with VPN leak detection"
log "🎯 Focus: Detecting VPN IP → Real IP transitions"

# =============================================================================
# Enhanced Monitoring Loop with VPN Leak Detection
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
    # Core Logic: VPN IP → Real IP Change Detection
    # =========================================================================
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        # Current IP is real IP
        
        if [ "$PREVIOUS_IP" != "$REAL_IP_BEFORE_VPN" ] && [ "$VPN_WAS_ACTIVE" = "true" ]; then
            # Previous IP was VPN IP but now changed to real IP = VPN LEAK!
            LEAK_DETECTION_COUNT=$((LEAK_DETECTION_COUNT + 1))
            
            log "🚨🚨🚨 VPN LEAK DETECTED! 🚨🚨🚨"
            log "🚨 Leak Event #$LEAK_DETECTION_COUNT"
            log "🚨 Transition: VPN IP ($PREVIOUS_IP) → Real IP ($CURRENT_IP)"
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
            # Real IP from the beginning or VPN was inactive
            if [ "$VPN_WAS_ACTIVE" = "false" ]; then
                log "ℹ️ Real IP detected, but VPN was never active - continuing monitoring"
            fi
        fi
        
        # In real IP state, mark VPN as inactive
        VPN_WAS_ACTIVE=false
        
    else
        # Current IP is VPN IP
        VPN_WAS_ACTIVE=true
        LEAK_WARNING_SENT=false  # Reset warning flag when VPN is restored
        
        # Detect VPN server changes (only when not real IP)
        if [ "$CURRENT_IP" != "$PREVIOUS_IP" ] && [ "$PREVIOUS_IP" != "$REAL_IP_BEFORE_VPN" ]; then
            VPN_SERVER_CHANGE_COUNT=$((VPN_SERVER_CHANGE_COUNT + 1))
            
            log "🔄 VPN server change detected (#$VPN_SERVER_CHANGE_COUNT)"
            log "🔄 Server change: $PREVIOUS_IP → $CURRENT_IP"
            
            # Check if VPN server changes are allowed
            if [ "${ADGUARD_ALLOW_VPN_IP_CHANGE,,}" != "true" ]; then
                log "🚨 VPN server changes are disabled by configuration!"
                log "🚨 Set ADGUARD_ALLOW_VPN_IP_CHANGE=true to allow server switching"
                exit 1
            fi
            
            # Check VPN server change limit
            if [ "$ADGUARD_MAX_IP_CHANGES" -gt 0 ] && [ "$VPN_SERVER_CHANGE_COUNT" -gt "$ADGUARD_MAX_IP_CHANGES" ]; then
                log "🚨 Maximum VPN server changes exceeded!"
                log "🚨 Changes: $VPN_SERVER_CHANGE_COUNT (limit: $ADGUARD_MAX_IP_CHANGES)"
                log "🚨 Excessive server switching indicates connection instability"
                exit 1
            fi
            
            # Re-verify VPN service during server change
            if ! check_adguard_vpn_status; then
                log "🚨 VPN service failed during server change!"
                exit 1
            fi
            
            log "✅ VPN server change accepted and validated"
        fi
        
        # Update new VPN IP
        if [ "$CURRENT_IP" != "$VPN_IP" ]; then
            VPN_IP="$CURRENT_IP"
        fi
    fi
    
    # =========================================================================
    # Update Previous IP (for next cycle)
    # =========================================================================
    PREVIOUS_IP="$CURRENT_IP"
    
    # =========================================================================
    # Detailed Status Information Output
    # =========================================================================
    uptime=$(($(date +%s) - SCRIPT_START_TIME))
    status_msg="🛡️ Status Report:"
    
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        status_msg="${status_msg} ⚠️ REAL IP EXPOSED"
        status_msg="${status_msg} | IP: $CURRENT_IP"
        status_msg="${status_msg} | Leaks: $LEAK_DETECTION_COUNT"
        if [ "$LEAK_WARNING_SENT" = "true" ]; then
            status_msg="${status_msg} (⚠️ WARNING)"
        fi
    else
        status_msg="${status_msg} 🔒 VPN PROTECTED"
        status_msg="${status_msg} | VPN IP: $CURRENT_IP"
        status_msg="${status_msg} | Server Changes: $VPN_SERVER_CHANGE_COUNT"
    fi
    
    # Additional status information
    status_msg="${status_msg} | Checks: $TOTAL_HEALTH_CHECKS | Uptime: ${uptime}s"
    
    # Kill Switch status display
    if [ "$VPN_WAS_ACTIVE" = "true" ]; then
        if [ "${ADGUARD_LEAK_WARNING_ONLY,,}" = "true" ]; then
            status_msg="${status_msg} | Kill Switch: 🔕 WARNING MODE"
        else
            status_msg="${status_msg} | Kill Switch: 🔥 ARMED"
        fi
    else
        status_msg="${status_msg} | Kill Switch: ⏳ STANDBY"
    fi
    
    log "$status_msg"
    
    # =========================================================================
    # Regular System Status Summary (every 20 times)
    # =========================================================================
    if [ $((TOTAL_HEALTH_CHECKS % 20)) -eq 0 ]; then
        log "📊 System Summary (every 20 checks):"
        log "   └── Total Health Checks: $TOTAL_HEALTH_CHECKS"
        log "   └── VPN Server Changes: $VPN_SERVER_CHANGE_COUNT"
        log "   └── Leak Detections: $LEAK_DETECTION_COUNT"
        log "   └── Current Protection: $([ "$VPN_WAS_ACTIVE" = "true" ] && echo "🔒 VPN Active" || echo "⚠️ Real IP Exposed")"
        log "   └── Uptime: ${uptime}s"
    fi
    
    # =========================================================================
    # Memory Usage Optimization (every 100 times)
    # =========================================================================
    if [ $((TOTAL_HEALTH_CHECKS % 100)) -eq 0 ]; then
        log "🧹 Performing periodic cleanup..."
        # Perform temporary file cleanup or log compression if needed
    fi
    
done
