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

# =============================================================================
# Persistent identity preservation during auth reset (option C)
# =============================================================================

test_persistent_identity_preserved_on_optin_reset() {
    local test_dir
    test_dir=$(mktemp -d)
    local data_dir="${test_dir}/data"
    mkdir -p "${data_dir}/identity"
    printf '%s\n' '02:34:56:78:9a:bc' > "${data_dir}/identity/mac"
    chmod 600 "${data_dir}/identity/mac"
    chmod 700 "${data_dir}/identity"
    printf '%s\n' 'session' > "${data_dir}/session.json"

    DATA_DIR="$data_dir" \
    ADGUARD_SHOW_LOG=false \
    ADGUARD_PERSISTENT_IDENTITY=true \
    bash -c "
        source '${PROJECT_DIR}/scripts/lib/logging.sh'
        # shellcheck disable=SC1090
        source <(sed -n '/^_reset_auth_data() {/,/^}/p' '${PROJECT_DIR}/scripts/init.sh')
        _reset_auth_data
    "
    local rc=$?

    if [ "$rc" -ne 0 ]; then
        echo "  FAIL: opt-in reset returned non-zero ($rc)"
        FAIL=$((FAIL + 1))
        rm -rf "$test_dir"
        return
    fi

    if [ -f "${data_dir}/identity/mac" ] && \
       [ "$(cat "${data_dir}/identity/mac")" = "02:34:56:78:9a:bc" ] && \
       [ ! -e "${data_dir}/session.json" ]; then
        echo "  PASS: opt-in reset preserves identity/mac and removes session"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: opt-in reset did not preserve identity or removed it incorrectly"
        echo "    identity/mac present: $([ -f "${data_dir}/identity/mac" ] && echo yes || echo no)"
        echo "    identity/mac content: $(cat "${data_dir}/identity/mac" 2>/dev/null || echo missing)"
        echo "    session.json present: $([ -e "${data_dir}/session.json" ] && echo yes || echo no)"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$test_dir"
    unset DATA_DIR ADGUARD_PERSISTENT_IDENTITY
}

test_persistent_identity_removed_on_optout_reset() {
    local test_dir
    test_dir=$(mktemp -d)
    local data_dir="${test_dir}/data"
    mkdir -p "${data_dir}/identity"
    printf '%s\n' '02:34:56:78:9a:bc' > "${data_dir}/identity/mac"
    chmod 600 "${data_dir}/identity/mac"
    chmod 700 "${data_dir}/identity"

    DATA_DIR="$data_dir" \
    ADGUARD_SHOW_LOG=false \
    ADGUARD_PERSISTENT_IDENTITY=false \
    bash -c "
        source '${PROJECT_DIR}/scripts/lib/logging.sh'
        # shellcheck disable=SC1090
        source <(sed -n '/^_reset_auth_data() {/,/^}/p' '${PROJECT_DIR}/scripts/init.sh')
        _reset_auth_data
    "
    local rc=$?

    if [ "$rc" -ne 0 ]; then
        echo "  FAIL: opt-out reset returned non-zero ($rc)"
        FAIL=$((FAIL + 1))
        rm -rf "$test_dir"
        return
    fi

    if [ ! -e "${data_dir}/identity" ] && [ ! -e "${data_dir}/identity/mac" ]; then
        echo "  PASS: opt-out reset removes identity subtree (legacy behavior)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: opt-out reset kept identity subtree (expected removal)"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$test_dir"
    unset DATA_DIR ADGUARD_PERSISTENT_IDENTITY
}

test_init_references_persistent_identity_in_reset_log() {
    # The opt-in branch must log the explicit "preserved" message so operators
    # do not mistakenly assume the MAC was rotated.
    if grep -q 'persistent identity preserved' "${PROJECT_DIR}/scripts/init.sh"; then
        echo "  PASS: init.sh _reset_auth_data logs the preserved-identity message"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: init.sh _reset_auth_data missing preserved-identity log line"
        FAIL=$((FAIL + 1))
    fi
}

echo "=========================================="
echo " Authentication Recovery Tests"
echo "=========================================="
echo ""

test_auth_failures_reset_data_on_threshold
test_auth_detection_does_not_use_runtime_pid_file
test_init_does_not_clear_socks_auth_before_configuration
test_persistent_identity_preserved_on_optin_reset
test_persistent_identity_removed_on_optout_reset
test_init_references_persistent_identity_in_reset_log

echo ""
echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
