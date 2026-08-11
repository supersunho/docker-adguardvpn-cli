#!/bin/bash
set -euo pipefail

# Test: container healthcheck (scripts/healthcheck.sh) and timezone defaulting
# in the Dockerfile.
#
# The healthcheck is mode-aware:
#   - Always require adguardvpn-cli to report an active connection
#     (parity with check_adguard_vpn_status in vpn_status.sh).
#   - In SOCKS mode, additionally verify the SOCKS5 listener accepts a bare
#     TCP connection (no SOCKS negotiation, so no credentials leave the box).
#
# Static assertions cover: no credential reference in the healthcheck, the
# Dockerfile timezone default/fallback, and compose wiring.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE="${PROJECT_DIR}/Dockerfile"
COMPOSE="${PROJECT_DIR}/docker-compose.yml"

PASS=0
FAIL=0

check() {
    local label="$1"
    local ok="$2"

    if [ "$ok" = "1" ]; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"

    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        check "$label" 1
    else
        check "$label" 0
        echo "    missing: ${needle}"
    fi
}

# Start a throwaway TCP listener on 127.0.0.1:port. Returns 0 and sets
# LISTENER_PID on success; returns 1 (listener unavailable) so tests can
# skip rather than fail on platforms without nc.
start_listener() {
    local port="$1"
    if ! command -v nc >/dev/null 2>&1; then
        echo "    (nc unavailable)"
        return 1
    fi
    nc -l 127.0.0.1 "$port" >/dev/null 2>&1 &
    LISTENER_PID=$!
    sleep 0.2
    return 0
}

stop_listener() {
    if [ -n "${LISTENER_PID:-}" ]; then
        kill "${LISTENER_PID}" 2>/dev/null || true
        wait "${LISTENER_PID}" 2>/dev/null || true
        unset LISTENER_PID
    fi
}

# Return a high, currently-unused local TCP port by briefly claiming one.
free_port() {
    local port
    port=$(( 20000 + RANDOM % 20000 ))
    if command -v nc >/dev/null 2>&1; then
        nc -l 127.0.0.1 "$port" >/dev/null 2>&1 &
        local pid=$!
        sleep 0.2
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    echo "$port"
}

# =============================================================================
# VPN status checks
# =============================================================================

test_vpn_status_true() {
    local dir
    dir=$(mktemp -d)
    cat > "$dir/adguardvpn-cli" <<'STUB'
#!/bin/bash
printf '%s\n' 'Connected (mode: TUN)'
STUB
    chmod +x "$dir/adguardvpn-cli"

    local old_path="$PATH"
    export PATH="$dir:$PATH"
    source "${PROJECT_DIR}/scripts/healthcheck.sh"
    if healthcheck_vpn_connected; then
        check "VPN 'Connected' => connected" 1
    else
        check "VPN 'Connected' => connected" 0
    fi
    export PATH="$old_path"
    rm -rf "$dir"
}

test_vpn_status_false() {
    local dir
    dir=$(mktemp -d)
    cat > "$dir/adguardvpn-cli" <<'STUB'
#!/bin/bash
printf '%s\n' 'Disconnected'
STUB
    chmod +x "$dir/adguardvpn-cli"

    local old_path="$PATH"
    export PATH="$dir:$PATH"
    source "${PROJECT_DIR}/scripts/healthcheck.sh"
    if healthcheck_vpn_connected; then
        check "VPN 'Disconnected' => not connected" 0
    else
        check "VPN 'Disconnected' => not connected" 1
    fi
    export PATH="$old_path"
    rm -rf "$dir"
}

# =============================================================================
# SOCKS listener availability
# =============================================================================

test_socks_listener_accepts_when_listening() {
    local port
    port=$(free_port)
    source "${PROJECT_DIR}/scripts/healthcheck.sh"

    if ! start_listener "$port"; then
        return 0
    fi
    ADGUARD_SOCKS5_HOST=127.0.0.1
    ADGUARD_SOCKS5_PORT="$port"
    export ADGUARD_SOCKS5_HOST ADGUARD_SOCKS5_PORT

    if healthcheck_socks_listener_up; then
        check "listener open => listener up" 1
    else
        check "listener open => listener up" 0
    fi
    stop_listener
}

test_socks_listener_rejects_when_closed() {
    local port
    port=$(free_port)
    source "${PROJECT_DIR}/scripts/healthcheck.sh"

    ADGUARD_SOCKS5_HOST=127.0.0.1
    ADGUARD_SOCKS5_PORT="$port"
    export ADGUARD_SOCKS5_HOST ADGUARD_SOCKS5_PORT

    if healthcheck_socks_listener_up; then
        check "listener closed => listener down" 0
        echo "    WARNING: port $port unexpectedly open"
    else
        check "listener closed => listener down" 1
    fi
}

test_socks_listener_zero_host_maps_to_loopback() {
    local port
    port=$(free_port)
    source "${PROJECT_DIR}/scripts/healthcheck.sh"

    if ! start_listener "$port"; then
        return 0
    fi
    ADGUARD_SOCKS5_HOST=0.0.0.0
    ADGUARD_SOCKS5_PORT="$port"
    export ADGUARD_SOCKS5_HOST ADGUARD_SOCKS5_PORT

    if healthcheck_socks_listener_up; then
        check "0.0.0.0 listener probed via loopback" 1
    else
        check "0.0.0.0 listener probed via loopback" 0
    fi
    stop_listener
}

# =============================================================================
# Mode-aware run
# =============================================================================

test_run_tun_mode_requires_status_only() {
    local dir port
    dir=$(mktemp -d)
    port=$(free_port)
    cat > "$dir/adguardvpn-cli" <<'STUB'
#!/bin/bash
printf '%s\n' 'Connected (mode: TUN)'
STUB
    chmod +x "$dir/adguardvpn-cli"

    local old_path="$PATH"
    export PATH="$dir:$PATH"
    source "${PROJECT_DIR}/scripts/healthcheck.sh"

    # TUN mode: connected status alone is healthy even with the SOCKS port closed.
    ADGUARD_CONNECTION_TYPE=TUN
    ADGUARD_SOCKS5_HOST=127.0.0.1
    ADGUARD_SOCKS5_PORT="$port"
    export ADGUARD_CONNECTION_TYPE ADGUARD_SOCKS5_HOST ADGUARD_SOCKS5_PORT

    if healthcheck_run; then
        check "TUN mode: status connected, port closed => healthy" 1
    else
        check "TUN mode: status connected, port closed => healthy" 0
    fi
    export PATH="$old_path"
    rm -rf "$dir"
}

test_run_socks_mode_requires_listener() {
    local dir port
    dir=$(mktemp -d)
    port=$(free_port)
    cat > "$dir/adguardvpn-cli" <<'STUB'
#!/bin/bash
printf '%s\n' 'Connected (mode: SOCKS)'
STUB
    chmod +x "$dir/adguardvpn-cli"

    local old_path="$PATH"
    export PATH="$dir:$PATH"
    source "${PROJECT_DIR}/scripts/healthcheck.sh"

    ADGUARD_CONNECTION_TYPE=SOCKS
    ADGUARD_SOCKS5_HOST=127.0.0.1
    ADGUARD_SOCKS5_PORT="$port"
    export ADGUARD_CONNECTION_TYPE ADGUARD_SOCKS5_HOST ADGUARD_SOCKS5_PORT

    # SOCKS mode with the listener down must be unhealthy even though status is Connected.
    if healthcheck_run; then
        check "SOCKS mode: status connected, port closed => healthy" 0
    else
        check "SOCKS mode: status connected, port closed => healthy" 1
    fi

    # ... and healthy when the listener is up.
    if start_listener "$port"; then
        if healthcheck_run; then
            check "SOCKS mode: status connected, port open => healthy" 1
        else
            check "SOCKS mode: status connected, port open => healthy" 0
        fi
        stop_listener
    fi

    export PATH="$old_path"
    rm -rf "$dir"
}

# =============================================================================
# No-credential-exposure guarantees
# =============================================================================

test_healthcheck_never_references_credentials() {
    local content
    content=$(cat "${PROJECT_DIR}/scripts/healthcheck.sh")

    if printf '%s' "$content" | grep -qE 'SOCKS5_(USERNAME|PASSWORD)'; then
        check "healthcheck does not read SOCKS credentials" 0
    else
        check "healthcheck does not read SOCKS credentials" 1
    fi

    # A bare TCP handshake must not be a proxied curl request that would send
    # credentials to a destination. Match an actual curl *invocation* (a line
    # whose first command is curl), not the word in a comment.
    if printf '%s' "$content" | grep -qE '^\s*curl(\s|$)'; then
        check "healthcheck uses no proxied curl (no credential egress)" 0
    else
        check "healthcheck uses no proxied curl (no credential egress)" 1
    fi
}

# =============================================================================
# Dockerfile timezone
# =============================================================================

test_dockerfile_timezone_default_and_guard() {
    local content
    content=$(cat "$DOCKERFILE")

    assert_contains "Dockerfile declares ARG TZ with default" \
        "$content" "ARG TZ="

    # The symlink must be produced from a validated zoneinfo path, i.e. the
    # target is $TZ under /usr/share/zoneinfo (never the bare directory).
    if printf '%s' "$content" | grep -qE '/usr/share/zoneinfo/\$\{?TZ\}?'; then
        check "Dockerfile links /etc/localtime from /usr/share/zoneinfo/\$TZ" 1
    else
        check "Dockerfile links /etc/localtime from /usr/share/zoneinfo/\$TZ" 0
    fi

    # Guard against an unset/invalid TZ producing a dangling/directory link:
    # there must be a validity check + Etc/UTC fallback in the same RUN block.
    if printf '%s' "$content" | grep -qE 'Etc/UTC' && \
       printf '%s' "$content" | grep -qE '\-f[" ]*/usr/share/zoneinfo'; then
        check "Dockerfile validates TZ and falls back to Etc/UTC" 1
    else
        check "Dockerfile validates TZ and falls back to Etc/UTC" 0
    fi

    # The build must write the chosen value into /etc/timezone (not the
    # unquoted, unguarded form that expands to a directory).
    if printf '%s' "$content" | grep -qE 'echo .*>\s*/etc/timezone'; then
        check "Dockerfile writes TZ to /etc/timezone" 1
    else
        check "Dockerfile writes TZ to /etc/timezone" 0
    fi
}

# =============================================================================
# Compose wiring
# =============================================================================

test_compose_uses_healthcheck_script() {
    local content
    content=$(cat "$COMPOSE")

    assert_contains "compose healthcheck invokes scripts/healthcheck.sh" \
        "$content" "scripts/healthcheck.sh"

    if printf '%s' "$content" | grep -qE 'CMD-SHELL.*adguardvpn-cli status.*grep'; then
        check "compose no longer uses inline status grep healthcheck" 0
    else
        check "compose no longer uses inline status grep healthcheck" 1
    fi
}

# =============================================================================
# Runner
# =============================================================================

echo "=========================================="
echo " Healthcheck & Timezone Tests"
echo "=========================================="
echo ""

test_vpn_status_true
echo ""
test_vpn_status_false
echo ""
test_socks_listener_accepts_when_listening
echo ""
test_socks_listener_rejects_when_closed
echo ""
test_socks_listener_zero_host_maps_to_loopback
echo ""
test_run_tun_mode_requires_status_only
echo ""
test_run_socks_mode_requires_listener
echo ""
test_healthcheck_never_references_credentials
echo ""
test_dockerfile_timezone_default_and_guard
echo ""
test_compose_uses_healthcheck_script
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))