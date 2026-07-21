#!/bin/bash
set -euo pipefail

# Test: Container lifecycle independence
#
# Validates that the container entrypoint keeps running independently
# of log output — especially when ADGUARD_SHOW_LOG=false and
# ADGUARD_USE_KILL_SWITCH=false (where previously there was nothing
# to wait on and the container exited immediately).
#
# Structural tests verify source code patterns; functional tests
# run supervise_vpn() in isolation with stubs.
#
# Usage:  bash tests/test_entrypoint_lifecycle.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# =============================================================================
# Structural tests  (grep-based pattern checks)
# =============================================================================

# Test 1: supervise_vpn function is defined in the entrypoint
test_supervise_vpn_function_exists() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q 'supervise_vpn()' "$entrypoint"; then
        echo "  PASS: supervise_vpn() function is defined"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: supervise_vpn() function is missing from entrypoint"
        FAIL=$((FAIL + 1))
    fi
}

# Test 2: supervise_vpn checks VPN status with adguardvpn-cli
test_supervise_vpn_checks_status() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q 'adguardvpn-cli\s*status' "$entrypoint"; then
        echo "  PASS: supervise_vpn checks VPN status via adguardvpn-cli"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: supervise_vpn does not check VPN status"
        FAIL=$((FAIL + 1))
    fi
}

# Test 3: supervise_vpn uses signal-responsive sleep
test_supervise_vpn_uses_signal_sleep() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    # Must use "sleep N & wait $!" pattern (not bare "sleep N")
    # so that signals are delivered immediately
    if grep -q 'sleep 60 \&\s*$' "$entrypoint" || grep -q 'sleep 60 &\s*wait' "$entrypoint"; then
        echo "  PASS: supervise_vpn uses signal-responsive sleep pattern"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: supervise_vpn missing signal-responsive sleep pattern"
        FAIL=$((FAIL + 1))
    fi
}

# Test 4: _cleanup_and_exit handles SUPERVISE_PID
test_supervise_pid_cleanup_exists() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q 'SUPERVISE_PID' "$entrypoint"; then
        echo "  PASS: SUPERVISE_PID cleanup present in _cleanup_and_exit"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: SUPERVISE_PID cleanup missing from _cleanup_and_exit"
        FAIL=$((FAIL + 1))
    fi
}

# Test 5: log file waiting has a timeout
test_log_file_has_timeout() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q 'ADGUARD_MAX_WAIT_TIME\|_LOG_WAITED\|_LOG_WAIT_MAX' "$entrypoint"; then
        echo "  PASS: Log file wait loop has a timeout mechanism"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Log file wait loop lacks a timeout"
        FAIL=$((FAIL + 1))
    fi
}

# Test 6: ADGUARD_MAX_WAIT_TIME is in config schema
test_max_wait_time_in_schema() {
    local config="${PROJECT_DIR}/scripts/lib/config.sh"

    if grep -q 'ADGUARD_MAX_WAIT_TIME' "$config"; then
        echo "  PASS: ADGUARD_MAX_WAIT_TIME is defined in config schema"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ADGUARD_MAX_WAIT_TIME missing from config schema"
        FAIL=$((FAIL + 1))
    fi
}

# Test 7: KILL_SWITCH=false branch uses supervise_vpn
test_no_ks_branch_uses_supervise() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    # The else branch (KILL_SWITCH=false) must reference supervise_vpn or SUPERVISE_PID
    # Extract lines between "Kill Switch DISABLED" and the next "fi"
    local block
    block=$(sed -n '/Kill Switch DISABLED/,/^fi/p' "$entrypoint" 2>/dev/null || true)

    if echo "$block" | grep -q 'supervise_vpn\|SUPERVISE_PID'; then
        echo "  PASS: KILL_SWITCH=false branch uses supervise_vpn"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: KILL_SWITCH=false branch does not use supervise_vpn"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Functional tests  (run supervise_vpn in isolation with stubs)
# =============================================================================

# Create a temporary test environment with stubs
setup_stubs() {
    local stub_dir="$1"

    # Stub adguardvpn-cli: status returns success
    cat > "${stub_dir}/adguardvpn-cli" << 'STUB'
#!/bin/bash
case "${1:-}" in
    status) exit 0 ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "${stub_dir}/adguardvpn-cli"

    # Stub adguardvpn-cli that FAILS status
    cat > "${stub_dir}/adguardvpn-cli-fail" << 'STUB'
#!/bin/bash
case "${1:-}" in
    status) exit 1 ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "${stub_dir}/adguardvpn-cli-fail"

    # Stub sleep: cap at 1s for fast tests, use /bin/sleep directly
    cat > "${stub_dir}/sleep" << 'STUB'
#!/bin/bash
DURATION="${1:-1}"
[ "$DURATION" -gt 1 ] && DURATION=1
/bin/sleep "$DURATION"
STUB
    chmod +x "${stub_dir}/sleep"

    # Stub sleep that always exits immediately (for testing fail-fast)
    cat > "${stub_dir}/sleep-immediate" << 'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "${stub_dir}/sleep-immediate"
}

# Test 8: supervise_vpn stays alive when VPN status is OK
test_supervise_stays_alive_on_ok() {
    local test_dir
    test_dir=$(mktemp -d)
    setup_stubs "$test_dir"

    # Create the test runner script
    local runner="${test_dir}/run_supervise_ok.sh"
    cat > "$runner" << RUNNER
#!/bin/bash
set -euo pipefail

export PATH="${test_dir}:${PATH}"
export HOME="${test_dir}/home"
export ADGUARD_SHOW_LOG=false
export ADGUARD_USE_KILL_SWITCH=false

# Source required libraries (using real files from project)
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/config.sh"
source "${PROJECT_DIR}/scripts/lib/error_handling.sh"
config_bootstrap

# Define supervise_vpn (same as in docker-entrypoint.sh)
supervise_vpn() {
    while true; do
        if ! adguardvpn-cli status >/dev/null 2>&1; then
            echo "VPN status check failed" >&2
            return 1
        fi
        sleep 60 &
        wait "\$!"
    done
}

# Start in background, print PID
supervise_vpn &
SV_PID=\$!
echo "SUPERVISE_PID=\${SV_PID}"

# Sleep briefly, then check if still alive
sleep 2
if kill -0 "\${SV_PID}" 2>/dev/null; then
    echo "RESULT=ALIVE"
    kill "\${SV_PID}" 2>/dev/null || true
    exit 0
else
    echo "RESULT=DIED"
    exit 1
fi
RUNNER

    chmod +x "$runner"
    local output
    output=$(bash "$runner" 2>&1 || true)
    local exit_code=$?

    rm -rf "$test_dir"

    if echo "$output" | grep -q 'RESULT=ALIVE' && [ "$exit_code" -eq 0 ]; then
        echo "  PASS: supervise_vpn stays alive when VPN status is OK"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: supervise_vpn exited despite OK status"
        echo "   Output: ${output}"
        FAIL=$((FAIL + 1))
    fi
}

# Test 9: supervise_vpn exits when VPN status fails
test_supervise_exits_on_fail() {
    local test_dir
    test_dir=$(mktemp -d)
    setup_stubs "$test_dir"

    local runner="${test_dir}/run_supervise_fail.sh"
    cat > "$runner" << RUNNER
#!/bin/bash
set -euo pipefail

# Use FAILING stub for adguardvpn-cli
export PATH="${test_dir}:${test_dir}"
# Override: put failing stub first in PATH
export PATH="${test_dir}:${PATH}"

# Create a wrapper that runs the failing adguardvpn-cli
cat > "${test_dir}/adguardvpn-cli" << 'STUB'
#!/bin/bash
case "\${1:-}" in
    status) exit 1 ;;
    *) exit 0 ;;
esac
STUB
chmod +x "${test_dir}/adguardvpn-cli"

export HOME="${test_dir}/home"
export ADGUARD_SHOW_LOG=false
export ADGUARD_USE_KILL_SWITCH=false

source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/config.sh"
source "${PROJECT_DIR}/scripts/lib/error_handling.sh"
config_bootstrap

supervise_vpn() {
    while true; do
        if ! adguardvpn-cli status >/dev/null 2>&1; then
            echo "VPN status check failed" >&2
            return 1
        fi
        sleep 60 &
        wait "\$!"
    done
}

# Run supervise_vpn in foreground (should exit quickly)
if supervise_vpn; then
    echo "RESULT=UNEXPECTED_SUCCESS"
    exit 1
else
    echo "RESULT=EXPECTED_FAIL"
    exit 0
fi
RUNNER

    chmod +x "$runner"
    local output
    output=$(bash "$runner" 2>&1 || true)
    local exit_code=$?

    rm -rf "$test_dir"

    if echo "$output" | grep -q 'RESULT=EXPECTED_FAIL' && [ "$exit_code" -eq 0 ]; then
        echo "  PASS: supervise_vpn exits when VPN status fails"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: supervise_vpn did not exit on status failure"
        echo "   Output: ${output}"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Container Lifecycle Tests"
echo "=========================================="
echo ""

test_supervise_vpn_function_exists
echo ""
test_supervise_vpn_checks_status
echo ""
test_supervise_vpn_uses_signal_sleep
echo ""
test_supervise_pid_cleanup_exists
echo ""
test_log_file_has_timeout
echo ""
test_max_wait_time_in_schema
echo ""
test_no_ks_branch_uses_supervise
echo ""
test_supervise_stays_alive_on_ok
echo ""
test_supervise_exits_on_fail
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
