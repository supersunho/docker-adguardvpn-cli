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
export ADGUARD_ALLOW_VPN_IP_CHANGE=${ADGUARD_ALLOW_VPN_IP_CHANGE:-true}
export ADGUARD_MAX_IP_CHANGES=${ADGUARD_MAX_IP_CHANGES:-5}

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
# Initial IP Detection
# =============================================================================

log "📡 Getting current IP..."
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

log "🌐 VPN IP: $VPN_IP"
log "🛡️ Kill Switch monitoring started"

# =============================================================================
# Enhanced Monitoring Loop with Unlimited IP Changes Support
# =============================================================================

while true; do
    sleep $ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
    
    log "💓 Health check..."
    
    # Check VPN service
    if ! check_adguard_vpn_status; then
        log "🚨 VPN service disconnected! Terminating..."
        exit 1
    fi
    
    # Get current IP with retry
    RETRY_COUNT=0
    while [ "$RETRY_COUNT" -lt 3 ]; do
        CURRENT_IP=$(get_public_ip)
        [ "$CURRENT_IP" != "ERROR" ] && break
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "⚠️ IP detection failed (retry $RETRY_COUNT/3)"
        sleep 10
    done
    
    if [ "$CURRENT_IP" = "ERROR" ]; then
        log "🚨 All IP detection failed! Terminating..."
        exit 1
    fi
    
    # Critical: Check traffic leak
    if [ "$CURRENT_IP" = "$REAL_IP_BEFORE_VPN" ]; then
        log "🚨 TRAFFIC LEAK DETECTED! IP: $CURRENT_IP"
        log "🛑 IMMEDIATE TERMINATION"
        exit 1
    fi
    
    # Handle VPN IP change with unlimited support
    if [ "$CURRENT_IP" != "$VPN_IP" ]; then
        log "🔄 VPN IP changed: $VPN_IP → $CURRENT_IP"
        
        if [ "${ADGUARD_ALLOW_VPN_IP_CHANGE,,}" != "true" ]; then
            log "🚨 IP changes disabled! Terminating..."
            exit 1
        fi
        
        VPN_IP_CHANGE_COUNT=$((VPN_IP_CHANGE_COUNT + 1))

        if [ "$ADGUARD_MAX_IP_CHANGES" -le 0 ]; then 
            log "🔄 IP changes: $VPN_IP_CHANGE_COUNT (unlimited)"
        else
            if [ "$VPN_IP_CHANGE_COUNT" -gt "$ADGUARD_MAX_IP_CHANGES" ]; then
                log "🚨 Too many IP changes ($VPN_IP_CHANGE_COUNT)! Connection unstable"
                exit 1
            fi
            log "🔄 IP changes: $VPN_IP_CHANGE_COUNT/$ADGUARD_MAX_IP_CHANGES"
        fi
        
        if ! check_adguard_vpn_status; then
            log "🚨 VPN disconnected during IP change!"
            exit 1
        fi
        
        VPN_IP="$CURRENT_IP"
        log "✅ New VPN IP accepted: $VPN_IP"
    fi
    
    # Success summary with change count display
    if [ "$ADGUARD_MAX_IP_CHANGES" -le 0 ]; then
        log "🛡️ Secure: VPN=$CURRENT_IP, Changes=$VPN_IP_CHANGE_COUNT (unlimited)"
    else
        log "🛡️ Secure: VPN=$CURRENT_IP, Changes=$VPN_IP_CHANGE_COUNT/$ADGUARD_MAX_IP_CHANGES"
    fi
    
done

# =============================================================================
# Script End
# =============================================================================
