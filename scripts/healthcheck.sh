#!/bin/bash
set -euo pipefail

# =============================================================================
# AdGuard VPN Container Health Check
# =============================================================================
#
# Reports container health to Docker. The check is mode-aware:
#   - Always: adguardvpn-cli must report an active connection, using the same
#     "Connected.*mode" regex as check_adguard_vpn_status() in vpn_status.sh.
#   - SOCKS mode: additionally verify the SOCKS5 listener accepts connections.
#
# The SOCKS probe performs a *bare TCP handshake* (no SOCKS negotiation and no
# application data), so credentials are never exchanged with the proxy and
# nothing is written to logs. The script deliberately does not read the SOCKS
# username/password variables, and performs no proxied curl.
#
# The logic lives in source-able functions with a guarded main so that unit
# tests can load and exercise them directly. Running as a script exits 0 when
# healthy and 1 otherwise, per Docker healthcheck convention.

# VPN must report an active connection.
# Returns 0 if connected, 1 otherwise.
healthcheck_vpn_connected() {
    if ! command -v adguardvpn-cli >/dev/null 2>&1; then
        return 1
    fi

    local status
    status="$(adguardvpn-cli status 2>/dev/null)" || true

    [[ "$status" =~ Connected.*mode ]]
}

# SOCKS5 listener must accept a bare TCP connection.
# Returns 0 if a connection is accepted, 1 otherwise.
healthcheck_socks_listener_up() {
    local host="${ADGUARD_SOCKS5_HOST:-127.0.0.1}"
    local port="${ADGUARD_SOCKS5_PORT:-1080}"
    local connect_host="$host"

    # A listener bound to 0.0.0.0 is reachable via loopback but not connectable
    # through the wildcard address itself.
    [ "$connect_host" = "0.0.0.0" ] && connect_host="127.0.0.1"

    # Bare TCP three-way handshake only -- no SOCKS negotiate step, so no
    # credentials are sent to the proxy, and nothing is echoed to logs.
    timeout 3 bash -c "exec 3<>/dev/tcp/${connect_host}/${port}" 2>/dev/null
}

# Mode-aware overall health decision.
# Returns 0 if healthy, 1 otherwise.
healthcheck_run() {
    local mode connected listener_up
    mode="${ADGUARD_CONNECTION_TYPE,,}"

    connected=0
    if healthcheck_vpn_connected; then
        connected=1
    fi

    listener_up=0
    if [ "$mode" = "socks" ]; then
        if healthcheck_socks_listener_up; then
            listener_up=1
        fi
    else
        # Non-SOCKS modes rely on the status check alone.
        listener_up=1
    fi

    if [ "$connected" -eq 1 ] && [ "$listener_up" -eq 1 ]; then
        return 0
    fi
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if healthcheck_run; then
        exit 0
    fi
    exit 1
fi