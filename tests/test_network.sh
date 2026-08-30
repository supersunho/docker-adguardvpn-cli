#!/bin/bash
set -euo pipefail

# Test: SOCKS5 proxy authentication is passed as proxy authentication.
#
# The credentials must be supplied with curl's proxy-user directive. A netrc
# file would authenticate the origin request instead of the SOCKS5 proxy, so
# this test inspects both the invoked curl arguments and the temporary config
# file.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_HOME="$(mktemp -d /tmp/network-test-XXXXXX)"
export HOME="$TEST_HOME"
export ADGUARD_CONNECTION_TYPE=SOCKS
export ADGUARD_SOCKS5_HOST=127.0.0.1
export ADGUARD_SOCKS5_PORT=1080
export ADGUARD_SHOW_LOG=false
export ADGUARD_SHOW_LOG_LEVEL=ERROR

# shellcheck source=../scripts/lib/logging.sh
source "${PROJECT_DIR}/scripts/lib/logging.sh"
# shellcheck source=../scripts/lib/config.sh
source "${PROJECT_DIR}/scripts/lib/config.sh"
# shellcheck source=../scripts/lib/network.sh
source "${PROJECT_DIR}/scripts/lib/network.sh"

PASS=0
FAIL=0

_find_arg_value() {
    local option="$1"; shift
    local value
    while [ "$#" -gt 0 ]; do
        value="$1"; shift
        if [ "$value" = "$option" ]; then
            [ "$#" -gt 0 ] || return 1
            printf '%s' "$1"
            return 0
        fi
    done
    return 1
}

_has_arg() {
    local wanted="$1"; shift
    local value
    for value in "$@"; do
        [ "$value" = "$wanted" ] && return 0
    done
    return 1
}

_config_permissions() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

test_socks_auth_uses_proxy_config_not_netrc() {
    export ADGUARD_SOCKS5_USERNAME='proxy-user'
    export ADGUARD_SOCKS5_PASSWORD='proxy-password'

    local -a args=()
    _curl_socks5_args args

    local config_file
    config_file="$(_find_arg_value '--config' "${args[@]}" || true)"
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo '  FAIL: SOCKS auth did not create a curl config file'
        FAIL=$((FAIL + 1))
        return
    fi
    if _has_arg '--netrc-file' "${args[@]}" || _has_arg '--user' "${args[@]}" || \
        _has_arg '-u' "${args[@]}"; then
        echo '  FAIL: SOCKS auth used origin-auth curl arguments'
        FAIL=$((FAIL + 1))
        return
    fi

    local config_line
    config_line="$(sed -n '1p' "$config_file")"
    if [ "$config_line" != 'proxy-user = "proxy-user:proxy-password"' ]; then
        echo '  FAIL: curl config does not contain proxy-user authentication'
        FAIL=$((FAIL + 1))
        return
    fi
    if [ "$(_config_permissions "$config_file")" != '600' ]; then
        echo '  FAIL: curl config is not mode 600'
        FAIL=$((FAIL + 1))
        return
    fi

    echo '  PASS: SOCKS auth uses mode-600 proxy-user config without netrc/origin auth'
    PASS=$((PASS + 1))
}

test_socks_auth_escapes_config_special_characters() {
    export ADGUARD_SOCKS5_USERNAME='proxy user"\\path'
    export ADGUARD_SOCKS5_PASSWORD=$'p@ss:word#with space\nnext'

    local -a args=()
    _curl_socks5_args args

    local config_file
    config_file="$(_find_arg_value '--config' "${args[@]}" || true)"
    # The expected line contains curl config escapes, not the raw newline or
    # quote/backslash characters from the environment values.
    local expected='proxy-user = "proxy user\"\\\\path:p@ss:word#with space\nnext"'
    if [ -n "$config_file" ] && [ "$(sed -n '1p' "$config_file")" = "$expected" ]; then
        echo '  PASS: SOCKS proxy credentials preserve config special characters safely'
        PASS=$((PASS + 1))
    else
        echo '  FAIL: SOCKS proxy credentials were not safely escaped in config'
        FAIL=$((FAIL + 1))
    fi
}

test_socks5_curl_invokes_config_without_netrc() {
    export ADGUARD_SOCKS5_USERNAME='proxy-user'
    export ADGUARD_SOCKS5_PASSWORD='proxy-password'
    local args_file
    args_file="$(mktemp "${TEST_HOME}/curl-args.XXXXXX")"

    # Function definitions take precedence over the external curl binary.
    curl() {
        printf '%s\n' "$@" > "$args_file"
    }

    socks5_curl_get 'https://example.test/ip' >/dev/null

    if grep -qx -- '--config' "$args_file" && \
        ! grep -Eq -- '^--netrc-file$|^--user$|^-u$' "$args_file"; then
        echo '  PASS: socks5_curl_get invokes curl with proxy config, not origin auth'
        PASS=$((PASS + 1))
    else
        echo '  FAIL: socks5_curl_get invoked the wrong curl authentication option'
        FAIL=$((FAIL + 1))
    fi
}

echo '=========================================='
echo ' Network SOCKS Authentication Tests'
echo '=========================================='
echo ''

test_socks_auth_uses_proxy_config_not_netrc
test_socks_auth_escapes_config_special_characters
test_socks5_curl_invokes_config_without_netrc

echo ''
echo "Results: $PASS passed, $FAIL failed (network SOCKS authentication)"

rm -rf "$TEST_HOME"
exit $(( FAIL > 0 ? 1 : 0 ))
