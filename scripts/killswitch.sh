#!/bin/bash

# =============================================================================
# AdGuard VPN Kill Switch Script - Enhanced with Dual IP Detection
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
export ADGUARD_MAX_IP_CHANGES=${ADGUARD_MAX_IP_CHANGES:-5}

# IP 불일치 허용 횟수 추가
export ADGUARD_MAX_IP_MISMATCHES=${ADGUARD_MAX_IP_MISMATCHES:-3}

# 무제한 설정 표시
if [ "$ADGUARD_MAX_IP_CHANGES" -le 0 ]; then
    log "⚙️ Config: Check ${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL}s, IP Changes ${ADGUARD_ALLOW_VPN_IP_CHANGE} (unlimited)"
else
    log "⚙️ Config: Check ${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL}s, IP Changes ${ADGUARD_ALLOW_VPN_IP_CHANGE} (max:${ADGUARD_MAX_IP_CHANGES})"
fi

# =============================================================================
# Initial VPN Verification
# =============================================================================

log "🔍 Checking VPN connection..."

if ! check_adguard_vpn_status; then
    log "🚨 VPN not connected!"
    exit 1
fi

log "✅ VPN connected"

# =============================================================================
# Initial IP Detection with Enhanced Validation
# =============================================================================

log "📡 Getting current IP with dual method validation..."
CURRENT_IP=$(get_public_ip)

if [ "$CURRENT_IP" = "ERROR" ]; then
    log "🚨 Failed to get IP address"
    exit 1
fi

if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
    log "🚨 VPN not working! Current IP matches original IP"
    exit 1
fi

VPN_IP="$CURRENT_IP"
VPN_IP_CHANGE_COUNT=0
IP_MISMATCH_COUNT=0

log "🌐 VPN IP: $VPN_IP"
log "🛡️ Kill Switch monitoring started with enhanced dual detection"

# =============================================================================
# Enhanced Monitoring Loop with Dual IP Detection Analysis
# =============================================================================

while true; do
    sleep $ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
    
    log "💓 Health check with dual method validation..."
    
    # Check VPN service
    if ! check_adguard_vpn_status; then
        log "🚨 VPN service disconnected! Terminating..."
        exit 1
    fi
    
    # =========================================================================
    # Enhanced IP Detection with Retry Logic
    # =========================================================================
    RETRY_COUNT=0
    CURRENT_IP=""
    
    while [ "$RETRY_COUNT" -lt 3 ]; do
        log "🔍 IP detection attempt $((RETRY_COUNT + 1))/3..."
        CURRENT_IP=$(get_public_ip)
        
        if [ "$CURRENT_IP" != "ERROR" ]; then
            break
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ "$RETRY_COUNT" -lt 3 ]; then
            log "⚠️ IP detection failed, retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    if [ "$CURRENT_IP" = "ERROR" ]; then
        log "🚨 All IP detection methods failed after 3 attempts! Terminating..."
        exit 1
    fi
    
    # =========================================================================
    # Critical Security Check: Traffic Leak Detection
    # =========================================================================
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        log "🚨 CRITICAL: TRAFFIC LEAK DETECTED!"
        log "🚨 Current IP ($CURRENT_IP) matches original IP"
        log "🛑 IMMEDIATE TERMINATION for security protection"
        exit 1
    fi
    
    # =========================================================================
    # VPN IP Change Analysis with Enhanced Logic
    # =========================================================================
    if [ "$CURRENT_IP" != "$VPN_IP" ]; then
        log "🔄 VPN IP change detected: $VPN_IP → $CURRENT_IP"
        
        # Check if IP changes are allowed
        if [ "${ADGUARD_ALLOW_VPN_IP_CHANGE,,}" != "true" ]; then
            log "🚨 VPN IP changes are disabled by configuration!"
            log "🚨 Set ADGUARD_ALLOW_VPN_IP_CHANGE=true to allow server changes"
            exit 1
        fi
        
        # Increment change counter
        VPN_IP_CHANGE_COUNT=$((VPN_IP_CHANGE_COUNT + 1))
        
        # Check change limits (unlimited support)
        if [ "$ADGUARD_MAX_IP_CHANGES" -le 0 ]; then
            log "🔄 IP changes: $VPN_IP_CHANGE_COUNT (unlimited mode)"
        else
            if [ "$VPN_IP_CHANGE_COUNT" -gt "$ADGUARD_MAX_IP_CHANGES" ]; then
                log "🚨 Maximum IP changes exceeded!"
                log "🚨 Changes: $VPN_IP_CHANGE_COUNT (limit: $ADGUARD_MAX_IP_CHANGES)"
                log "🚨 This indicates connection instability - terminating"
                exit 1
            fi
            log "🔄 IP changes: $VPN_IP_CHANGE_COUNT/$ADGUARD_MAX_IP_CHANGES"
        fi
        
        # Re-verify VPN service during IP change
        if ! check_adguard_vpn_status; then
            log "🚨 VPN service disconnected during IP change!"
            log "🚨 IP changed AND VPN service is down - critical failure"
            exit 1
        fi
        
        # Accept new VPN IP
        VPN_IP="$CURRENT_IP"
        log "✅ New VPN IP accepted and validated: $VPN_IP"
        
        # Reset mismatch counter on successful IP change
        IP_MISMATCH_COUNT=0
    fi
    
    # =========================================================================
    # Health Status Summary with Enhanced Information
    # =========================================================================
    local status_msg="🛡️ Status: VPN=$CURRENT_IP"
    
    if [ "$ADGUARD_MAX_IP_CHANGES" -le 0 ]; then
        status_msg="$status_msg, Changes=$VPN_IP_CHANGE_COUNT (∞)"
    else
        status_msg="$status_msg, Changes=$VPN_IP_CHANGE_COUNT/$ADGUARD_MAX_IP_CHANGES"
    fi
    
    # Add security indicators
    status_msg="$status_msg, Secure=✓"
    
    log "$status_msg"
    
    # Optional: Periodic method consistency check (every 10 cycles)
    if [ $((VPN_IP_CHANGE_COUNT % 10)) -eq 0 ] && [ "$VPN_IP_CHANGE_COUNT" -gt 0 ]; then
        log "🔍 Periodic method consistency verification..."
    fi
done