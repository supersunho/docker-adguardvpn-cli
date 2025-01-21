#!/bin/bash 

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
export ADGUARD_USE_QUIC=${ADGUARD_USE_QUIC:-false}

echo "Login Adguard VPN and test connection..."
adguardvpn-cli login -u "$ADGUARD_USERNAME" -p "$ADGUARD_PASSWORD"
adguardvpn-cli config set-mode "$ADGUARD_CONNECTION_TYPE" 
adguardvpn-cli connect -f -y
adguardvpn-cli disconnect
adguardvpn-cli config clear-socks-auth

if [ "${ADGUARD_USE_CUSTOM_DNS,,}" = true ]; then
    adguardvpn-cli config set-dns "$ADGUARD_CUSTOM_DNS"
fi
if [ "${ADGUARD_USE_QUIC,,}" = true ]; then
    adguardvpn-cli config set-use-quic on
fi

echo "Configure Adguard VPN" 
if [ "${ADGUARD_SET_SYSTEM_DNS,,}" = false ]; then 
    echo "adguardvpn-cli config set-system-dns off"
    adguardvpn-cli config set-system-dns off
fi

if [ "${ADGUARD_SEND_REPORTS,,}" = false ]; then 
    echo "adguardvpn-cli config send-reports off"
    adguardvpn-cli config send-reports off
fi

echo "Running Adguard VPN" 
Log "adguardvpn-cli connect -l $ADGUARD_CONNECTION_LOCATION"
if [ "${ADGUARD_CONNECTION_TYPE,,}" = "SOCKS" ]; then
    adguardvpn-cli config set-socks-username "$ADGUARD_SOCKS5_USERNAME"
    adguardvpn-cli config set-socks-password "$ADGUARD_SOCKS5_PASSWORD"
fi
adguardvpn-cli connect -l "$ADGUARD_CONNECTION_LOCATION"

echo "Testing Adguard VPN"
adguardvpn-cli status

tail -f /root/.local/share/adguardvpn-cli/app.log