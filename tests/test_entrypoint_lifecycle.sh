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

# Test 11: kill-switch startup is monitored immediately by its own wait loop
test_kill_switch_has_no_blind_startup_sleep() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"
    local kill_switch_block
    # shellcheck disable=SC2016 # sed range intentionally matches literal shell syntax.
    kill_switch_block=$(sed -n '/^if \[ "\${ADGUARD_USE_KILL_SWITCH,,}" = "true" \]; then/,/^else$/p' "$entrypoint" 2>/dev/null || true)

    if echo "$kill_switch_block" | grep -q '/opt/adguardvpn_cli/scripts/killswitch.sh' && \
       ! echo "$kill_switch_block" | grep -q '_KS_STABILIZE_DELAY\|Stabilizing VPN connection'; then
        echo "  PASS: Kill Switch starts without a blind startup grace sleep"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Kill Switch still has an unmonitored startup sleep"
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
test_kill_switch_has_no_blind_startup_sleep
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

# =============================================================================
# Grace boundary deterministic tests (A)
#
# Run the actual supervise_vpn() with a stubbed `sleep` that records its
# arguments and immediately returns.  Each case verifies both the per-tick
# sequence and the running total matches the configured grace window.
# =============================================================================

# Stub sleep that records its first argument to a log file and returns
# immediately.  Background form (sleep N &) is preserved by also returning
# 0 promptly so `wait "$!"` reaps the child without blocking.
# Only integer-argument calls are recorded so that the runner's own
# `sleep 0.1` plumbing call (which the stub PATH would otherwise catch)
# does not contaminate the recorded sequence.
RECORD_SLEEP_LOG=""
record_sleep_setup() {
    local stub_dir="$1"
    RECORD_SLEEP_LOG="${stub_dir}/sleep.log"
    : > "$RECORD_SLEEP_LOG"
    cat > "${stub_dir}/sleep" << STUB
#!/bin/bash
ARG="\${1:-0}"
if [[ "\$ARG" =~ ^[0-9]+\$ ]]; then
    printf '%s\n' "\$ARG" >> "${RECORD_SLEEP_LOG}"
fi
exit 0
STUB
    chmod +x "${stub_dir}/sleep"
}

# Write the grace recorder runner for a given grace value.  The runner
# shadows `sleep` via PATH so each call from supervise_vpn is recorded.
# Plumbing sleeps in the runner itself use /bin/sleep to avoid the shadow.
write_grace_runner() {
    local test_dir="$1"
    local grace_value="$2"
    local runner="${test_dir}/run_grace.sh"
    local project_dir="$PROJECT_DIR"
    cat > "$runner" << RUNNER
#!/bin/bash
set -uo pipefail
hash -r
export PATH="${test_dir}:\${PATH}"
export HOME="${test_dir}/home"
export ADGUARD_SHOW_LOG=false
export ADGUARD_USE_KILL_SWITCH=false
export ADGUARD_VPN_STARTUP_GRACE_SECONDS="${grace_value}"
source "${project_dir}/scripts/lib/logging.sh"
source "${project_dir}/scripts/lib/vpn_status.sh"
source <(sed -n '/^supervise_vpn() {/,/^}/p' "${project_dir}/scripts/docker-entrypoint.sh")
check_adguard_vpn_status() { return 1; }
supervise_vpn &
SV_PID=\$!
# Wait at least grace_value seconds so the recorded sleep sequence
# completes.  The supervisor runs for the full grace period when status
# keeps failing, so a shorter wait truncates the recorded log.
/bin/sleep "${grace_value}"
# A small additional wait lets the backgrounded stub sleep finish its
# write to the log before we tear the supervisor down.
/bin/sleep 0.5
kill "\${SV_PID}" 2>/dev/null || true
wait "\${SV_PID}" 2>/dev/null || true
echo "GRACE_LOG_START"
cat "${test_dir}/sleep.log" 2>/dev/null || true
echo "GRACE_LOG_END"
RUNNER
    chmod +x "$runner"
}

# Run supervise_vpn with stubbed sleep + always-failing status, then return
# the contents of the sleep log on stdout (between GRACE_LOG_START/END markers).
# The runner uses PATH-based sleep shadowing; the runner's own plumbing uses
# /bin/sleep to bypass that shadow.
run_grace_recorder() {
    local test_dir="$1"
    local grace_value="$2"
    write_grace_runner "$test_dir" "$grace_value"
    local runner="${test_dir}/run_grace.sh"
    local raw
    raw=$(bash "$runner" 2>/dev/null || true)
    # Extract only the segment between markers so any stray output is excluded.
    local between
    between=$(printf '%s' "$raw" | sed -n '/^GRACE_LOG_START$/,/^GRACE_LOG_END$/p' | sed '1d;$d')
    printf '%s' "$between"
}

assert_grace_sequence() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: ${label} — sleeps=${actual}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label} — expected=${expected} actual=${actual}"
        FAIL=$((FAIL + 1))
    fi
}

test_grace_0_emits_no_sleeps() {
    local test_dir
    test_dir=$(mktemp -d)
    record_sleep_setup "$test_dir"
    local actual
    actual=$(run_grace_recorder "$test_dir" 0 | tr '\n' ',' | sed 's/,$//')
    assert_grace_sequence "grace=0 emits no sleep calls" "" "$actual"
    rm -rf "$test_dir"
}

test_grace_1_emits_one_sleep_of_one_second() {
    local test_dir
    test_dir=$(mktemp -d)
    record_sleep_setup "$test_dir"
    local actual
    actual=$(run_grace_recorder "$test_dir" 1 | tr '\n' ',' | sed 's/,$//')
    assert_grace_sequence "grace=1 emits one 1s sleep" "1" "$actual"
    rm -rf "$test_dir"
}

test_grace_6_emits_sleeps_five_then_one() {
    local test_dir
    test_dir=$(mktemp -d)
    record_sleep_setup "$test_dir"
    local actual
    actual=$(run_grace_recorder "$test_dir" 6 | tr '\n' ',' | sed 's/,$//')
    assert_grace_sequence "grace=6 emits 5s then 1s" "5,1" "$actual"
    rm -rf "$test_dir"
}

test_grace_30_emits_six_five_second_sleeps() {
    local test_dir
    test_dir=$(mktemp -d)
    record_sleep_setup "$test_dir"
    local actual
    actual=$(run_grace_recorder "$test_dir" 30 | tr '\n' ',' | sed 's/,$//')
    assert_grace_sequence "grace=30 emits six 5s sleeps" "5,5,5,5,5,5" "$actual"
    rm -rf "$test_dir"
}

test_grace_600_emits_one_twenty_five_second_sleeps() {
    local test_dir
    test_dir=$(mktemp -d)
    record_sleep_setup "$test_dir"
    # 600 / 5 = 120 ticks.  The stub sleep returns immediately, so the
    # grace loop iterates all 120 ticks in milliseconds (sum = 600).
    # We verify the cap-at-5 invariant exactly: every recorded sleep is
    # exactly 5, count == 120, sum == 600, cap_violation == 0.  Any of
    # these being off means the remainder/accumulation fix has regressed.
    local runner="${test_dir}/run_grace_600.sh"
    cat > "$runner" << RUNNER
#!/bin/bash
set -uo pipefail
hash -r
export PATH="${test_dir}:\${PATH}"
export HOME="${test_dir}/home"
export ADGUARD_SHOW_LOG=false
export ADGUARD_USE_KILL_SWITCH=false
export ADGUARD_VPN_STARTUP_GRACE_SECONDS=600

source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/vpn_status.sh"
source <(sed -n '/^supervise_vpn() {/,/^}/p' "${PROJECT_DIR}/scripts/docker-entrypoint.sh")

check_adguard_vpn_status() { return 1; }

supervise_vpn &
SV_PID=\$!
# The stub sleep returns instantly, so 120 ticks finish in milliseconds.
# Give the loop a generous 2-second ceiling so scheduler jitter cannot
# truncate the recorded log.
/bin/sleep 2
kill "\${SV_PID}" 2>/dev/null || true
wait "\${SV_PID}" 2>/dev/null || true

# Count and sum the recorded sleep durations.
awk 'BEGIN{s=0;n=0;cap_violation=0} {s+=\$1; n++; if (\$1 != 5) cap_violation++} END{printf "count=%d sum=%d cap_violation=%d\n", n, s, cap_violation}' "${test_dir}/sleep.log"
RUNNER
    chmod +x "$runner"
    local actual
    actual=$(bash "$runner" 2>&1 | grep -E '^count=' || echo "count=0 sum=0 cap_violation=0")
    local count sum cap_violation
    count=$(echo "$actual" | sed -n 's/^count=\([0-9]*\).*/\1/p')
    sum=$(echo "$actual" | sed -n 's/.*sum=\([0-9]*\).*/\1/p')
    cap_violation=$(echo "$actual" | sed -n 's/.*cap_violation=\([0-9]*\)$/\1/p')
    # Exact assertion.  A regression that drops a tick, exceeds 5, or
    # fails to reach the full grace must fail this test.
    if [ "${count}" -eq 120 ] && [ "${sum}" -eq 600 ] && [ "${cap_violation}" -eq 0 ]; then
        echo "  PASS: grace=600 exactly 120 ticks of 5s each (sum=600 cap_violation=0)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: grace=600 expected count=120 sum=600 cap_violation=0, got ${actual}"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$test_dir"
}

# =============================================================================
# Entrypoint test seam + ordering tests (E)
#
# Source the entrypoint's _persistent_identity_apply_main helper and the
# surrounding top-level gate, then verify ordering, fail-closed rc=78, and
# success rc=0 with init marker behavior.
# =============================================================================

test_entrypoint_ordering_invariant() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    # Resolve the line numbers of each anchor in the actual file.
    # The anchors mark TOP-LEVEL CALLS and SECTION STARTS, not function
    # definitions, so a regression that moves a definition without moving
    # its call site is caught.
    #
    # Order required: ensure_data_dir < _persistent_identity_apply_main
    # < TUN permission setup < pre-VPN IP detection < init.sh
    #
    # This invariant is the fail-closed contract: when
    # persistent_identity_apply fails, none of the network side effects
    # (TUN chmod, IP probe, init.sh, OAuth, connect) may run.
    # The pattern strings contain $-signs that must NOT be expanded by
    # grep, so they live in single-quoted variables (intentional SC2016
    # suppression).
    # shellcheck disable=SC2016
    local anchor_data_dir='ensure_data_dir "$DATA_DIR"'
    # shellcheck disable=SC2016
    local anchor_apply='_persistent_identity_apply_main || identity_rc=$?'
    # shellcheck disable=SC2016
    local anchor_tun='if [ -c /dev/net/tun ]; then'
    # shellcheck disable=SC2016
    local anchor_ip='# Pre-VPN IP detection (for kill switch)'
    # shellcheck disable=SC2016
    local anchor_init='if /opt/adguardvpn_cli/scripts/init.sh'
    local line_data_dir line_apply line_tun line_ip line_init
    line_data_dir=$(grep -nF "$anchor_data_dir" "$entrypoint" | head -1 | cut -d: -f1)
    line_apply=$(grep -nF "$anchor_apply" "$entrypoint" | head -1 | cut -d: -f1)
    line_tun=$(grep -nF "$anchor_tun" "$entrypoint" | head -1 | cut -d: -f1)
    line_ip=$(grep -nF "$anchor_ip" "$entrypoint" | head -1 | cut -d: -f1)
    line_init=$(grep -nF "$anchor_init" "$entrypoint" | head -1 | cut -d: -f1)

    if [ -z "$line_data_dir" ] || [ -z "$line_apply" ] || [ -z "$line_tun" ] || [ -z "$line_ip" ] || [ -z "$line_init" ]; then
        echo "  FAIL: could not locate 5 anchors (data_dir=${line_data_dir} apply=${line_apply} tun=${line_tun} ip=${line_ip} init=${line_init})"
        FAIL=$((FAIL + 1))
        return
    fi

    if [ "$line_data_dir" -lt "$line_apply" ] && \
       [ "$line_apply" -lt "$line_tun" ] && \
       [ "$line_tun" -lt "$line_ip" ] && \
       [ "$line_ip" -lt "$line_init" ]; then
        echo "  PASS: 5-anchor ordering data_dir(${line_data_dir}) < apply(${line_apply}) < tun(${line_tun}) < ip_detect(${line_ip}) < init.sh(${line_init})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ordering broken: data_dir=${line_data_dir} apply=${line_apply} tun=${line_tun} ip=${line_ip} init=${line_init}"
        FAIL=$((FAIL + 1))
    fi
}

test_helper_failure_exits_78_without_init_marker() {
    local test_dir
    test_dir=$(mktemp -d)
    local marker="${test_dir}/init_marker"
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"
    # Source the production helper by name and the top-level gate plus the
    # /dev/net/tun permission block via sed range.  The gate+TUN extraction
    # starts at the `identity_rc=0` line and ends at (but does not
    # include) the `LOG_FILE=...` assignment, so the post-fail path is
    # the only exit.
    local helper_range='172,178p'
    local runner="${test_dir}/run_fail.sh"
    # Pre-process a copy of the entrypoint: replace the `[ -c /dev/net/tun ]`
    # check with `[ -e / ]` (always true on any POSIX system) so the TUN
    # block exercises the chmod path on a host without /dev/net/tun.  The
    # replacement is a test-only concern; production is unchanged.
    # Test-only copy: swap the /dev/net/tun character-device check for an
    # always-true predicate so the TUN block exercises its chmod path on
    # hosts without the device; production stays unchanged.
    sed 's|\[ -c /dev/net/tun \]|[ -e / ]|' "$entrypoint" > "${test_dir}/entrypoint_copy.sh"
    cat > "$runner" << RUNNER
#!/bin/bash
set -uo pipefail
# Stub persistent_identity_apply so the gate exits with rc=78.
persistent_identity_apply() { return 1; }
# log_force and the lib log functions are no-op stubs so the runner
# does not need the production logging.sh.
log_force() { :; }
log() { :; }
# chmod stub records invocations so the test can prove the TUN block
# was not reached on identity failure.
chmod() {
    printf '%s\n' "\$*" >> "\${TEST_DIR}/_chmod_calls.log"
    return 0
}
# Source the production helper verbatim from the entrypoint copy.
sed -n '${helper_range}' "\${TEST_DIR}/entrypoint_copy.sh" > "\${TEST_DIR}/_helper.sh"
# Source the production gate + TUN permission block.  This block ends
# just before LOG_FILE= so any post-gate code (IP probe, init.sh) is
# not sourced.  The TUN chmod must be reached only when the gate passes.
sed -n '/^identity_rc=0$/,/^LOG_FILE=/p' "\${TEST_DIR}/entrypoint_copy.sh" | sed '/^LOG_FILE=/d' > "\${TEST_DIR}/_gate_and_tun.sh"
# shellcheck disable=SC1091
source "\${TEST_DIR}/_helper.sh"
# shellcheck disable=SC1091
source "\${TEST_DIR}/_gate_and_tun.sh"

# This line must NOT execute when apply fails.
touch "\${TEST_DIR}/init_marker"
RUNNER
    chmod +x "$runner"
    local rc
    rc=0
    if env TEST_DIR="$test_dir" bash "$runner" >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 78 ] && [ ! -e "$marker" ] && [ ! -s "$test_dir/_chmod_calls.log" ]; then
        echo "  PASS: helper failure exits 78, skips init marker, and skips TUN chmod (production gate+TUN sourced)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: helper failure rc=${rc} marker_present=$([ -e "$marker" ] && echo yes || echo no) chmod_calls=$([ -s "$test_dir/_chmod_calls.log" ] && cat "$test_dir/_chmod_calls.log" || echo none)"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$test_dir"
}

test_helper_success_returns_zero_and_reaches_init_marker() {
    local test_dir
    test_dir=$(mktemp -d)
    local marker="${test_dir}/init_marker"
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"
    local helper_range='172,178p'
    local runner="${test_dir}/run_ok.sh"
    # Test-only copy: swap the /dev/net/tun character-device check for an
    # always-true predicate so the TUN block exercises its chmod path on
    # hosts without the device; production stays unchanged.
    sed 's|\[ -c /dev/net/tun \]|[ -e / ]|' "$entrypoint" > "${test_dir}/entrypoint_copy.sh"
    cat > "$runner" << RUNNER
#!/bin/bash
set -uo pipefail
# Mock apply succeeds.
persistent_identity_apply() { return 0; }
log_force() { :; }
log() { :; }
chmod() {
    printf '%s\n' "\$*" >> "\${TEST_DIR}/_chmod_calls.log"
    return 0
}
sed -n '${helper_range}' "\${TEST_DIR}/entrypoint_copy.sh" > "\${TEST_DIR}/_helper.sh"
sed -n '/^identity_rc=0$/,/^LOG_FILE=/p' "\${TEST_DIR}/entrypoint_copy.sh" | sed '/^LOG_FILE=/d' > "\${TEST_DIR}/_gate_and_tun.sh"
# shellcheck disable=SC1091
source "\${TEST_DIR}/_helper.sh"
# shellcheck disable=SC1091
source "\${TEST_DIR}/_gate_and_tun.sh"

# This line must execute when apply succeeds and the TUN block runs.
touch "\${TEST_DIR}/init_marker"
RUNNER
    chmod +x "$runner"
    local rc
    rc=0
    if env TEST_DIR="$test_dir" bash "$runner" >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 0 ] && [ -e "$marker" ] && [ -s "$test_dir/_chmod_calls.log" ]; then
        echo "  PASS: helper success rc=0, reaches init marker, and runs TUN chmod (production gate+TUN sourced)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: helper success rc=${rc} marker_present=$([ -e "$marker" ] && echo yes || echo no) chmod_calls=$([ -s "$test_dir/_chmod_calls.log" ] && cat "$test_dir/_chmod_calls.log" || echo none)"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$test_dir"
}

test_grace_0_emits_no_sleeps
echo ""
test_grace_1_emits_one_sleep_of_one_second
echo ""
test_grace_6_emits_sleeps_five_then_one
echo ""
test_grace_30_emits_six_five_second_sleeps
echo ""
test_grace_600_emits_one_twenty_five_second_sleeps
echo ""
test_entrypoint_ordering_invariant
echo ""
test_helper_failure_exits_78_without_init_marker
echo ""
test_helper_success_returns_zero_and_reaches_init_marker
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
