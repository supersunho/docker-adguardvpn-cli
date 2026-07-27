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

SHUNIT2="${SCRIPT_DIR}/lib/shunit2"
if [ ! -f "$SHUNIT2" ]; then
    mkdir -p "${SCRIPT_DIR}/lib"
    curl -fsSL -o "$SHUNIT2" \
        "https://raw.githubusercontent.com/kward/shunit2/master/shunit2"
    chmod +x "$SHUNIT2"
fi
# shellcheck source=/dev/null
source "$SHUNIT2"
