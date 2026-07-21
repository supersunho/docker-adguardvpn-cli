#!/bin/bash
#
# Test: OAuth device-code URL detection and user-prompt flow.
#
# Proves that when adguardvpn-cli login outputs the device-code URL,
# _oauth_login() detects it and prints the user prompt.
#
# This test creates a mock adguardvpn-cli script, sets up a test
# harness that replicates the _oauth_login logic from init.sh,
# and verifies the detection + prompt + timeout behavior.
#
# Usage:  bash tests/test_oauth_detection.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PASS=0
FAIL=0

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: ${label}"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: ${label} — expected to find '${needle}' in output"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL + 1))
        echo "  FAIL: ${label} — found unexpected '${needle}'"
    else
        PASS=$((PASS + 1))
        echo "  PASS: ${label}"
    fi
}

# Source logging for test output
HOME="${HOME:-/tmp}"
ADGUARD_LOG_LEVEL=ERROR
source "${PROJECT_DIR}/scripts/lib/logging.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test 1: URL detection from adguardvpn-cli output
#
# Prove the grep pattern correctly extracts the device-code URL from
# the real-world output format that adguardvpn-cli emits.

test_url_pattern_detection() {
    echo "# Test: URL pattern detection from mock output"

    local mock_output
    mock_output='You need to authorize in your browser. The following link will be available for 1799 seconds: https://auth.adguard.io/device_code?user_code=KGPP-FMSN

b - Open link in browser

s - Speed up check

x - Cancel'

    # Test the grep pattern used in _oauth_login
    local detected
    detected=$(echo "$mock_output" | grep -oE 'https://auth\.adguard\.io/device_code\?user_code=[A-Z0-9-]+' 2>/dev/null || true)

    assert_contains "URL extracted from mock output" \
        "https://auth.adguard.io/device_code?user_code=KGPP-FMSN" "$detected"
}

# ---------------------------------------------------------------------------
# Test 2: Full detection flow with mock adguardvpn-cli
#
# Creates a mock adguardvpn-cli that outputs the device-code URL and
# exits 0, then runs a minimal version of the _oauth_login loop.

test_detection_flow_with_mock() {
    echo "# Test: full detection flow with mock adguardvpn-cli"

    local tmpdir
    tmpdir="$(mktemp -d /tmp/oauth-test-XXXXXX 2>/dev/null || echo /tmp/oauth-test-$$)"
    mkdir -p "$tmpdir"

    # Mock adguardvpn-cli that prints the device-code URL and exits 0
    cat > "$tmpdir/adguardvpn-cli" <<'MOCK'
#!/bin/bash
echo "You need to authorize in your browser."
echo "The following link will be available for 1799 seconds:"
echo "https://auth.adguard.io/device_code?user_code=TEST-ABCD"
echo ""
echo "b - Open link in browser"
echo "s - Speed up check"
echo "x - Cancel"
exit 0
MOCK
    chmod +x "$tmpdir/adguardvpn-cli"

    # Save original PATH and restore after
    local saved_PATH="$PATH"
    export PATH="$tmpdir:$PATH"

    # Capture the output of a full _oauth_login-like flow
    local result
    result=$(HOME=/tmp \
        ADGUARD_LOG_LEVEL=INFO \
        PATH="$tmpdir:$saved_PATH" \
        bash "${PROJECT_DIR}/tests/lib/oauth_flow_harness.sh" 2>&1) || true

    export PATH="$saved_PATH"

    # Verify the user prompt was printed
    assert_contains "User prompt printed" \
        "OPEN THIS LINK IN YOUR BROWSER" "$result"

    assert_contains "URL shown to user" \
        "https://auth.adguard.io/device_code?user_code=TEST-ABCD" "$result"

    assert_contains "Authentication completed successfully" \
        "Authentication completed successfully" "$result"

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Test 3: Timeout correctly fails
#
# Mock adguardvpn-cli that hangs forever — _oauth_login should timeout.

test_timeout_is_rejected() {
    echo "# Test: timeout is rejected as failure"

    local tmpdir
    tmpdir="$(mktemp -d /tmp/oauth-test-XXXXXX 2>/dev/null || echo /tmp/oauth-test-$$)"
    mkdir -p "$tmpdir"

    # Mock adguardvpn-cli that hangs (never exits)
    cat > "$tmpdir/adguardvpn-cli" <<'MOCK'
#!/bin/bash
echo "https://auth.adguard.io/device_code?user_code=HANG-TEST"
# Never exit — simulate user never authenticating
while true; do sleep 10; done
MOCK
    chmod +x "$tmpdir/adguardvpn-cli"

    # Run the harness with a very short timeout
    local saved_PATH="$PATH"
    export PATH="$tmpdir:$saved_PATH"

    local result
    result=$(HOME=/tmp \
        ADGUARD_LOG_LEVEL=INFO \
        MOCK_TIMEOUT=3 \
        PATH="$tmpdir:$saved_PATH" \
        bash "${PROJECT_DIR}/tests/lib/oauth_flow_harness.sh" 2>&1) || true

    export PATH="$saved_PATH"

    assert_contains "Timeout message logged" \
        "Authentication timed out" "$result"

    assert_not_contains "Should not say completed on timeout" \
        "Authentication completed successfully" "$result"

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Test 4: Mock adguardvpn-cli failure is detected
#
# Mock that exits with non-zero — login failure should be detected.

test_failure_is_detected() {
    echo "# Test: adguardvpn-cli failure is detected"

    local tmpdir
    tmpdir="$(mktemp -d /tmp/oauth-test-XXXXXX 2>/dev/null || echo /tmp/oauth-test-$$)"
    mkdir -p "$tmpdir"

    # Mock adguardvpn-cli that exits with failure
    cat > "$tmpdir/adguardvpn-cli" <<'MOCK'
#!/bin/bash
echo "Error: could not connect to auth server" >&2
exit 1
MOCK
    chmod +x "$tmpdir/adguardvpn-cli"

    local saved_PATH="$PATH"
    export PATH="$tmpdir:$saved_PATH"

    local result
    result=$(HOME=/tmp \
        ADGUARD_LOG_LEVEL=INFO \
        PATH="$tmpdir:$saved_PATH" \
        bash "${PROJECT_DIR}/tests/lib/oauth_flow_harness.sh" 2>&1) || true

    export PATH="$saved_PATH"

    assert_contains "Failure message logged" \
        "adguardvpn-cli login failed" "$result"

    assert_not_contains "Should not say completed on failure" \
        "Authentication completed successfully" "$result"

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=========================================="
echo " OAuth Detection Tests"
echo "=========================================="
echo ""

test_url_pattern_detection
echo ""
test_detection_flow_with_mock
echo ""
test_timeout_is_rejected
echo ""
test_failure_is_detected
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
