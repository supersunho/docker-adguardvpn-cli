#!/bin/bash 

# Import utility functions
source /opt/adguardvpn_cli/scripts/utils.sh

export ADGUARD_USERNAME=${ADGUARD_USERNAME:-"username"} 
export ADGUARD_PASSWORD=${ADGUARD_PASSWORD:-"password"} 
export ADGUARD_CONNECTION_LOCATION=${ADGUARD_CONNECTION_LOCATION:-"JP"} 
export ADGUARD_CONNECTION_TYPE=${ADGUARD_CONNECTION_TYPE:-"TUN"} 
export ADGUARD_SOCKS5_USERNAME=${ADGUARD_SOCKS5_USERNAME:-"username"} 
export ADGUARD_SOCKS5_PASSWORD=${ADGUARD_SOCKS5_PASSWORD:-"password"} 
export ADGUARD_SOCKS5_HOST=${ADGUARD_SOCKS5_HOST:-"127.0.0.1"} 
export ADGUARD_SOCKS5_PORT=${ADGUARD_SOCKS5_PORT:-1080} 
export ADGUARD_SEND_REPORTS=${ADGUARD_SEND_REPORTS:-false} 
export ADGUARD_SET_SYSTEM_DNS=${ADGUARD_SET_SYSTEM_DNS:-false} 
export ADGUARD_USE_CUSTOM_DNS=${ADGUARD_USE_CUSTOM_DNS:-false}
export ADGUARD_CUSTOM_DNS=${ADGUARD_CUSTOM_DNS:-"1.1.1.1"}

export ADGUARD_UPDATE_CHANNEL=${ADGUARD_UPDATE_CHANNEL:-"release"}
export ADGUARD_SHOW_HINTS=${ADGUARD_SHOW_HINTS:-"on"}
export ADGUARD_DEBUG_LOGGING=${ADGUARD_DEBUG_LOGGING:-"on"}
export ADGUARD_SHOW_NOTIFICATIONS=${ADGUARD_SHOW_NOTIFICATIONS:-"on"}
export ADGUARD_PROTOCOL=${ADGUARD_PROTOCOL:-"auto"}
export ADGUARD_POST_QUANTUM=${ADGUARD_POST_QUANTUM:-"off"}

log "Updating Adguard VPN CLI..."
adguardvpn-cli update

log "Login Adguard VPN and test connection..."
adguardvpn-cli login -u "$ADGUARD_USERNAME" -p "$ADGUARD_PASSWORD"
adguardvpn-cli config set-mode "$ADGUARD_CONNECTION_TYPE" 
adguardvpn-cli connect -f -y
adguardvpn-cli disconnect
adguardvpn-cli config clear-socks-auth

adguardvpn-cli config set-update-channel "$ADGUARD_UPDATE_CHANNEL"
adguardvpn-cli config set-show-hints "$ADGUARD_SHOW_HINTS"
adguardvpn-cli config set-debug-logging "$ADGUARD_DEBUG_LOGGING"
adguardvpn-cli config set-show-notifications "$ADGUARD_SHOW_NOTIFICATIONS"
adguardvpn-cli config set-protocol "$ADGUARD_PROTOCOL"
adguardvpn-cli config set-post-quantum "$ADGUARD_POST_QUANTUM"

if [ "${ADGUARD_USE_CUSTOM_DNS,,}" = true ]; then
    adguardvpn-cli config set-dns "$ADGUARD_CUSTOM_DNS"
fi

log "Configure Adguard VPN" 
if [ "${ADGUARD_SET_SYSTEM_DNS,,}" = false ]; then 
    log "adguardvpn-cli config set-change-system-dns  off"
    adguardvpn-cli config set-change-system-dns off
fi

if [ "${ADGUARD_SEND_REPORTS,,}" = false ]; then 
    log "adguardvpn-cli config set-crash-reporting off"
    adguardvpn-cli config set-crash-reporting off
fi

log "Running Adguard VPN" 
log "adguardvpn-cli connect -l $ADGUARD_CONNECTION_LOCATION"
if [ "${ADGUARD_CONNECTION_TYPE,,}" = "SOCKS" ]; then
    adguardvpn-cli config set-socks-username "$ADGUARD_SOCKS5_USERNAME"
    adguardvpn-cli config set-socks-password "$ADGUARD_SOCKS5_PASSWORD"
fi
adguardvpn-cli connect -l "$ADGUARD_CONNECTION_LOCATION"

log "Adguard VPN Status"

adguardvpn-cli status

