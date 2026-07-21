#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

assert_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        echo "    expected: ${expected}"
        echo "    actual:   ${actual}"
        FAIL=$((FAIL + 1))
    fi
}

test_auth_failures_reset_data_on_threshold() {
    local test_dir
    test_dir=$(mktemp -d)
    local data_dir="${test_dir}/data"
    mkdir -p "$data_dir"
    printf '%s\n' 'session' > "${data_dir}/session.json"

    export DATA_DIR="$data_dir"
    export AUTH_FAILURE_FILE="${data_dir}/.auth-failures"
    export ADGUARD_AUTH_RESET_AFTER_FAILURES=3
    export ADGUARD_SHOW_LOG=false

    source "${PROJECT_DIR}/scripts/lib/logging.sh"
    # shellcheck disable=SC1090
    source <(sed -n '/^_reset_auth_data() {/,/^}/p' "${PROJECT_DIR}/scripts/init.sh")
    # shellcheck disable=SC1090
    source <(sed -n '/^_record_auth_failure() {/,/^}/p' "${PROJECT_DIR}/scripts/init.sh")

    _record_auth_failure
    assert_equals "first authentication failure is recorded" "1" "$(cat "$AUTH_FAILURE_FILE")"
    _record_auth_failure
    assert_equals "second authentication failure is recorded" "2" "$(cat "$AUTH_FAILURE_FILE")"
    _record_auth_failure

    local remaining
    remaining=$(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -print -quit)
    assert_equals "third authentication failure resets persisted data" "" "$remaining"

    rm -rf "$test_dir"
}

test_auth_detection_does_not_use_runtime_pid_file() {
    if grep -q 'vpn\.pid' "${PROJECT_DIR}/scripts/init.sh"; then
        echo "  FAIL: authentication detection still uses the VPN runtime PID file"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: authentication detection does not use the VPN runtime PID file"
        PASS=$((PASS + 1))
    fi
}

test_init_does_not_clear_socks_auth_before_configuration() {
    if grep -q 'config clear-socks-auth' "${PROJECT_DIR}/scripts/init.sh"; then
        echo "  FAIL: init.sh clears SOCKS authentication before the safe setup helper"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: init.sh delegates SOCKS authentication setup to the helper"
        PASS=$((PASS + 1))
    fi
}

echo "=========================================="
echo " Authentication Recovery Tests"
echo "=========================================="
echo ""

test_auth_failures_reset_data_on_threshold
test_auth_detection_does_not_use_runtime_pid_file
test_init_does_not_clear_socks_auth_before_configuration

echo ""
echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
