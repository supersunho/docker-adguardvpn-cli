#!/bin/bash
#
# AdGuard VPN -- Container healthcheck
#
# TUN mode uses the CLI's connected status. SOCKS mode additionally requires
# a listening proxy and a successful public-IP request through that proxy;
# a local listener alone is not proof that traffic is tunneled.

set -euo pipefail

_HEALTHCHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${_HEALTHCHECK_DIR}/utils.sh"
unset _HEALTHCHECK_DIR

healthcheck_main() {
    config_bootstrap

    if ! is_socks_mode; then
        check_adguard_vpn_status
        return $?
    fi

    if ! ks_socks_port_listening; then
        log ERROR "SOCKS5 proxy port is not listening"
        return 1
    fi

    local proxy_ip=""
    proxy_ip=$(ks_detect_ip_consistent 2>/dev/null) || true
    if ! _is_valid_ipv4 "$proxy_ip"; then
        log ERROR "SOCKS5 proxy egress probe failed"
        return 1
    fi

    log DEBUG "SOCKS5 proxy egress is healthy (${proxy_ip})"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    healthcheck_main
fi
