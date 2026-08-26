#!/bin/bash
set -euo pipefail

# The production module is sourced when present; ip/od boundaries below are
# shell-function stubs so every call remains local and observable.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
export HOME="${HOME:-/tmp}"

source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/error_handling.sh"
source "${PROJECT_DIR}/scripts/lib/config.sh"

# Keep the red phase useful before the production module exists.
if [ -f "${PROJECT_DIR}/scripts/lib/persistent_identity.sh" ]; then
    # shellcheck source=/dev/null
    source "${PROJECT_DIR}/scripts/lib/persistent_identity.sh"
else
    persistent_identity_apply() { return 127; }
    persistent_identity_validate_mac() { return 127; }
    persistent_identity_mac_file() { printf '%s\n' "${DATA_DIR}/identity/mac"; }
    persistent_identity_primary_interface() { return 127; }
fi

STUB_ROOT=""
STUB_IP_LOG=""
STUB_ROUTE_OUTPUT=""
STUB_CURRENT_MAC="02:42:ac:14:00:02"
STUB_EFFECTIVE_MAC="02:42:ac:14:00:02"
STUB_IP_SET_RC=0
STUB_MISMATCH=false
STUB_REQUIRE_PRIVILEGED_SET=false
STUB_SUDO_ACTIVE=false
STUB_SUDO_USED=false
STUB_RANDOM_OUTPUT="12 34 56 78 9a bc"
ip() {
    printf '%s\n' "$*" >> "$STUB_IP_LOG"

    case "$*" in
        "route show default")
            printf '%s\n' "$STUB_ROUTE_OUTPUT"
            ;;
        "link show dev "*)
            local interface="${4:-}"
            printf '    link/ether %s brd ff:ff:ff:ff:ff:ff\n' "$STUB_EFFECTIVE_MAC"
            ;;
        "link set dev "*)
            local previous=""
            local argument target=""
            for argument in "$@"; do
                if [ "$previous" = "address" ]; then
                    target="$argument"
                    break
                fi
                previous="$argument"
            done
            [ -n "$target" ] || return 2
            if [ "$STUB_REQUIRE_PRIVILEGED_SET" = true ] && \
               [ "$STUB_SUDO_ACTIVE" != true ]; then
                return 1
            fi
            if [ "$STUB_IP_SET_RC" -ne 0 ]; then
                return "$STUB_IP_SET_RC"
            fi
            if [ "$STUB_MISMATCH" = false ] || [ "$target" = "$STUB_CURRENT_MAC" ]; then
                STUB_EFFECTIVE_MAC="$target"
            fi
            ;;
        *)
            return 2
            ;;
    esac
}

sudo() {
    local rc=0
    if [ "${1:-}" = "-n" ]; then
        shift
    fi
    STUB_SUDO_USED=true
    STUB_SUDO_ACTIVE=true
    "$@" || rc=$?
    STUB_SUDO_ACTIVE=false
    return "$rc"
}

od() {
    printf '%s\n' "$STUB_RANDOM_OUTPUT"
}

mode_of() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

setUp() {
    STUB_ROOT="$(mktemp -d)"
    STUB_IP_LOG="${STUB_ROOT}/ip.log"
    : > "$STUB_IP_LOG"
    DATA_DIR="${STUB_ROOT}/data"
    export DATA_DIR
    mkdir -p "$DATA_DIR"
    STUB_ROUTE_OUTPUT='default via 172.20.0.1 dev eth0'
    STUB_CURRENT_MAC='02:42:ac:14:00:02'
    STUB_EFFECTIVE_MAC="$STUB_CURRENT_MAC"
    STUB_IP_SET_RC=0
    STUB_MISMATCH=false
    STUB_REQUIRE_PRIVILEGED_SET=false
    STUB_SUDO_ACTIVE=false
    STUB_SUDO_USED=false
    STUB_RANDOM_OUTPUT='12 34 56 78 9a bc'
    export ADGUARD_PERSISTENT_IDENTITY=false
}

tearDown() {
    rm -rf "$STUB_ROOT"
    unset DATA_DIR ADGUARD_PERSISTENT_IDENTITY
}

test_disabled_mode_does_not_call_ip() {
    persistent_identity_apply
    assertTrue "disabled mode should not call ip" "[ ! -s \"$STUB_IP_LOG\" ]"
    assertTrue "disabled mode should not create identity" "[ ! -e \"$DATA_DIR/identity\" ]"
}

test_mac_validator_requires_unicast() {
    assertTrue "globally administered unicast is valid" \
        "persistent_identity_validate_mac '00:11:22:33:44:56'"
    assertTrue "locally administered unicast is valid" \
        "persistent_identity_validate_mac '02:11:22:33:44:56'"
    assertFalse "multicast MAC is rejected" \
        "persistent_identity_validate_mac '01:11:22:33:44:56'"
    assertFalse "short MAC is rejected" \
        "persistent_identity_validate_mac '02:11:22:33:44'"
}

test_valid_persisted_mac_is_reused_and_verified() {
    mkdir -p "$DATA_DIR/identity"
    printf '%s\n' '00:11:22:33:44:56' > "$DATA_DIR/identity/mac"

    export ADGUARD_PERSISTENT_IDENTITY=true
    persistent_identity_apply

    assertEquals "persisted target applied" \
        '00:11:22:33:44:56' "$STUB_EFFECTIVE_MAC"
    assertTrue "set command targets primary interface" \
        "grep -q 'link set dev eth0 address 00:11:22:33:44:56' '$STUB_IP_LOG'"
}

test_mac_apply_uses_privileged_network_command() {
    mkdir -p "$DATA_DIR/identity"
    printf '%s\n' '02:11:22:33:44:56' > "$DATA_DIR/identity/mac"
    STUB_REQUIRE_PRIVILEGED_SET=true
    export ADGUARD_PERSISTENT_IDENTITY=true

    if persistent_identity_apply; then
        assertTrue "MAC apply uses the privileged network command" \
            "$STUB_SUDO_USED"
    else
        assertTrue "MAC apply must succeed through the privileged path" false
    fi
}

test_invalid_persisted_mac_fails_closed() {
    mkdir -p "$DATA_DIR/identity"
    printf '%s\n' '01:11:22:33:44:56' > "$DATA_DIR/identity/mac"

    export ADGUARD_PERSISTENT_IDENTITY=true
    if persistent_identity_apply; then
        assertTrue "multicast persisted identity must fail" false
    else
        assertTrue "multicast persisted identity rejected" true
    fi
}

test_existing_state_captures_current_mac() {
    mkdir -p "$DATA_DIR/active"
    printf '%s\n' 'authenticated-state' > "$DATA_DIR/active/session"

    export ADGUARD_PERSISTENT_IDENTITY=true
    persistent_identity_apply

    assertEquals "existing state keeps current MAC" \
        "$STUB_CURRENT_MAC" "$(cat "$DATA_DIR/identity/mac")"
}

# Smart-reuse must not call _persistent_identity_generate_mac when existing
# AdGuard state is present.  This proves the opt-in path reuses the
# current interface MAC instead of rotating to a new random one.
test_smart_reuse_skips_generation() {
    mkdir -p "$DATA_DIR/active"
    : > "$DATA_DIR/active/session"

    # Wrap the production generator with a probe that records invocations
    # and forces an error so any accidental call would surface as a
    # test failure (not a silent skip).  Save the original function and
    # restore it after the assertion so subsequent tests see the real
    # implementation.
    local orig_generator
    orig_generator="$(declare -f _persistent_identity_generate_mac)"
    # shellcheck disable=SC2329  # invoked indirectly by persistent_identity_apply
    _persistent_identity_generate_mac() {
        echo "generator-called" > "$DATA_DIR/.generator_was_called"
        return 1
    }

    export ADGUARD_PERSISTENT_IDENTITY=true
    persistent_identity_apply
    local rc=$?

    # Restore the production function before any assertion that might
    # trigger follow-up shunit2 calls (assertFalse on a path that hits
    # the probe again would otherwise re-run the override).
    eval "$orig_generator"

    assertEquals "smart-reuse returns success" 0 "$rc"
    assertEquals "smart-reuse adopts current MAC" \
        "$STUB_CURRENT_MAC" "$(cat "$DATA_DIR/identity/mac")"
    assertFalse "generator must not run when state is present" \
        "[ -e '$DATA_DIR/.generator_was_called' ]"
}

test_existing_global_mac_is_preserved() {
    STUB_CURRENT_MAC='00:11:22:33:44:56'
    STUB_EFFECTIVE_MAC="$STUB_CURRENT_MAC"
    mkdir -p "$DATA_DIR/active"
    printf '%s\n' 'authenticated-state' > "$DATA_DIR/active/session"

    export ADGUARD_PERSISTENT_IDENTITY=true
    persistent_identity_apply

    assertEquals "existing globally administered MAC is preserved" \
        "$STUB_CURRENT_MAC" "$(cat "$DATA_DIR/identity/mac")"
}

test_fresh_state_generates_local_unicast_mac() {
    export ADGUARD_PERSISTENT_IDENTITY=true
    persistent_identity_apply

    local generated
    generated="$(cat "$DATA_DIR/identity/mac")"
    assertEquals "deterministic generated MAC" \
        '12:34:56:78:9a:bc' "$generated"
    assertTrue "generated MAC is locally administered and unicast" \
        "persistent_identity_validate_mac '$generated'"
    assertTrue "generated MAC local bit is set" \
        "(( ((16#${generated:0:2}) & 2) == 2 ))"
}

test_generated_identity_has_restrictive_permissions() {
    export ADGUARD_PERSISTENT_IDENTITY=true
    persistent_identity_apply

    assertEquals "identity directory mode" 700 "$(mode_of "$DATA_DIR/identity")"
    assertEquals "identity file mode" 600 "$(mode_of "$DATA_DIR/identity/mac")"
}

test_unsafe_auth_layout_fails_closed() {
    mkdir -p "$STUB_ROOT/outside"
    ln -s "$STUB_ROOT/outside" "$DATA_DIR/active"
    export ADGUARD_PERSISTENT_IDENTITY=true

    if persistent_identity_apply; then
        assertTrue "symlinked auth layout must fail" false
    else
        assertTrue "symlinked auth layout rejected" true
    fi

    rm -f "$DATA_DIR/active"
    mkdir -p "$DATA_DIR/cli-home"
    ln -s "$STUB_ROOT/outside" "$DATA_DIR/cli-home/.local"
    if persistent_identity_apply; then
        assertTrue "symlinked CLI adapter layout must fail" false
    else
        assertTrue "symlinked CLI adapter layout rejected" true
    fi
}

test_symlinked_data_root_fails_closed() {
    mkdir -p "$STUB_ROOT/outside"
    rm -rf "$DATA_DIR"
    ln -s "$STUB_ROOT/outside" "$DATA_DIR"
    export ADGUARD_PERSISTENT_IDENTITY=true

    if persistent_identity_apply; then
        assertTrue "symlinked data root must fail" false
    else
        assertTrue "symlinked data root rejected" true
    fi
    assertTrue "symlinked root was not modified" \
        "[ ! -e '$STUB_ROOT/outside/identity' ]"
}

test_missing_default_route_fails_closed() {
    STUB_ROUTE_OUTPUT=''
    export ADGUARD_PERSISTENT_IDENTITY=true

    if persistent_identity_apply; then
        assertTrue "missing default route must fail" false
    else
        assertTrue "missing default route rejected" true
    fi
}

test_set_mac_failure_attempts_restore_and_fails() {
    mkdir -p "$DATA_DIR/identity"
    printf '%s\n' '02:11:22:33:44:56' > "$DATA_DIR/identity/mac"
    STUB_IP_SET_RC=1
    export ADGUARD_PERSISTENT_IDENTITY=true

    if persistent_identity_apply; then
        assertTrue "ip link failure must fail startup" false
    else
        assertTrue "ip link failure rejected" true
    fi
    assertTrue "set command was attempted" \
        "grep -q 'link set dev eth0 address 02:11:22:33:44:56' '$STUB_IP_LOG'"
}

test_effective_mac_mismatch_fails_closed() {
    mkdir -p "$DATA_DIR/identity"
    printf '%s\n' '02:11:22:33:44:56' > "$DATA_DIR/identity/mac"
    STUB_MISMATCH=true
    export ADGUARD_PERSISTENT_IDENTITY=true

    if persistent_identity_apply; then
        assertTrue "post-apply mismatch must fail startup" false
    else
        assertTrue "post-apply mismatch rejected" true
    fi
}

# NOTE: dev's test_auth_migration_preserves_identity_directory depends on
# scripts/lib/auth.sh, which is not part of beta (the active-view split lives
# behind a different code path here).  Equivalent beta coverage lives in
# tests/test_auth_recovery.sh ("identity preserved on opt-in reset" /
# "identity removed on opt-out reset") and tests/test_persistent_identity.sh
# already covers identity/mac lifecycle independently of auth.sh.

SHUNIT2="${SCRIPT_DIR}/lib/shunit2"
if [ ! -f "$SHUNIT2" ]; then
    mkdir -p "${SCRIPT_DIR}/lib"
    curl -fsSL -o "$SHUNIT2" \
        "https://raw.githubusercontent.com/kward/shunit2/master/shunit2"
    chmod +x "$SHUNIT2"
fi
# shellcheck source=/dev/null
source "$SHUNIT2"
