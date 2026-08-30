#!/bin/bash
set -euo pipefail

# Unit tests for the mode-aware container healthcheck.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_HOME="$(mktemp -d /tmp/adguard-healthcheck-test-XXXXXX)"
export HOME="$TEST_HOME"
export ADGUARD_SHOW_LOG=false
export ADGUARD_SHOW_LOG_LEVEL=ERROR

# shellcheck source=../scripts/healthcheck.sh
source "${PROJECT_DIR}/scripts/healthcheck.sh"

PASS=0
FAIL=0

test_tun_uses_status() {
    ADGUARD_CONNECTION_TYPE=TUN
    check_adguard_vpn_status() { return 0; }
    if healthcheck_main; then
        echo "  PASS: TUN healthcheck uses CLI status"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: TUN healthcheck rejected connected status"
        FAIL=$((FAIL + 1))
    fi
}

test_socks_requires_listener() {
    ADGUARD_CONNECTION_TYPE=SOCKS
    ks_socks_port_listening() { return 1; }
    ks_detect_ip_consistent() { echo "198.51.100.20"; return 0; }
    if healthcheck_main; then
        echo "  FAIL: SOCKS healthcheck accepted a closed listener"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: SOCKS healthcheck fails when listener is closed"
        PASS=$((PASS + 1))
    fi
}

test_socks_requires_proxy_egress() {
    ADGUARD_CONNECTION_TYPE=SOCKS
    ks_socks_port_listening() { return 0; }
    ks_detect_ip_consistent() { echo "ERROR"; return 1; }
    if healthcheck_main; then
        echo "  FAIL: SOCKS healthcheck accepted a failed egress probe"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: SOCKS healthcheck fails when proxy egress is unavailable"
        PASS=$((PASS + 1))
    fi
}

test_socks_accepts_proxy_egress() {
    ADGUARD_CONNECTION_TYPE=SOCKS
    ks_socks_port_listening() { return 0; }
    ks_detect_ip_consistent() { echo "198.51.100.20"; return 0; }
    if healthcheck_main; then
        echo "  PASS: SOCKS healthcheck accepts a valid proxy egress response"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: SOCKS healthcheck rejected a valid proxy egress response"
        FAIL=$((FAIL + 1))
    fi
}

echo "=========================================="
echo " Healthcheck Tests"
echo "=========================================="
echo ""
test_tun_uses_status
test_socks_requires_listener
test_socks_requires_proxy_egress
test_socks_accepts_proxy_egress
echo ""
echo "Results: $PASS passed, $FAIL failed (healthcheck)"

rm -rf "$TEST_HOME"
exit $(( FAIL > 0 ? 1 : 0 ))
