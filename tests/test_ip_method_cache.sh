#!/bin/bash
set -euo pipefail

# Test: IP method cache security
#
# Proves that ip_method.txt stores only v1|type|id records,
# unknown IDs are ignored, injection payloads produce no side effects,
# and cache writes are atomic with mode 600.
#
# Usage:  bash tests/test_ip_method_cache.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Create temp HOME for isolated cache file testing
_IP_CACHE_TMPDIR="$(mktemp -d /tmp/ip-cache-test-XXXXXX 2>/dev/null || echo "/tmp/ip-cache-test-$$")"
export HOME="$_IP_CACHE_TMPDIR"

# Source modules in order
source "${PROJECT_DIR}/scripts/lib/logging.sh"
source "${PROJECT_DIR}/scripts/lib/error_handling.sh"
source "${PROJECT_DIR}/scripts/lib/config.sh"
source "${PROJECT_DIR}/scripts/lib/network.sh"
source "${PROJECT_DIR}/scripts/lib/ip_detection.sh"

ADGUARD_LOG_LEVEL="${ADGUARD_LOG_LEVEL:-ERROR}"

PASS=0
FAIL=0

# =============================================================================
# Test 1+2: Dispatch functions exist
# =============================================================================

test_dispatch_functions_defined() {
    if type _ip_run_dns_method >/dev/null 2>&1; then
        echo "  PASS: _ip_run_dns_method is defined"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: _ip_run_dns_method not defined"
        FAIL=$((FAIL + 1))
    fi

    if type _ip_run_http_method >/dev/null 2>&1; then
        echo "  PASS: _ip_run_http_method is defined"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: _ip_run_http_method not defined"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 3: _ip_save_methods writes v1|type|id format
# =============================================================================

test_save_method_writes_v1_format() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    rm -f "$cache"

    _ip_save_methods "opendns" ""

    if [ -f "$cache" ]; then
        local content
        content=$(cat "$cache")
        if [ "$content" = "v1|dns|opendns" ]; then
            echo "  PASS: cache contains v1|dns|opendns"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: unexpected content: $content"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: cache file not created"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 4: Saving both methods is atomic and preserves both records
# =============================================================================

test_save_methods_preserves_both_records() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    rm -f "$cache"

    _ip_save_methods "opendns" "aws"

    read -r dns http <<< "$(_ip_load_methods)"

    if [ "$dns" = "opendns" ] && [ "$http" = "aws" ]; then
        echo "  PASS: cache preserves DNS and HTTP methods together"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: expected dns=opendns and http=aws, got dns='$dns' http='$http'"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 5: get_public_ip persists both successful methods
# =============================================================================

test_get_public_ip_persists_both_methods() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    rm -f "$cache"

    # Stub discovery so this exercises get_public_ip's reconciliation path,
    # not just the low-level cache writer.
    is_socks_mode() { return 1; }
    _ip_detect_dns() {
        _IP_LAST_DNS_ID="opendns"
        _IP_DETECTED_IP="198.51.100.7"
        printf '%s\n' '198.51.100.7'
    }
    _ip_detect_http() {
        _IP_LAST_HTTP_ID="aws"
        _IP_DETECTED_IP="198.51.100.7"
        printf '%s\n' '198.51.100.7'
    }

    local result
    result=$(get_public_ip)
    read -r dns http <<< "$(_ip_load_methods)"

    if [ "$result" = "198.51.100.7" ] && \
       [ "$dns" = "opendns" ] && [ "$http" = "aws" ]; then
        echo "  PASS: get_public_ip persists DNS and HTTP methods together"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: get_public_ip lost one of the successful methods"
        echo "   result='$result' dns='$dns' http='$http'"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 6: File mode 600
# =============================================================================

test_save_method_mode_600() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    rm -f "$cache"

    _ip_save_methods "" "aws"

    if [ -f "$cache" ]; then
        local perms
        # GNU stat returns filesystem information for -f, even with a zero
        # exit status. Try its file-mode format first, then BSD/macOS stat.
        perms=$(stat -c "%a" "$cache" 2>/dev/null || \
            stat -f "%Lp" "$cache" 2>/dev/null || echo "unknown")
        if [ "$perms" = "600" ]; then
            echo "  PASS: cache file mode is 600"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: cache file mode is $perms (expected 600)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: cache file not created"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 5: Load known method
# =============================================================================

test_load_known_method() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    mkdir -p "$(dirname "$cache")"
    printf 'v1|dns|opendns\n' > "$cache"

    read -r dns http <<< "$(_ip_load_methods)"

    if [ "$dns" = "opendns" ]; then
        echo "  PASS: loaded DNS method is opendns"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: expected opendns, got '$dns'"
        FAIL=$((FAIL + 1))
    fi

    if [ -z "$http" ]; then
        echo "  PASS: HTTP method is empty (none saved)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: expected empty HTTP method, got '$http'"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 6: Ignore unknown IDs
# =============================================================================

test_load_ignores_unknown_ids() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    mkdir -p "$(dirname "$cache")"
    printf 'v1|dns|unknown_method\n' > "$cache"

    read -r dns http <<< "$(_ip_load_methods)"

    if [ -z "$dns" ]; then
        echo "  PASS: unknown DNS method ID is ignored"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: unknown ID '$dns' should have been ignored"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 7: Ignore legacy executable format
# =============================================================================

test_load_ignores_executable_format() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    mkdir -p "$(dirname "$cache")"
    printf 'dns|opendns|dig_get +short myip.opendns.com @resolver1.opendns.com\n' > "$cache"

    read -r dns http <<< "$(_ip_load_methods)"

    if [ -z "$dns" ] && [ -z "$http" ]; then
        echo "  PASS: legacy executable format is ignored"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: legacy format returned dns='$dns' http='$http'"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 8: Ignore injection payloads
# =============================================================================

test_load_ignores_injection() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    mkdir -p "$(dirname "$cache")"
# shellcheck disable=SC2016 # intentional: literal injection test string
    # Literal injection string — shellcheck disable: intentional test content
    printf 'v1|dns|$(touch /tmp/pwned)\n' > "$cache"

    read -r dns http <<< "$(_ip_load_methods)"

    if [ -z "$dns" ]; then
        echo "  PASS: injection payload is ignored"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: injection payload was accepted: '$dns'"
        FAIL=$((FAIL + 1))
    fi

    if [ ! -f /tmp/pwned ]; then
        echo "  PASS: no side effect from injection"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: injection created /tmp/pwned!"
        FAIL=$((FAIL + 1))
        rm -f /tmp/pwned
    fi
}

# =============================================================================
# Test 9: Atomic write pattern in source
# =============================================================================

test_atomic_write_pattern() {
    local src="${PROJECT_DIR}/scripts/lib/ip_detection.sh"

    if grep -q 'mktemp' "$src" && grep -q 'mv -f' "$src" && grep -q 'chmod 600' "$src"; then
        echo "  PASS: source uses mktemp + chmod 600 + mv pattern"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: source missing atomic write pattern"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 10: No command execution from cache
# =============================================================================

test_no_command_execution_from_cache() {
    local src="${PROJECT_DIR}/scripts/lib/ip_detection.sh"

    if grep -n 'read -ra.*cmd_parts' "$src" 2>/dev/null; then
        echo "  FAIL: source still uses read -ra for command execution"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: no read -ra command execution from cache"
        PASS=$((PASS + 1))
    fi

    # Check that the cmd_parts array execution pattern is absent
# shellcheck disable=SC2016 # intentional: literal grep pattern
    if grep -n '\${cmd_parts\[' "$src" 2>/dev/null; then
        echo "  FAIL: source still uses cmd_parts array execution"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: no cmd_parts array execution"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 11: Newly added HTTP IDs are registered and round-trip via the cache
# =============================================================================

test_new_http_ids_registered() {
    local src="${PROJECT_DIR}/scripts/lib/ip_detection.sh"

    # _IP_HTTP_SERVICES must include the new IDs.
    if grep -q '"ifconfig"' "$src" && grep -q '"ident"' "$src"; then
        echo "  PASS: _IP_HTTP_SERVICES includes ifconfig and ident"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: _IP_HTTP_SERVICES missing new IDs"
        FAIL=$((FAIL + 1))
    fi

    # _ip_run_http_method case branches must map them to allowlisted URLs.
    if grep -q 'ifconfig\.co/ip' "$src" && grep -q 'ident\.me' "$src"; then
        echo "  PASS: dispatch case branches map new IDs to allowlisted URLs"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: dispatch case branches do not map new IDs"
        FAIL=$((FAIL + 1))
    fi
}

test_new_http_ids_round_trip_via_cache() {
    local cache="${HOME}/.local/share/adguardvpn-cli/ip_method.txt"
    rm -f "$cache"

    # Pair with a known DNS ID so the save/load parser has both fields
    # well-defined; this matches the real call sites (get_public_ip only
    # saves both IDs when both DNS and HTTP succeeded).
    _ip_save_methods "opendns" "ifconfig"
    read -r _dns _http <<< "$(_ip_load_methods)"

    if [ "$_http" = "ifconfig" ] && [ "$_dns" = "opendns" ]; then
        echo "  PASS: ifconfig survives v1|http| save/load round-trip"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ifconfig round-trip got dns='${_dns}' http='${_http}'"
        FAIL=$((FAIL + 1))
    fi

    _ip_save_methods "opendns" "ident"
    read -r _dns _http <<< "$(_ip_load_methods)"
    if [ "$_http" = "ident" ] && [ "$_dns" = "opendns" ]; then
        echo "  PASS: ident survives v1|http| save/load round-trip"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ident round-trip got dns='${_dns}' http='${_http}'"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 12: _ip_run_http_method actually dispatches new IDs to the right
# transport (curl_get for direct, socks5_curl_get for SOCKS) with the right URL.
# =============================================================================

test_new_http_ids_dispatch_via_stub_curl() {
    # Replace curl_get / socks5_curl_get with shims that record their
    # arguments, so we can verify both routing and URL without making
    # network calls.
    local shim_dir
    shim_dir=$(mktemp -d /tmp/ip-cache-shim-XXXXXX)
    export _IP_STUB_DIRECT_LOG="$shim_dir/direct.log"
    export _IP_STUB_SOCKS_LOG="$shim_dir/socks.log"
    : > "$_IP_STUB_DIRECT_LOG"
    : > "$_IP_STUB_SOCKS_LOG"

    curl_get() {
        # Append the URL to the direct log; print a fake IP.
        printf '%s\n' "$*" >> "$_IP_STUB_DIRECT_LOG"
        printf '203.0.113.7'
    }
    socks5_curl_get() {
        printf '%s\n' "$*" >> "$_IP_STUB_SOCKS_LOG"
        printf '198.51.100.7'
    }

    local id expected_url got_url got_via got_ip
    for id in ifconfig ident; do
        case "$id" in
            ifconfig) expected_url="https://ifconfig.co/ip" ;;
            ident)    expected_url="https://ident.me" ;;
        esac

        # Direct (TUN) path: use_socks5=false
        got_url=$(_ip_run_http_method "$id" false 2>/dev/null)
        if [ "$got_url" = "203.0.113.7" ] && \
           grep -qF "$expected_url" "$_IP_STUB_DIRECT_LOG"; then
            echo "  PASS: ${id} dispatches to curl_get with ${expected_url} (direct)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: ${id} direct dispatch: got url '$(tail -1 "$_IP_STUB_DIRECT_LOG" 2>/dev/null)' ip '${got_url}'"
            FAIL=$((FAIL + 1))
        fi

        # SOCKS path: use_socks5=true
        got_via=$(_ip_run_http_method "$id" true 2>/dev/null)
        if [ "$got_via" = "198.51.100.7" ] && \
           grep -qF "$expected_url" "$_IP_STUB_SOCKS_LOG"; then
            echo "  PASS: ${id} dispatches to socks5_curl_get with ${expected_url} (SOCKS)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: ${id} SOCKS dispatch: got url '$(tail -1 "$_IP_STUB_SOCKS_LOG" 2>/dev/null)' ip '${got_via}'"
            FAIL=$((FAIL + 1))
        fi
    done

    unset _IP_STUB_DIRECT_LOG _IP_STUB_SOCKS_LOG
    rm -rf "$shim_dir"
}

test_new_http_ids_reject_unknown_id() {
    # An ID outside the allowlist must not call any transport; the function
    # returns 1 and produces no output.
    local out
    out=$(_ip_run_http_method "not_in_allowlist" false 2>/dev/null || true)
    if [ -z "$out" ]; then
        echo "  PASS: unknown HTTP ID rejected silently"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: unknown ID leaked output: '${out}'"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " IP Method Cache Security Tests"
echo "=========================================="
echo ""

test_dispatch_functions_defined
echo ""
test_save_method_writes_v1_format
echo ""
test_save_methods_preserves_both_records
echo ""
test_get_public_ip_persists_both_methods
echo ""
test_save_method_mode_600
echo ""
test_load_known_method
echo ""
test_load_ignores_unknown_ids
echo ""
test_load_ignores_executable_format
echo ""
test_load_ignores_injection
echo ""
test_atomic_write_pattern
echo ""
test_no_command_execution_from_cache
echo ""
test_new_http_ids_registered
echo ""
test_new_http_ids_round_trip_via_cache
echo ""
test_new_http_ids_dispatch_via_stub_curl
echo ""
test_new_http_ids_reject_unknown_id
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

rm -rf "$HOME"

exit $(( FAIL > 0 ? 1 : 0 ))
