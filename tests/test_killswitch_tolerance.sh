#!/bin/bash
set -euo pipefail

# Test: Kill-switch tolerance semantics
#
# Proves the leak-tolerance policy contract:
#   tolerance=0, first leak       => terminate
#   tolerance=1, first leak       => LEAK_WARNING, count=1
#   tolerance=1, second leak      => terminate
#   recovery resets count          => PROTECTED, count=0
#   warning-only mode              => no terminate
#
# Usage:  bash tests/test_killswitch_tolerance.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export HOME="${HOME:-/tmp}"

# Source modules in dependency order
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/killswitch_state.sh"

# Redirect log output away from test output
ADGUARD_LOG_LEVEL="${ADGUARD_LOG_LEVEL:-ERROR}"

# =============================================================================
# Test cases
# =============================================================================

# Test: tolerance=0, first leak => terminate (ks_record_leak returns non-zero)
test_zero_tolerance_first_leak_terminates() {
    ks_reset

    # Simulate being in PROTECTED state
    ks_set_state $KS_PROTECTED

    # First leak with tolerance=0
    ks_record_leak 0 false
    local rc=$?

    # Must return non-zero (terminate)
    assertTrue "Zero tolerance, first leak should return non-zero" \
        "[ $rc -ne 0 ]"

    # Leak count should be 1
    assertEquals "Leak count should be 1" 1 "$_KS_LEAK_COUNT"
}

# Test: tolerance=1, first leak => warning (ks_record_leak returns 0)
test_tolerance_one_first_leak_warns() {
    ks_reset
    ks_set_state $KS_PROTECTED

    # First leak with tolerance=1
    ks_record_leak 1 false
    local rc=$?

    # Must return 0 (continue monitoring)
    assertEquals "Tolerance=1, first leak should return 0" 0 $rc

    # Leak count should be 1
    assertEquals "Leak count should be 1" 1 "$_KS_LEAK_COUNT"
}

# Test: tolerance=1, second leak => terminate
test_tolerance_one_second_leak_terminates() {
    ks_reset
    ks_set_state $KS_PROTECTED

    # First leak — within tolerance
    ks_record_leak 1 false
    assertEquals "First leak should return 0" 0 $?

    # Second leak — exceeds tolerance
    ks_record_leak 1 false
    local rc=$?

    assertTrue "Second leak should return non-zero" \
        "[ $rc -ne 0 ]"
    assertEquals "Leak count should be 2" 2 "$_KS_LEAK_COUNT"
}

# Test: tolerance=1, recovery resets count
test_recovery_resets_leak_count() {
    ks_reset
    ks_set_state $KS_PROTECTED

    # First leak
    ks_record_leak 1 false
    assertEquals "Leak count after first leak" 1 "$_KS_LEAK_COUNT"

    # Recovery — simulate non-leak path calling ks_clear_leak_count
    ks_clear_leak_count
    assertEquals "Leak count after recovery" 0 "$_KS_LEAK_COUNT"
}

# Test: warning-only mode never terminates regardless of count
test_warning_only_never_terminates() {
    ks_reset
    ks_set_state $KS_PROTECTED

    # Multiple leaks with warning_only=true — all should return 0
    ks_record_leak 0 true
    assertEquals "Warning-only, leak 1 should return 0" 0 $?

    ks_record_leak 0 true
    assertEquals "Warning-only, leak 2 should return 0" 0 $?

    ks_record_leak 5 true
    assertEquals "Warning-only, leak 3 should return 0" 0 $?

    # Count should keep incrementing
    assertEquals "Leak count should be 3" 3 "$_KS_LEAK_COUNT"
}

# Test: ks_set_state rejects invalid transitions
test_set_state_rejects_invalid_transition() {
    ks_reset

    # STANDBY -> LEAK_WARNING is invalid (should skip PROTECTED)
    ks_set_state $KS_LEAK_WARNING
    local rc=$?

    assertTrue "STANDBY -> LEAK_WARNING should be rejected" \
        "[ $rc -ne 0 ]"

    # State should still be STANDBY
    assertEquals "State should remain STANDBY" \
        "$KS_STANDBY" "$_KS_CURRENT_STATE"
}

# Test: ks_set_state accepts valid transitions
test_set_state_accepts_valid_transition() {
    ks_reset

    # STANDBY -> PROTECTED is valid
    ks_set_state $KS_PROTECTED
    assertEquals "STANDBY -> PROTECTED should succeed" 0 $?
    assertEquals "State should be PROTECTED" \
        "$KS_PROTECTED" "$_KS_CURRENT_STATE"

    # PROTECTED -> LEAK_WARNING is valid
    ks_set_state $KS_LEAK_WARNING
    assertEquals "PROTECTED -> LEAK_WARNING should succeed" 0 $?
    assertEquals "State should be LEAK_WARNING" \
        "$KS_LEAK_WARNING" "$_KS_CURRENT_STATE"
}

# =============================================================================
# shunit2 bootstrap
# =============================================================================

SHUNIT2="${SCRIPT_DIR}/lib/shunit2"
if [ ! -f "$SHUNIT2" ]; then
    mkdir -p "${SCRIPT_DIR}/lib"
    curl -fsSL -o "$SHUNIT2" \
        "https://raw.githubusercontent.com/kward/shunit2/master/shunit2"
    chmod +x "$SHUNIT2"
fi
# shellcheck source=/dev/null
source "$SHUNIT2"
