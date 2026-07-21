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

# Test 2: supervise_vpn checks semantic VPN status
test_supervise_vpn_checks_status() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q 'check_adguard_vpn_status' "$entrypoint"; then
        echo "  PASS: supervise_vpn checks parsed VPN status"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: supervise_vpn does not use parsed VPN status"
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

# Test 8: supervisor and log tail are waited independently
test_runtime_waits_for_supervisor_independently() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q 'wait -n -p completed_pid' "$entrypoint" && \
       grep -q 'VPN log tail exited — continuing with VPN supervisor' "$entrypoint"; then
        echo "  PASS: log tail cannot block VPN supervision"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: runtime still couples log tail lifetime to VPN supervision"
        FAIL=$((FAIL + 1))
    fi
}

# Test 9: kill-switch failure is propagated without a polling delay
test_kill_switch_waits_for_child_exit() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"
    local kill_switch_block
    kill_switch_block=$(sed -n '/^wait_for_kill_switch() {/,/^}/p' "$entrypoint" 2>/dev/null || true)

    if echo "$kill_switch_block" | grep -q -F "wait \"\${KILL_PID}\"" && \
       ! echo "$kill_switch_block" | grep -q 'sleep 60'; then
        echo "  PASS: Kill Switch failure is waited on directly"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Kill Switch failure can be delayed by polling"
        FAIL=$((FAIL + 1))
    fi
}

# Test 10: the kill-switch wait path returns promptly after the child exits
test_kill_switch_exits_without_polling_delay() {
    local test_dir
    test_dir=$(mktemp -d)
    local runner="${test_dir}/run_wait_kill_switch.sh"

    cat > "$runner" << RUNNER
#!/bin/bash
set -euo pipefail

export ADGUARD_SHOW_LOG=false
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source <(sed -n '/^wait_for_kill_switch() {/,/^}/p' "${PROJECT_DIR}/scripts/docker-entrypoint.sh")

_cleanup_and_exit() {
    printf 'CLEANUP_CODE=%s\\n' "\$1"
    exit "\$1"
}

(exit 1) &
KILL_PID=\$!
wait_for_kill_switch
RUNNER

    chmod +x "$runner"
    local output exit_code
    if output=$(bash "$runner" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -rf "$test_dir"

    if [ "$exit_code" -eq 1 ] && echo "$output" | grep -q 'CLEANUP_CODE=1'; then
        echo "  PASS: Kill Switch exits promptly when its child fails"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Kill Switch child failure was not propagated promptly"
        echo "   Output: ${output}"
        FAIL=$((FAIL + 1))
    fi
}

# Test 9: data directory creation fails fast and reports the actual UID:GID
test_data_directory_permission_failure_is_actionable() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"
    local create_block
    create_block=$(grep -A15 -F 'ensure_data_dir() {' "$entrypoint" || true)

    if echo "$create_block" | grep -q 'exit 78' && \
       grep -q -F "current_gid=\$(id -g)" "$entrypoint" && \
       grep -q -F "current_uid}:\${current_gid}" "$entrypoint"; then
        echo "  PASS: data directory failures stop startup with a UID:GID hint"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: data directory failure handling is incomplete"
        FAIL=$((FAIL + 1))
    fi
}

# Test 10: a missing log file never starts a tail process
test_missing_log_does_not_start_tail() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q -F "if [ -f \"\$LOG_FILE\" ]; then" "$entrypoint" && \
       grep -q 'Continuing without AdGuard VPN log tail' "$entrypoint"; then
        echo "  PASS: missing log file is handled without starting tail"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: missing log file can still start a blocking tail"
        FAIL=$((FAIL + 1))
    fi
}

# Test 11: init.sh failures are captured before the entrypoint exits
test_init_failure_is_captured() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    if grep -q -F 'if /opt/adguardvpn_cli/scripts/init.sh; then' "$entrypoint" && \
       grep -q 'INIT_EXIT_CODE=\$?' "$entrypoint"; then
        echo "  PASS: VPN initialization failures are captured and reported"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: set -e can bypass VPN initialization failure handling"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Functional tests  (run supervise_vpn in isolation with stubs)
# =============================================================================

# Create a temporary test environment with stubs
setup_stubs() {
    local stub_dir="$1"

    # Stub adguardvpn-cli: status reports a connected VPN
    cat > "${stub_dir}/adguardvpn-cli" << 'STUB'
#!/bin/bash
case "${1:-}" in
    status) printf '%s\n' 'Connected in tun mode'; exit 0 ;;
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

# Test 12: supervise_vpn stays alive when VPN status is OK
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
source "${PROJECT_DIR}/scripts/lib/vpn_status.sh"
source <(sed -n '/^supervise_vpn() {/,/^}/p' "${PROJECT_DIR}/scripts/docker-entrypoint.sh")

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
    local exit_code
    if output=$(bash "$runner" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

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

# Test 13: supervise_vpn exits when status output says disconnected
test_supervise_exits_on_fail() {
    local test_dir
    test_dir=$(mktemp -d)
    setup_stubs "$test_dir"

    local runner="${test_dir}/run_supervise_fail.sh"
    cat > "$runner" << RUNNER
#!/bin/bash
set -euo pipefail

# Use a status-reporting stub for adguardvpn-cli
export PATH="${test_dir}:${test_dir}"
# Override: put failing stub first in PATH
export PATH="${test_dir}:${PATH}"

# Create a wrapper that returns success but reports a disconnected VPN.  This
# catches implementations that only trust the CLI process exit code.
cat > "${test_dir}/adguardvpn-cli" << 'STUB'
#!/bin/bash
case "\${1:-}" in
    status) printf '%s\n' 'Disconnected'; exit 0 ;;
    *) exit 0 ;;
esac
STUB
chmod +x "${test_dir}/adguardvpn-cli"

export HOME="${test_dir}/home"
export ADGUARD_SHOW_LOG=false
export ADGUARD_USE_KILL_SWITCH=false

source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/vpn_status.sh"
source <(sed -n '/^supervise_vpn() {/,/^}/p' "${PROJECT_DIR}/scripts/docker-entrypoint.sh")

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
    local exit_code
    if output=$(bash "$runner" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

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

# Test 14: the actual runtime wait logic ignores an early log-tail exit
test_runtime_waits_past_log_tail_exit() {
    local test_dir
    test_dir=$(mktemp -d)
    local runner="${test_dir}/run_wait_runtime.sh"

    cat > "$runner" << RUNNER
#!/bin/bash
set -euo pipefail

export ADGUARD_SHOW_LOG=false
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source <(sed -n '/^wait_for_runtime() {/,/^}/p' "${PROJECT_DIR}/scripts/docker-entrypoint.sh")

_cleanup_and_exit() {
    printf 'CLEANUP_CODE=%s\n' "\$1"
    printf 'TAIL_PID=%s\n' "\${TAIL_PID:-}"
    exit "\$1"
}

/bin/sleep 3 &
SUPERVISE_PID=\$!
/bin/sleep 1 &
TAIL_PID=\$!
wait_for_runtime
RUNNER

    chmod +x "$runner"
    local output exit_code
    if output=$(bash "$runner" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -rf "$test_dir"

    if echo "$output" | grep -q 'CLEANUP_CODE=1' && \
       echo "$output" | grep -q '^TAIL_PID=$' && [ "$exit_code" -eq 1 ]; then
        echo "  PASS: runtime continues after the log tail exits"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: runtime wait stopped with the log tail"
        echo "   Output: ${output}"
        FAIL=$((FAIL + 1))
    fi
}

# Test 15: the actual data-directory guard exits 78 when mkdir cannot work
test_data_directory_guard_fails_fast() {
    local test_dir
    test_dir=$(mktemp -d)
    local runner="${test_dir}/run_data_dir_guard.sh"

    printf '%s\n' 'not-a-directory' > "${test_dir}/blocked"
    cat > "$runner" << RUNNER
#!/bin/bash
set -euo pipefail

export ADGUARD_SHOW_LOG=false
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source <(sed -n '/^ensure_data_dir() {/,/^}/p' "${PROJECT_DIR}/scripts/docker-entrypoint.sh")
ensure_data_dir "${test_dir}/blocked/child"
RUNNER

    chmod +x "$runner"
    local output exit_code
    if output=$(bash "$runner" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -rf "$test_dir"

    if [ "$exit_code" -eq 78 ] && \
       echo "$output" | grep -q 'Could not create data directory'; then
        echo "  PASS: data-directory creation failure exits 78"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: data-directory creation failure was not fatal"
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
test_runtime_waits_for_supervisor_independently
echo ""
test_kill_switch_waits_for_child_exit
echo ""
test_kill_switch_exits_without_polling_delay
echo ""
test_data_directory_permission_failure_is_actionable
echo ""
test_missing_log_does_not_start_tail
echo ""
test_init_failure_is_captured
echo ""
test_supervise_stays_alive_on_ok
echo ""
test_supervise_exits_on_fail
echo ""
test_runtime_waits_past_log_tail_exit
echo ""
test_data_directory_guard_fails_fast
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
