#!/bin/bash
#
# OAuth flow harness — replicates the _oauth_login() logic from init.sh
# for testing with a mock adguardvpn-cli.  Called by test_oauth_detection.sh.
#
# Environment:
#   MOCK_TIMEOUT  — override timeout in seconds (default 1800)
#   PATH          — should include directory with mock adguardvpn-cli

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source logging
source "${PROJECT_DIR}/scripts/lib/logging.sh"

# ---------------------------------------------------------------------------
# _oauth_login  (mirrors the logic in scripts/init.sh)
# ---------------------------------------------------------------------------

_oauth_login() {
    local timeout="${MOCK_TIMEOUT:-1800}"
    local temp_file
    temp_file="$(mktemp /tmp/oauth-harness-XXXXXX 2>/dev/null)" || temp_file="/tmp/oauth-harness-$$"

    # Background the mock login command — $! is its real PID
    adguardvpn-cli login > "$temp_file" 2>&1 &
    local login_pid=$!

    # Relay output in real time
    tail -f "$temp_file" 2>/dev/null &
    local tail_pid=$!

    # Wait for initial output
    sleep 1 &
    wait $! 2>/dev/null || true

    local elapsed=0
    local url_printed=false
    local timed_out=false

    # Small delay for initial process output
    sleep 1 2>/dev/null || true

    # Check for URL even if the process already exited
    _detect_and_print_url() {
        if [ "$url_printed" = false ] && [ -f "$temp_file" ] && \
           grep -qE 'https://auth\.adguard\.io/device_code' "$temp_file" 2>/dev/null; then
            local device_url
            device_url=$(grep -oE 'https://auth\.adguard\.io/device_code\?user_code=[A-Z0-9-]+' \
                         "$temp_file" 2>/dev/null | head -1)

            echo "[TEST] =============================================="
            echo "[TEST]  OPEN THIS LINK IN YOUR BROWSER:"
            echo "[TEST]"
            echo "[TEST]  ${device_url}"
            echo "[TEST]"
            echo "[TEST]  Authenticate in your browser, then wait here."
            echo "[TEST] =============================================="

            url_printed=true
        fi
    }

    # Check immediately (process may exit before loop starts)
    _detect_and_print_url

    while kill -0 "$login_pid" 2>/dev/null; do
        _detect_and_print_url

        sleep 1 &
        wait $! 2>/dev/null || true
        elapsed=$((elapsed + 1))

        if [ "$elapsed" -ge "$timeout" ]; then
            timed_out=true
            kill "$login_pid" 2>/dev/null || true
            break
        fi
    done

    # One last check after process exits (URL might have been in output)
    _detect_and_print_url

    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    rm -f "$temp_file" 2>/dev/null || true

    # Collect the actual exit code of adguardvpn-cli login.
    # The &&/|| pattern captures the exit code while preventing set -e from aborting
    # on non-zero (e.g. 143 when we killed the process ourselves).
    local login_exit=0
    wait "$login_pid" 2>/dev/null && login_exit=$? || login_exit=$?

    if [ "$timed_out" = true ]; then
        log ERROR "Authentication timed out after ${timeout}s"
        return 1
    fi

    if [ "$login_exit" -ne 0 ]; then
        log ERROR "adguardvpn-cli login failed (exit code: ${login_exit})"
        return 1
    fi

    log INFO "Authentication completed successfully"
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

_oauth_login
