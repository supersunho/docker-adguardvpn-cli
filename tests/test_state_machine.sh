#!/bin/bash
#
# Unit tests for killswitch_state.sh — state machine transitions.
#
# These tests validate the pure-logic state machine without requiring
# root, Docker, or a VPN connection.  They run locally with shunit2.
#
# Usage:
#   bash tests/test_state_machine.sh
#
# Dependencies: shunit2 (pulled automatically if not found)

set -euo pipefail

# --- Test setup --------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source the state machine module directly (no need for the full utils.sh)
# We need the logging module first since killswitch_state uses log().
export HOME="${HOME:-/tmp}"
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/killswitch_state.sh"

# Redirect log output away from test output
ADGUARD_LOG_LEVEL="${ADGUARD_LOG_LEVEL:-ERROR}"

# --- Test cases --------------------------------------------------------------

test_initial_state_is_standby() {
    ks_reset
    assertEquals "Initial state should be STANDBY" \
        "$KS_STANDBY" "$_KS_CURRENT_STATE"
    assertEquals "State name should be STANDBY" \
        "STANDBY" "$(ks_get_state_name)"
}

test_standby_to_protected_transition() {
    ks_reset
    ks_set_state $KS_PROTECTED
    assertEquals "Should transition to PROTECTED" \
        "$KS_PROTECTED" "$_KS_CURRENT_STATE"
    assertEquals "State name should be PROTECTED" \
        "PROTECTED" "$(ks_get_state_name)"
    assertTrue "ks_is_protected should return true" ks_is_protected
}

test_protected_to_leak_warning_transition() {
    ks_reset
    ks_set_state $KS_PROTECTED
    ks_set_state $KS_LEAK_WARNING
    assertEquals "Should transition to LEAK_WARNING" \
        "$KS_LEAK_WARNING" "$_KS_CURRENT_STATE"
}

test_leak_warning_to_protected_recovery() {
    ks_reset
    ks_set_state $KS_PROTECTED
    ks_set_state $KS_LEAK_WARNING
    ks_set_state $KS_PROTECTED
    assertEquals "Should recover to PROTECTED" \
        "$KS_PROTECTED" "$_KS_CURRENT_STATE"
}

test_direct_to_terminating() {
    ks_reset
    ks_set_state $KS_TERMINATING
    assertEquals "Should transition to TERMINATING from any state" \
        "$KS_TERMINATING" "$_KS_CURRENT_STATE"
    assertTrue "ks_is_terminating should return true" ks_is_terminating
}

test_leak_warning_to_terminating() {
    ks_reset
    ks_set_state $KS_PROTECTED
    ks_set_state $KS_LEAK_WARNING
    ks_set_state $KS_TERMINATING
    assertEquals "Should transition LEAK_WARNING -> TERMINATING" \
        "$KS_TERMINATING" "$_KS_CURRENT_STATE"
}

test_has_been_protected_tracking() {
    ks_reset
    assertFalse "Should not be protected yet" \
        $_KS_HAS_BEEN_PROTECTED
    ks_set_state $KS_PROTECTED
    assertTrue "Should track that we were protected" \
        "$_KS_HAS_BEEN_PROTECTED"
    ks_set_state $KS_LEAK_WARNING
    assertTrue "Should still track that we were protected" \
        "$_KS_HAS_BEEN_PROTECTED"
}

test_setting_same_state_is_noop() {
    ks_reset
    ks_set_state $KS_STANDBY  # same state
    assertEquals "STANDBY should remain STANDBY" \
        "$KS_STANDBY" "$_KS_CURRENT_STATE"
}

test_valid_transitions() {
    # Valid transitions
    ks_is_valid_transition $KS_STANDBY $KS_PROTECTED
    assertTrue "STANDBY -> PROTECTED should be valid" $?

    ks_is_valid_transition $KS_PROTECTED $KS_LEAK_WARNING
    assertTrue "PROTECTED -> LEAK_WARNING should be valid" $?

    ks_is_valid_transition $KS_PROTECTED $KS_TERMINATING
    assertTrue "PROTECTED -> TERMINATING should be valid" $?

    ks_is_valid_transition $KS_LEAK_WARNING $KS_PROTECTED
    assertTrue "LEAK_WARNING -> PROTECTED should be valid" $?

    ks_is_valid_transition $KS_LEAK_WARNING $KS_TERMINATING
    assertTrue "LEAK_WARNING -> TERMINATING should be valid" $?
}

test_invalid_transitions() {
    # STANDBY cannot skip to LEAK_WARNING
    ks_is_valid_transition $KS_STANDBY $KS_LEAK_WARNING
    assertFalse "STANDBY -> LEAK_WARNING should be invalid" $?

    # PROTECTED cannot go back to STANDBY
    ks_is_valid_transition $KS_PROTECTED $KS_STANDBY
    assertFalse "PROTECTED -> STANDBY should be invalid" $?

    # LEAK_WARNING cannot go to STANDBY
    ks_is_valid_transition $KS_LEAK_WARNING $KS_STANDBY
    assertFalse "LEAK_WARNING -> STANDBY should be invalid" $?
}

# --- shunit2 bootstrap -------------------------------------------------------

# Download shunit2 if not present
SHUNIT2="${SCRIPT_DIR}/lib/shunit2"
if [ ! -f "$SHUNIT2" ]; then
    echo "Downloading shunit2..."
    mkdir -p "${SCRIPT_DIR}/lib"
    curl -fsSL -o "$SHUNIT2" \
        "https://raw.githubusercontent.com/kward/shunit2/master/shunit2"
    chmod +x "$SHUNIT2"
fi

# shellcheck source=/dev/null
source "$SHUNIT2"
