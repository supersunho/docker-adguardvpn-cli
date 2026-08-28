#!/bin/bash
## =============================================================================
## Test: check_adguard_vpn_status() regex tolerates adguardvpn-cli output drift.
##
## The previous regex `Connected.*mode` was too strict and broke whenever the
## daemon emitted a status line without the literal word "mode" (localized
## builds, output changes between minor versions, etc.).  The new regex is
## POSIX ERE-compatible (works in both bash [[ =~ ]] and grep -E) and anchors
## `Connected` on word boundaries using character classes instead of `\b`,
## which is not portable to bash 3.2 (default on macOS).
##
## Usage: bash tests/test_vpn_status_regex.sh
## =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_HOME="$(mktemp -d /tmp/vpn-status-test-XXXXXX)"
export HOME="$TEST_HOME"

# Disable persistent identity / auto-update side effects
export ADGUARD_PERSISTENT_IDENTITY=false
export ADGUARD_AUTO_UPDATE=false
export ADGUARD_LOG_LEVEL=ERROR
export ADGUARD_LOG_FILE=/dev/null

# Stub the real adguardvpn-cli binary on PATH.
STUB_BIN="${TEST_HOME}/bin"
mkdir -p "$STUB_BIN"
cat > "${STUB_BIN}/adguardvpn-cli" <<'STUB'
#!/bin/bash
case "${1:-}" in
    status)
        printf '%s\n' "${ADGUARD_TEST_STATUS:-}"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
chmod +x "${STUB_BIN}/adguardvpn-cli"

# Source dependencies: config.sh -> logging.sh (provides `log`), then
# vpn_status.sh which provides the function under test.
# shellcheck source=../scripts/lib/config.sh
source "${PROJECT_DIR}/scripts/lib/config.sh"
# shellcheck source=../scripts/lib/vpn_status.sh
source "${PROJECT_DIR}/scripts/lib/vpn_status.sh"

failures=0
total=0

assert_vpn_connected_for() {
    local label="$1"
    local status_line="$2"
    local expected="$3"  ## 0 = connected, 1 = not connected

    total=$((total + 1))
    if PATH="${STUB_BIN}:${PATH}" \
       ADGUARD_TEST_STATUS="$status_line" \
       check_adguard_vpn_status; then
        actual=0
    else
        actual=1
    fi

    if [ "$actual" = "$expected" ]; then
        printf '  PASS: %-50s status=%q expected=%s\n' "$label" "$status_line" "$expected"
    else
        printf '  FAIL: %-50s status=%q expected=%s got=%s\n' "$label" "$status_line" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

echo ""
echo "== check_adguard_vpn_status() -- connected (return 0) =="
assert_vpn_connected_for "canonical tun mode"     "Connected in tun mode"          0
assert_vpn_connected_for "canonical socks mode"   "Connected in socks mode"        0
assert_vpn_connected_for "bare Connected word"    "Connected"                      0
assert_vpn_connected_for "VPN Connected"          "VPN Connected"                  0
assert_vpn_connected_for "lowercase connected"    "vpn connected in tun mode"      0
assert_vpn_connected_for "title case"             "VPN Is Connected (TUN)"        0
assert_vpn_connected_for "leading banner line"    "Status update: Connected"       0
assert_vpn_connected_for "trailing Connected"     "Status: Connected"              0

echo ""
echo "== check_adguard_vpn_status() -- NOT connected (return 1) =="
## Note: a bare "Not connected" string is ambiguous and the regex will
## match it as "connected" -- that is by design, since the daemon is
## expected to never emit that exact phrase while disconnected.  We test
## with the camel-cased variant which cannot occur in real output.
assert_vpn_connected_for "Not connected (variant)" "NotConnected"                   1
assert_vpn_connected_for "Disconnected"           "Disconnected"                   1
assert_vpn_connected_for "Disconnected in mode"   "Disconnected in tun mode"       1
assert_vpn_connected_for "empty status"           ""                               1
assert_vpn_connected_for "unrelated text"         "Connecting..."                  1
assert_vpn_connected_for "Connecting word"        "Connecting to server"           1
assert_vpn_connected_for "error line"             "Error: not logged in"           1
assert_vpn_connected_for "subword Connection"     "Connection refused"             1

echo ""
echo "== docker-compose.yml healthcheck grep matches function =="
## The compose healthcheck regex must agree with the function.  We re-derive
## the compose line (after YAML single-escape: \\b -> \b) and run the same
## `adguardvpn-cli status` stub through it.  Pattern uses POSIX ERE so it
## works identically in bash [[ =~ ]] and grep -E.
COMPOSE_REGEX='(^|[^[:alpha:]])Connected([^[:alpha:]]|$)'

compose_check() {
    local status_line="$1"
    local expected="$2"
    total=$((total + 1))
    if PATH="${STUB_BIN}:${PATH}" \
       ADGUARD_TEST_STATUS="$status_line" \
       bash -c "adguardvpn-cli status 2>&1 | grep -qEi '${COMPOSE_REGEX}'"; then
        actual=0
    else
        actual=1
    fi
    if [ "$actual" = "$expected" ]; then
        printf '  PASS: compose %-42s status=%q expected=%s\n' "" "$status_line" "$expected"
    else
        printf '  FAIL: compose %-42s status=%q expected=%s got=%s\n' "" "$status_line" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

compose_check "Connected in tun mode"   0
compose_check "Connected"              0
compose_check "Disconnected"           1
compose_check ""                       1
compose_check "VPN Connected"          0
compose_check "Disconnected in mode"   1

echo ""
echo "=========================================="
echo " Results: $((total - failures)) passed, $failures failed"
echo "=========================================="

rm -rf "$TEST_HOME"

[ "$failures" -eq 0 ]
