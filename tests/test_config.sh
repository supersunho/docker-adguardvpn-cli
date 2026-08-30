#!/bin/bash
set -euo pipefail

# Test: Configuration initialization safety
#
# Proves that config_export_defaults initializes all ADGUARD_*
# variables before strict-mode code paths read them.
#
# Usage:  bash tests/test_config.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export HOME="${HOME:-/tmp}"

source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/error_handling.sh"
source "${PROJECT_DIR}/scripts/lib/config.sh"

test_unset_logging_variables_are_initialized() {
    unset ADGUARD_SHOW_LOG ADGUARD_SHOW_SUMMARY ADGUARD_SHOW_LOG_LEVEL

    config_export_defaults

    assertEquals "ADGUARD_SHOW_LOG default should be true" \
        "true" "${ADGUARD_SHOW_LOG}"
    assertEquals "ADGUARD_SHOW_SUMMARY default should be true" \
        "true" "${ADGUARD_SHOW_SUMMARY}"
    assertEquals "ADGUARD_SHOW_LOG_LEVEL default should be INFO" \
        "INFO" "${ADGUARD_SHOW_LOG_LEVEL}"
}

test_config_bootstrap_completes() {
    unset ADGUARD_SHOW_LOG ADGUARD_SHOW_SUMMARY ADGUARD_SHOW_LOG_LEVEL
    unset ADGUARD_CONNECTION_LOCATION ADGUARD_CONNECTION_TYPE
    unset ADGUARD_MAX_LEAK_TOLERANCE ADGUARD_LEAK_WARNING_ONLY

    config_export_defaults

    assertEquals "ADGUARD_CONNECTION_LOCATION default" \
        "JP" "${ADGUARD_CONNECTION_LOCATION}"
    assertEquals "ADGUARD_MAX_LEAK_TOLERANCE default" \
        "0" "${ADGUARD_MAX_LEAK_TOLERANCE}"
    assertEquals "ADGUARD_LEAK_WARNING_ONLY default" \
        "false" "${ADGUARD_LEAK_WARNING_ONLY}"
    assertEquals "ADGUARD_AUTH_TIMEOUT default" \
        "900" "${ADGUARD_AUTH_TIMEOUT}"
    assertEquals "kill switch check interval default" \
        "8" "${ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL}"
}

test_auth_timeout_requires_positive_integer() {
    export ADGUARD_AUTH_TIMEOUT=0
    if config_validate; then
        assertTrue "ADGUARD_AUTH_TIMEOUT=0 must fail validation" false
    else
        assertTrue "ADGUARD_AUTH_TIMEOUT=0 must fail validation" true
    fi
    unset ADGUARD_AUTH_TIMEOUT
}

test_lowercase_expansion_does_not_crash() {
    unset ADGUARD_SHOW_LOG ADGUARD_SHOW_LOG_LEVEL

    local show_log="${ADGUARD_SHOW_LOG:-true}"
    local log_level="${ADGUARD_SHOW_LOG_LEVEL:-INFO}"

    if [ "${show_log,,}" = "true" ]; then
        : # ok
    fi

    assertEquals "show_log lowercased" "true" "${show_log,,}"
}

test_normalize_canonicalizes_values() {
    export ADGUARD_SHOW_LOG="TRUE"
    export ADGUARD_SHOW_SUMMARY="false"
    export ADGUARD_SHOW_LOG_LEVEL="debug"
    export ADGUARD_CONNECTION_TYPE="socks"
    export ADGUARD_MAX_LEAK_TOLERANCE="0"

    config_normalize

    assertEquals "SHOW_LOG normalized to lowercase" \
        "true" "${ADGUARD_SHOW_LOG}"
    assertEquals "SHOW_SUMMARY normalized to lowercase" \
        "false" "${ADGUARD_SHOW_SUMMARY}"
    assertEquals "LOG_LEVEL canonicalized to schema case" \
        "DEBUG" "${ADGUARD_SHOW_LOG_LEVEL}"
    assertEquals "CONNECTION_TYPE canonicalized to schema case" \
        "SOCKS" "${ADGUARD_CONNECTION_TYPE}"
}

# =============================================================================
# Persistent identity (opt-in) — config-level defaults and validation
# =============================================================================

test_persistent_identity_default_is_false() {
    unset ADGUARD_PERSISTENT_IDENTITY

    config_export_defaults

    assertEquals "ADGUARD_PERSISTENT_IDENTITY default should be false" \
        "false" "${ADGUARD_PERSISTENT_IDENTITY}"
}

test_persistent_identity_normalize_case_insensitive() {
    export ADGUARD_PERSISTENT_IDENTITY="True"
    config_normalize
    assertEquals "True normalizes to true" \
        "true" "${ADGUARD_PERSISTENT_IDENTITY}"

    export ADGUARD_PERSISTENT_IDENTITY="FALSE"
    config_normalize
    assertEquals "FALSE normalizes to false" \
        "false" "${ADGUARD_PERSISTENT_IDENTITY}"
}

test_persistent_identity_invalid_value_rejected() {
    export ADGUARD_PERSISTENT_IDENTITY="yes"
    if config_validate; then
        assertTrue "ADGUARD_PERSISTENT_IDENTITY=yes must fail validation" false
    else
        assertTrue "ADGUARD_PERSISTENT_IDENTITY=yes rejected" true
    fi
    unset ADGUARD_PERSISTENT_IDENTITY
}

# =============================================================================
# ADGUARD_VPN_STARTUP_GRACE_SECONDS — bounded_int validation
# =============================================================================

test_startup_grace_default_is_30() {
    unset ADGUARD_VPN_STARTUP_GRACE_SECONDS
    config_export_defaults
    assertEquals "grace default should be 30" \
        "30" "${ADGUARD_VPN_STARTUP_GRACE_SECONDS}"
}

test_startup_grace_boundaries_accepted() {
    export ADGUARD_VPN_STARTUP_GRACE_SECONDS=0
    if config_validate; then
        assertTrue "0 should be valid" true
    else
        assertTrue "0 should be valid" false
    fi

    export ADGUARD_VPN_STARTUP_GRACE_SECONDS=600
    if config_validate; then
        assertTrue "600 should be valid" true
    else
        assertTrue "600 should be valid" false
    fi

    unset ADGUARD_VPN_STARTUP_GRACE_SECONDS
}

test_startup_grace_rejects_out_of_range() {
    export ADGUARD_VPN_STARTUP_GRACE_SECONDS=-1
    if config_validate; then
        assertTrue "-1 must fail" false
    else
        assertTrue "-1 rejected" true
    fi

    export ADGUARD_VPN_STARTUP_GRACE_SECONDS=601
    if config_validate; then
        assertTrue "601 must fail" false
    else
        assertTrue "601 rejected" true
    fi

    export ADGUARD_VPN_STARTUP_GRACE_SECONDS=abc
    if config_validate; then
        assertTrue "non-integer must fail" false
    else
        assertTrue "non-integer rejected" true
    fi

    export ADGUARD_VPN_STARTUP_GRACE_SECONDS="3.14"
    if config_validate; then
        assertTrue "fractional must fail" false
    else
        assertTrue "fractional rejected" true
    fi

    unset ADGUARD_VPN_STARTUP_GRACE_SECONDS
}

# =============================================================================
# Optional keys: config_export_defaults / config_normalize / config_validate
# must leave an unset optional variable genuinely unset, and a non-empty
# value must be validated and exported normally. This is the regression that
# keeps ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL able to inherit
# ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL through process boundaries.
# =============================================================================

test_optional_key_stays_unset_after_export_defaults() {
    unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
    config_export_defaults

    # The variable must be empty (not "8") so a child process can detect
    # the unset state and apply the global fallback.
    if [ -z "${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL+x}" ]; then
        assertTrue "ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL must stay unset" true
    else
        assertTrue "leaked default value: '${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL}'" false
    fi
}

test_optional_key_stays_unset_after_normalize() {
    unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
    config_normalize

    if [ -z "${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL+x}" ]; then
        assertTrue "normalize must not export an unset optional key" true
    else
        assertTrue "normalize leaked: '${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL}'" false
    fi
}

test_optional_key_validates_when_empty() {
    unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
    if config_validate; then
        assertTrue "empty optional key must pass validation" true
    else
        assertTrue "empty optional key must NOT fail validation" false
    fi
}

test_optional_key_validates_when_set() {
    export ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL=15
    if config_validate; then
        assertTrue "non-empty optional key with valid value must pass" true
    else
        assertTrue "valid value 15 was rejected" false
    fi
    unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
}

test_optional_key_rejects_invalid_value() {
    export ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL=abc
    if config_validate; then
        assertTrue "invalid value must fail" false
    else
        assertTrue "invalid value rejected" true
    fi
    unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
}

# Parent -> child inheritance simulation: this is the production failure
# mode the review caught. With global=30, ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
# unset, and config_bootstrap run, a child process must see the variable
# as unset so the kill switch detector applies its global fallback.
test_optional_key_survives_parent_child_boundary() {
    # Simulate the PID-1 -> kill switch child boundary.
    # Parent runs config_bootstrap (as docker-entrypoint does); the child
    # inherits the parent's environment and sources killswitch_detector.sh.
    local child_effective_interval
    child_effective_interval=$( \
        ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL=30 \
        bash -c '
            set +u
            export HOME="${HOME:-/tmp}"
            unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
            # Parent step: run the same bootstrap the entrypoint runs.
            source "'"${PROJECT_DIR}"'/scripts/lib/logging.sh" 2>/dev/null
            source "'"${PROJECT_DIR}"'/scripts/lib/error_handling.sh" 2>/dev/null
            source "'"${PROJECT_DIR}"'/scripts/lib/config.sh" 2>/dev/null
            config_export_defaults >/dev/null 2>&1
            config_normalize >/dev/null 2>&1
            # Confirm the parent did not leak a default.
            if [ -n "${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL+x}" ]; then
                printf "LEAKED_%s" "${ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL}"
                exit 0
            fi
            # Child step: source the detector under the inherited env and
            # read the resolved SOCKS interval. It should fall back to 30.
            source "'"${PROJECT_DIR}"'/scripts/lib/network.sh" 2>/dev/null
            source "'"${PROJECT_DIR}"'/scripts/lib/vpn_status.sh" 2>/dev/null
            source "'"${PROJECT_DIR}"'/scripts/lib/killswitch_detector.sh" 2>/dev/null
            printf "%s" "${KS_SOCKS_CHECK_INTERVAL}"
        ')

    assertEquals "child must resolve SOCKS interval from global (30)" \
        "30" "$child_effective_interval"
    unset ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL
    unset ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL
}

SHUNIT2="${SCRIPT_DIR}/lib/shunit2"
if [ ! -f "$SHUNIT2" ]; then
    mkdir -p "${SCRIPT_DIR}/lib"
    curl -fsSL -o "$SHUNIT2" \
        "https://raw.githubusercontent.com/kward/shunit2/master/shunit2"
    chmod +x "$SHUNIT2"
fi
# shellcheck source=/dev/null
source "$SHUNIT2"
