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

test_non_localhost_configuration_is_applied_in_safe_order() {
    local test_dir
    test_dir=$(mktemp -d)

    cat > "${test_dir}/adguardvpn-cli" <<'STUB'
#!/bin/bash
set -euo pipefail

printf '%s %s\n' "${2:-}" "${3:-}" >> "$COMMAND_LOG"

case "${2:-}" in
    set-socks-host)
        printf '%s\n' "${3:-}" > "$HOST_FILE"
        ;;
    clear-socks-auth)
        if [ "$(cat "$HOST_FILE")" != "127.0.0.1" ]; then
            echo "Username is required for non-localhost listen address" >&2
            exit 16
        fi
        ;;
esac
STUB
    chmod +x "${test_dir}/adguardvpn-cli"

    export PATH="${test_dir}:${PATH}"
    export COMMAND_LOG="${test_dir}/commands.log"
    export HOST_FILE="${test_dir}/host"
    export ADGUARD_CONNECTION_TYPE=SOCKS
    export ADGUARD_SOCKS5_USERNAME=test-user
    export ADGUARD_SOCKS5_PASSWORD='test@password'
    export ADGUARD_SOCKS5_HOST=0.0.0.0
    export ADGUARD_SOCKS5_PORT=1080
    export ADGUARD_SHOW_LOG=false

    source "${PROJECT_DIR}/scripts/lib/logging.sh"
    source "${PROJECT_DIR}/scripts/lib/network.sh"

    network_init_socks

    local expected actual
    expected=$'set-socks-host 127.0.0.1\nclear-socks-auth \nset-socks-username test-user\nset-socks-password test@password\nset-socks-port 1080\nset-socks-host 0.0.0.0'
    actual=$(cat "$COMMAND_LOG")
    assert_equals "non-localhost SOCKS settings use a valid transition order" "$expected" "$actual"

    rm -rf "$test_dir"
}

echo "=========================================="
echo " SOCKS Configuration Tests"
echo "=========================================="
echo ""

test_non_localhost_configuration_is_applied_in_safe_order

echo ""
echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
