#!/bin/bash

# =============================================================================
# AdGuard VPN Container Entry Point Script - Minimal Logging Version
# =============================================================================

# Import utility functions
source /opt/adguardvpn_cli/scripts/utils.sh

# =============================================================================
# Configuration Setup
# =============================================================================

export ADGUARD_USE_KILL_SWITCH=${ADGUARD_USE_KILL_SWITCH:-true}

log "🚀 AdGuard VPN Container Starting..."
log "🛡️ Kill Switch: ${ADGUARD_USE_KILL_SWITCH}"

# =============================================================================
# Permission Setup
# =============================================================================

# Ensure /dev/net/tun is accessible (default permissions are usually sufficient)
if [ -c /dev/net/tun ]; then
    chmod 666 /dev/net/tun 2>/dev/null || true
fi

# Ensure data directory exists and is writable
DATA_DIR="${HOME}/.local/share/adguardvpn-cli"
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR" 2>/dev/null || true
fi

LOG_FILE="${DATA_DIR}/app.log"

REAL_IP="ERROR"

# Get IP before VPN if kill switch is enabled
if [ "${ADGUARD_USE_KILL_SWITCH,,}" = "true" ]; then
    log "📡 Getting current IP..."
    
    # Detect connection mode for appropriate IP detection method
    local_connection_mode="${ADGUARD_CONNECTION_TYPE,,}"
    
    if [ "$local_connection_mode" = "socks" ]; then
        # For SOCKS mode, use direct IP detection before VPN connection
        # since SOCKS proxy isn't available yet
        log "📡 SOCKS mode detected - using direct IP detection before VPN connection"
        REAL_IP=$(get_public_ip_direct 2>/dev/null) || REAL_IP="ERROR"
    else
        # For TUN mode, use normal IP detection function
        # Use the robust IP detection function from utils.sh with error handling
        REAL_IP=$(get_public_ip 2>/dev/null) || REAL_IP="ERROR"
    fi
    
    # Validate that we got a valid IP address
    if [ "$REAL_IP" = "ERROR" ] || [ -z "$REAL_IP" ]; then
        log "🚨 Failed to get current IP address before VPN connection!"
        log "🚨 Please ensure network connectivity before starting VPN with kill switch"
        exit 1
    fi
fi

# =============================================================================
# VPN Initialization
# =============================================================================

log "🔗 Starting VPN connection..."
/opt/adguardvpn_cli/scripts/init.sh

INIT_EXIT_CODE=$?

if [ "$INIT_EXIT_CODE" -ne 0 ]; then
    log "🚨 VPN initialization failed (code: $INIT_EXIT_CODE)"
    exit $INIT_EXIT_CODE
fi

log "✅ VPN connected successfully"

# =============================================================================
# Log File Setup
# =============================================================================

log "📄 Setting up log monitoring..."

while [ ! -f "$LOG_FILE" ]; do
    sleep 1
done

log "✅ Log file ready"

# Start background log monitoring
tail -F "$LOG_FILE" &
TAIL_PID=$!

# =============================================================================
# Kill Switch Setup
# =============================================================================

if [ "${ADGUARD_USE_KILL_SWITCH,,}" = "true" ]; then
    log "🛡️ Activating Kill Switch..."
    sleep 5;
    
    # Validate IP detection
    if [ "$REAL_IP" = "ERROR" ]; then
        log "🚨 Failed to get IP address!"
        kill "${TAIL_PID}" 2>/dev/null
        exit 1
    fi
    
    log "🌐 Monitoring IP: $REAL_IP"
    
    # Check if kill switch script exists
    if [ ! -f /opt/adguardvpn_cli/scripts/killswitch.sh ]; then
        log "🚨 Kill switch script not found!"
        kill "${TAIL_PID}" 2>/dev/null
        exit 1
    fi
    
    # Make executable if needed
    [ ! -x /opt/adguardvpn_cli/scripts/killswitch.sh ] && chmod +x /opt/adguardvpn_cli/scripts/killswitch.sh
    
    # Export for kill switch script
    export REAL_IP_BEFORE_VPN="$REAL_IP"
    
    # Start kill switch
    /opt/adguardvpn_cli/scripts/killswitch.sh "$REAL_IP" &
    KILL_PID=$!
    
    # Validate kill switch started
    if ! kill -0 "${KILL_PID}" 2>/dev/null; then
        log "🚨 Kill switch failed to start!"
        kill "${TAIL_PID}" 2>/dev/null
        exit 1
    fi
    
    log "✅ Kill switch activated (PID: $KILL_PID)"
    
    # Wait for stability
    sleep 5
    
    if ! kill -0 "${KILL_PID}" 2>/dev/null; then
        log "🚨 Kill switch died within 5 seconds!"
        kill "${TAIL_PID}" 2>/dev/null
        exit 1
    fi
    
    log "🛡️ Container protected - Kill switch monitoring active"
    
    # =========================================================================
    # Kill Switch Monitoring
    # =========================================================================
    
    # Simple monitoring loop
    while kill -0 "${KILL_PID}" 2>/dev/null; do
        sleep 60  # Check every minute
        log "💓 Kill switch running..."
    done
    
    # Kill switch terminated
    log "🛑 Kill switch terminated - Container shutting down"
    
    # Cleanup and exit
    kill "${TAIL_PID}" 2>/dev/null
    exit 1
    
else
    # =========================================================================
    # Kill Switch Disabled
    # =========================================================================
    
    log "⚠️ Kill Switch DISABLED"
    log "ℹ️ Container will continue even if VPN fails"
    
    # Keep container alive with log monitoring only
    wait "${TAIL_PID}"
fi

# =============================================================================
# Container Termination
# =============================================================================

log "🛑 Container shutting down..."

# Cleanup
[ -n "$TAIL_PID" ] && kill "${TAIL_PID}" 2>/dev/null

log "✅ Container exited (code: $INIT_EXIT_CODE)"
exit $INIT_EXIT_CODE