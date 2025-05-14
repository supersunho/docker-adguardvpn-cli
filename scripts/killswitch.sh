#!/bin/bash

export ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL=${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL:-30}

INITIAL_IP_INFO=$(curl -s https://ipinfo.io)
INITIAL_IP=$(echo "$INITIAL_IP_INFO" | awk -F'"' '/"ip":/ {print $4}')
INITIAL_IP_COUNTRY=$(echo "$INITIAL_IP_INFO" | awk -F'"' '/"country":/ {print $4}')
echo " > [Kill Switch] Initial IP: $INITIAL_IP($INITIAL_IP_COUNTRY)"

VPN_IP=""
VPN_CONNECTED=0

while true; do
    if [ "$VPN_CONNECTED" -eq 0 ]; then
        sleep 5
    else
        sleep $ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
    fi
 
    CURRENT_IP_INFO=$(curl -s https://ipinfo.io)
    CURRENT_IP=$(echo "$CURRENT_IP_INFO" | awk -F'"' '/"ip":/ {print $4}')
    CURRENT_IP_COUNTRY=$(echo "$CURRENT_IP_INFO" | awk -F'"' '/"country":/ {print $4}')
    echo " > [Kill Switch] Initial IP: $INITIAL_IP($INITIAL_IP_COUNTRY) => Current IP: $CURRENT_IP($CURRENT_IP_COUNTRY)"

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
