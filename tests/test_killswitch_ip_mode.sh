#!/bin/bash
set -euo pipefail

# Test: kill-switch IP detection respects the connection mode.
#
# In SOCKS mode, every post-connect check must use the SOCKS5 proxy.  In TUN
# mode, the same detector must use direct HTTP.  The test stubs the HTTP
# dispatcher and records only the method ID and proxy flag, so it never needs
# network access.
#
# Usage: bash tests/test_killswitch_ip_mode.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_HOME="$(mktemp -d /tmp/killswitch-ip-test-XXXXXX)"
export HOME="$TEST_HOME"
export ADGUARD_SHOW_LOG=false
export ADGUARD_SHOW_LOG_LEVEL=ERROR

source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/config.sh"
source "${PROJECT_DIR}/scripts/lib/network.sh"
source "${PROJECT_DIR}/scripts/lib/ip_detection.sh"
source "${PROJECT_DIR}/scripts/lib/vpn_status.sh"
source "${PROJECT_DIR}/scripts/lib/killswitch_detector.sh"

CALL_LOG="${HOME}/calls.log"
FAIL_FIRST_HTTP=false

_ip_run_http_method() {
    printf '%s|%s\n' "$1" "${2:-unset}" >> "$CALL_LOG"
    case "$1" in
        aws)
            if [ "$FAIL_FIRST_HTTP" = true ]; then
                return 1
            fi
            printf '%s\n' '198.51.100.7'
            ;;
        ipify) printf '%s\n' '198.51.100.7' ;;
        *) return 1 ;;
    esac
}

PASS=0
FAIL=0

test_detector_uses_direct_http_in_tun_mode() {
    : > "$CALL_LOG"
    export ADGUARD_CONNECTION_TYPE=TUN
    KS_LOCKED_HTTP_ID=""

    local result
    result=$(ks_detect_ip_consistent)

    if [ "$result" = "198.51.100.7" ] && grep -qx 'aws|false' "$CALL_LOG"; then
        echo "  PASS: TUN detection uses direct HTTP"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: TUN detection did not use direct HTTP"
        echo "   Calls: $(tr '\n' ' ' < "$CALL_LOG")"
        FAIL=$((FAIL + 1))
    fi
}

test_detector_uses_socks5_for_discovery() {
    : > "$CALL_LOG"
    export ADGUARD_CONNECTION_TYPE=SOCKS
    KS_LOCKED_HTTP_ID=""

    local result
    result=$(ks_detect_ip_consistent)

    if [ "$result" = "198.51.100.7" ] && grep -qx 'aws|true' "$CALL_LOG"; then
        echo "  PASS: SOCKS discovery uses SOCKS5 HTTP"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: SOCKS discovery did not use SOCKS5 HTTP"
        echo "   Calls: $(tr '\n' ' ' < "$CALL_LOG")"
        FAIL=$((FAIL + 1))
    fi
}

test_detector_uses_socks5_for_locked_method() {
    : > "$CALL_LOG"
    export ADGUARD_CONNECTION_TYPE=SOCKS
    KS_LOCKED_HTTP_ID=aws

    local result
    result=$(ks_detect_ip_consistent)

    if [ "$result" = "198.51.100.7" ] && grep -qx 'aws|true' "$CALL_LOG"; then
        echo "  PASS: SOCKS locked method uses SOCKS5 HTTP"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: SOCKS locked method did not use SOCKS5 HTTP"
        echo "   Calls: $(tr '\n' ' ' < "$CALL_LOG")"
        FAIL=$((FAIL + 1))
    fi
}

test_detector_continues_after_method_failure() {
    : > "$CALL_LOG"
    export ADGUARD_CONNECTION_TYPE=TUN
    FAIL_FIRST_HTTP=true
    KS_LOCKED_HTTP_ID=""

    local result
    result=$(ks_detect_ip_consistent)
    FAIL_FIRST_HTTP=false

    if [ "$result" = "198.51.100.7" ] && \
       grep -qx 'aws|false' "$CALL_LOG" && \
       grep -qx 'ipify|false' "$CALL_LOG"; then
        echo "  PASS: detector tries the next HTTP method after failure"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: detector stopped after the first HTTP method failure"
        echo "   Calls: $(tr '\n' ' ' < "$CALL_LOG")"
        FAIL=$((FAIL + 1))
    fi
}

echo "=========================================="
echo " Kill-switch IP Mode Tests"
echo "=========================================="
echo ""

test_detector_uses_direct_http_in_tun_mode
test_detector_uses_socks5_for_discovery
test_detector_uses_socks5_for_locked_method
test_detector_continues_after_method_failure

echo ""
echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

rm -rf "$HOME"
exit $(( FAIL > 0 ? 1 : 0 ))
