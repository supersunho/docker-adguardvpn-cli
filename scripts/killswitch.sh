#!/bin/bash

export ADGUARD_USE_KILL_SWITCH_TIME=${ADGUARD_USE_KILL_SWITCH_TIME:-30}

INITIAL_IP=$(curl -s https://ipinfo.io/ip)
echo " > [Kill Switch] Initial IP: $INITIAL_IP"

VPN_IP=""
VPN_CONNECTED=0

while true; do
    sleep $ADGUARD_USE_KILL_SWITCH_TIME
    CURRENT_IP=$(curl -s https://ipinfo.io/ip)
    echo " > [Kill Switch] Initial IP: $INITIAL_IP / Current IP: $CURRENT_IP"

    if [ "$VPN_CONNECTED" -eq 0 ]; then
        # If VPN is not connected yet, detect the first IP change (assume VPN connected)
        if [ "$CURRENT_IP" != "$INITIAL_IP" ]; then
            VPN_IP="$CURRENT_IP"
            VPN_CONNECTED=1
            echo " > [Kill Switch] VPN connection detected! VPN IP: $VPN_IP"
        fi
    else
        # If VPN is already connected, exit if IP changes again
        if [ "$CURRENT_IP" != "$VPN_IP" ]; then
            echo " > [Kill Switch] VPN IP changed again! Exiting container."
            exit 1
        fi
    fi
done
