#!/bin/bash
# Test: kill switch SOCKS-mode soft-success and IP detection bypass.
#
# In SOCKS mode, once adguardvpn-cli reports Connected, the SOCKS5 proxy is
# listening on the configured port and traffic is actively tunneled.  The
# detector must (a) treat Connected as immediate tunnel-active during the
# 60s wait window, and (b) skip HTTP IP detection on the periodic check
# (because IP detection through the proxy is unreliable in the first few
# seconds and KS must not self-terminate just because the proxy is busy).
#
# This test stubs check_adguard_vpn_status and ks_detect_ip_consistent
# (forcing the latter to ERROR) to confirm the SOCKS soft-success branch
# returns 0 from ks_wait_for_vpn_tunnel and ks_detect_current_ip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEST_HOME="$(mktemp -d /tmp/killswitch-socks-test-XXXXXX)"
export HOME="$TEST_HOME"
export ADGUARD_SHOW_LOG=false
export ADGUARD_SHOW_LOG_LEVEL=ERROR

# shellcheck source=../scripts/lib/logging.sh
source "${PROJECT_DIR}/scripts/lib/logging.sh"
# shellcheck source=../scripts/lib/config.sh
source "${PROJECT_DIR}/scripts/lib/config.sh"
# shellcheck source=../scripts/lib/network.sh
source "${PROJECT_DIR}/scripts/lib/network.sh"
# shellcheck source=../scripts/lib/vpn_status.sh
source "${PROJECT_DIR}/scripts/lib/vpn_status.sh"
# shellcheck source=../scripts/lib/killswitch_detector.sh
source "${PROJECT_DIR}/scripts/lib/killswitch_detector.sh"

PASS=0
FAIL=0

# ---- Test 1: ks_wait_for_vpn_tunnel returns 0 in SOCKS mode when status=Connected ----
test_socks_wait_returns_on_connected() {
    :
    ADGUARD_CONNECTION_TYPE=SOCKS
    KS_REAL_IP="211.176.140.126"
    KS_VPN_IP=""
    local start_ts elapsed
    start_ts=$(date +%s)

    KS_VPN_IP=""
    # KS_MAX_WAIT_TIME is readonly (60 by default) -- use it directly
    # Stub: IP detection would otherwise block / fail
    check_adguard_vpn_status() { return 0; }
    ks_detect_ip_consistent() { echo "ERROR"; return 1; }

    # Stub: log to silence output
    log() { :; }

    if ks_wait_for_vpn_tunnel; then
        elapsed=$(( $(date +%s) - start_ts ))
        if [ "$elapsed" -le 3 ]; then
            echo "  PASS: SOCKS wait returned immediately on Connected status"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: SOCKS wait took ${elapsed}s, expected <3s"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: SOCKS wait did not return 0 on Connected status"
        FAIL=$((FAIL + 1))
    fi
}

# ---- Test 2: the disconnected-status fallback initializes KS_VPN_IP -------
test_socks_wait_fallback_initializes_vpn_ip() {
    ADGUARD_CONNECTION_TYPE=SOCKS
    KS_REAL_IP="211.176.140.126"
    unset KS_VPN_IP

    # A steady-state SOCKS tunnel can report Disconnected while its connected
    # log entry and listener still prove that it is active.
    check_adguard_vpn_status() { return 1; }
    ks_tunnel_connected_in_log() { return 0; }
    ks_socks_port_listening() { return 0; }
    log() { :; }

    if ks_wait_for_vpn_tunnel; then
        if [ "$KS_VPN_IP" = "$KS_REAL_IP" ]; then
            echo "  PASS: SOCKS fallback initializes KS_VPN_IP"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: SOCKS fallback left KS_VPN_IP='${KS_VPN_IP:-}'"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: SOCKS disconnected-status fallback did not return 0"
        FAIL=$((FAIL + 1))
    fi
}

# ---- Test 3: standalone kill-switch loop must not return from top level ----
test_killswitch_loop_continues_after_socks_check() {
    if grep -Eq '^[[:space:]]*return[[:space:]]+0[[:space:]]*$' \
        "${PROJECT_DIR}/scripts/killswitch.sh"; then
        echo "  FAIL: standalone kill-switch loop contains a top-level return 0"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: standalone kill-switch loop has no top-level return 0"
        PASS=$((PASS + 1))
    fi
}

# ---- Test 4: ks_detect_current_ip returns 0 in SOCKS mode when status=Connected ----
test_socks_detect_returns_on_connected() {
    ADGUARD_CONNECTION_TYPE=SOCKS
    KS_REAL_IP="211.176.140.126"
    KS_VPN_IP=""
    KS_CURRENT_IP=""
    local start_ts elapsed
    start_ts=$(date +%s)

    # Stub: adguardvpn-cli status returns Connected
    check_adguard_vpn_status() { return 0; }
    # Stub: IP detection would otherwise fail (but must NOT be called in SOCKS mode)
    ks_detect_ip_consistent() { echo "ERROR"; return 1; }
    log() { :; }

    if ks_detect_current_ip; then
        elapsed=$(( $(date +%s) - start_ts ))
        if [ "$elapsed" -le 1 ]; then
            echo "  PASS: SOCKS detect returned immediately on Connected status"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: SOCKS detect took ${elapsed}s, expected <1s (must skip IP detect)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: SOCKS detect did not return 0 on Connected status"
        FAIL=$((FAIL + 1))
    fi
}

# ---- Test 3: ks_detect_current_ip fails in SOCKS mode when status=NOT Connected ----
test_socks_detect_fails_on_disconnected() {
    ADGUARD_CONNECTION_TYPE=SOCKS
    KS_REAL_IP="211.176.140.126"
    KS_VPN_IP=""
    KS_CURRENT_IP=""

    # Stub: adguardvpn-cli status returns NOT Connected
    check_adguard_vpn_status() { return 1; }
    # Stub: IP detection returns ERROR (must be called as fallback in this case)
    ks_detect_ip_consistent() { echo "ERROR"; return 1; }
    log() { :; }

    if ks_detect_current_ip; then
        echo "  FAIL: SOCKS detect returned 0 even though status=NOT Connected"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: SOCKS detect correctly returns 1 when status=NOT Connected"
        PASS=$((FAIL + 1))
        PASS=$((PASS + 1))
    fi
}

# ---- Test 4: TUN mode is unchanged -- still does IP detection ----
test_tun_detect_still_uses_ip() {
    ADGUARD_CONNECTION_TYPE=TUN
    KS_REAL_IP="211.176.140.126"
    KS_VPN_IP=""
    KS_CURRENT_IP=""

    local ip_detect_called=0
    check_adguard_vpn_status() { return 1; }
    IP_COUNTER_FILE="$(mktemp)"; ks_detect_ip_consistent() { echo 1 > "$IP_COUNTER_FILE"; echo "1.2.3.4"; return 0; }
    log() { :; }

    if ks_detect_current_ip; then
        if [ "$(cat "$IP_COUNTER_FILE" 2>/dev/null)" = "1" ]; then
            echo "  PASS: TUN detect still calls ks_detect_ip_consistent"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: TUN detect did not call ks_detect_ip_consistent"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: TUN detect did not return 0 on successful IP detection"
        FAIL=$((FAIL + 1))
    fi
}

test_socks_is_connected_returns_on_port_listening() {
    #### SOCKS mode + SOCKS5 port listening -> ks_is_vpn_connected returns 0
    #### even if adguardvpn-cli status fails (status output is unstable in
    #### steady state for SOCKS mode).
    export ADGUARD_CONNECTION_TYPE=SOCKS
    export ADGUARD_SOCKS5_PORT=19471
    if is_socks_mode; then :; else
        echo "  FAIL: is_socks_mode did not detect SOCKS mode"
        FAIL=$((FAIL + 1))
        return
    fi
    # Stub check_adguard_vpn_status to fail (return 1) -- simulates
    # post-Connected status instability in SOCKS mode.
    check_adguard_vpn_status() { return 1; }
    # ks_socks_port_listening must be called by ks_is_vpn_connected and
    # return 0 (port listening).  Inject a fake /proc/net/tcp with a
    # listening entry for port 19471 (0x4C0F).
    FAKE_PROC_DIR=$(mktemp -d)
    printf '  0: 00000000:4C0F 00000000:0000 0A 00000000:00000000 00:00000000 00000000  0 0 0 0\n' > "$FAKE_PROC_DIR/net_tcp"
    printf '  0: 00000000000000000000000000000000:4C0F 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  0 0 0 0\n' > "$FAKE_PROC_DIR/net_tcp6"
    ks_socks_port_listening() {
        local hex_port
        hex_port=$(printf '%04X' "${ADGUARD_SOCKS5_PORT:-1080}")
        awk -v want="$hex_port" \
            '$2 ~ /:'"$hex_port"'$/ && $4 == "0A" {found=1; exit} END{exit !found}' \
            "$FAKE_PROC_DIR/net_tcp" "$FAKE_PROC_DIR/net_tcp6" 2>/dev/null
    }
    if ks_socks_port_listening; then
        if ks_is_vpn_connected; then
            echo "  PASS: SOCKS port listening returns VPN connected"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: ks_is_vpn_connected returned false despite port listening"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: ks_socks_port_listening did not detect fake port"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$FAKE_PROC_DIR"
}

test_socks_is_connected_fails_when_port_closed() {
    #### SOCKS mode + SOCKS5 port NOT listening + status fails -> return 1
    export ADGUARD_CONNECTION_TYPE=SOCKS
    export ADGUARD_SOCKS5_PORT=19471
    check_adguard_vpn_status() { return 1; }
    FAKE_PROC_DIR=$(mktemp -d)
    printf '  0: 00000000:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000  0 0 0 0\n' > "$FAKE_PROC_DIR/net_tcp"
    printf '  0: 00000000:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000  0 0 0 0\n' > "$FAKE_PROC_DIR/net_tcp6"
    ks_socks_port_listening() {
        local hex_port
        hex_port=$(printf '%04X' "${ADGUARD_SOCKS5_PORT:-1080}")
        awk -v want="$hex_port" \
            '$2 ~ /:'"$hex_port"'$/ && $4 == "0A" {found=1; exit} END{exit !found}' \
            "$FAKE_PROC_DIR/net_tcp" "$FAKE_PROC_DIR/net_tcp6" 2>/dev/null
    }
    if ks_socks_port_listening; then
        echo "  FAIL: ks_socks_port_listening reported listening for non-existent port"
        FAIL=$((FAIL + 1))
    else
        if ks_is_vpn_connected; then
            echo "  FAIL: ks_is_vpn_connected returned true despite port closed and status fail"
            FAIL=$((FAIL + 1))
        else
            echo "  PASS: SOCKS port closed + status fail -> return 1"
            PASS=$((PASS + 1))
        fi
    fi
}

# Save the real ks_socks_port_listening and _ks_port_listening_darwin
# before any test stubs them.  Tests 7-9 need the real dispatcher and
# real Darwin impl.  Bash functions can be re-sourced indirectly via
# declare -f, but here we keep references for restoration.
_REAL_KS_SOCKS_PORT_LISTENING_DEFINED=$(declare -f ks_socks_port_listening 2>/dev/null)
_REAL_KS_DARWIN_DEFINED=$(declare -f _ks_port_listening_darwin 2>/dev/null)
_REAL_KS_LINUX_DEFINED=$(declare -f _ks_port_listening_linux 2>/dev/null)
# Helper: restore the real dispatcher and platform impls.  Used at the
# top of tests 7-9 after earlier tests have stubbed the lib.
_ks_restore_real_dispatcher() {
    eval "$_REAL_KS_SOCKS_PORT_LISTENING_DEFINED"
    eval "$_REAL_KS_DARWIN_DEFINED"
    eval "$_REAL_KS_LINUX_DEFINED"
}

# ---- Test 7: dispatcher routes to Darwin impl when uname -s == Darwin ----
test_socks_dispatcher_routes_to_darwin() {
    #### The dispatcher in ks_socks_port_listening must call the
    export ADGUARD_SOCKS5_PORT=19471
    # Earlier tests (test 6) redefine ks_socks_port_listening for
    # fake-proc mock; restore the real dispatcher from the saved copy.
    _ks_restore_real_dispatcher
    SHIM_DIR=$(mktemp -d)
    cat > "$SHIM_DIR/uname" <<'EOF'
#!/bin/sh
case "$1" in
    -s) echo Darwin ;;
    *)  /usr/bin/uname "$@" ;;
esac
EOF
    chmod +x "$SHIM_DIR/uname"
    LSOF_DIR=$(mktemp -d)
    cat > "$LSOF_DIR/lsof" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$LSOF_DIR/lsof"
    PATH="$LSOF_DIR:$SHIM_DIR:$PATH"
    if ks_socks_port_listening; then
        echo "  PASS: dispatcher routes to Darwin impl on macOS"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ks_socks_port_listening returned non-zero on Darwin with port open"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$SHIM_DIR" "$LSOF_DIR"
}

# ---- Test 8: Darwin impl uses lsof with correct arguments ----
test_socks_darwin_uses_lsof() {
    #### _ks_port_listening_darwin must invoke lsof with the configured
    #### port and a LISTEN filter.  Stub lsof to capture the call and
    #### return success.
    export ADGUARD_SOCKS5_PORT=19471
    # Earlier tests may have redefined _ks_port_listening_darwin.
    # Restore the real Darwin impl from the saved copy.
    _ks_restore_real_dispatcher
    SHIM_DIR=$(mktemp -d)
    LSOF_ARGS_FILE="$SHIM_DIR/lsof_args"
    cat > "$SHIM_DIR/lsof" <<EOF
#!/bin/sh
echo "\$*" > "$LSOF_ARGS_FILE"
exit 0
EOF
    chmod +x "$SHIM_DIR/lsof"
    PATH="$SHIM_DIR:$PATH"
    if _ks_port_listening_darwin "$ADGUARD_SOCKS5_PORT"; then
        if [ -f "$LSOF_ARGS_FILE" ] && grep -q "19471" "$LSOF_ARGS_FILE" && \
            grep -q "LISTEN" "$LSOF_ARGS_FILE"; then
            echo "  PASS: Darwin impl calls lsof with port + LISTEN filter"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: Darwin impl did not call lsof with expected args"
            echo "        lsof args file: $(cat "$LSOF_ARGS_FILE" 2>/dev/null)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: _ks_port_listening_darwin returned non-zero with stubbed lsof"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$SHIM_DIR"
}

# ---- Test 9: dispatcher fails closed on unsupported OS ----
test_socks_dispatcher_unsupported_os_fails_closed() {
    #### An unrecognised OS (not Linux, not Darwin) must make
    #### ks_socks_port_listening return non-zero so KS treats the
    #### tunnel as disconnected (fail-closed).
    export ADGUARD_SOCKS5_PORT=19471
    # Earlier tests may have stubbed the dispatcher.  Restore the
    # real one so the unsupported-OS branch is exercised.
    _ks_restore_real_dispatcher
    SHIM_DIR=$(mktemp -d)
    cat > "$SHIM_DIR/uname" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] && echo FreeBSD || /usr/bin/uname "$@"
EOF
    chmod +x "$SHIM_DIR/uname"
    PATH="$SHIM_DIR:$PATH"
    if ks_socks_port_listening; then
        echo "  FAIL: dispatcher returned 0 on unsupported OS (expected fail-closed)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: dispatcher fails closed on unsupported OS"
        PASS=$((PASS + 1))
    fi
    rm -rf "$SHIM_DIR"
}
test_socks_dispatcher_routes_to_darwin
test_socks_darwin_uses_lsof
test_socks_dispatcher_unsupported_os_fails_closed
test_socks_wait_returns_on_connected
test_socks_wait_fallback_initializes_vpn_ip
test_killswitch_loop_continues_after_socks_check
test_socks_detect_returns_on_connected
test_socks_detect_fails_on_disconnected
test_tun_detect_still_uses_ip
test_socks_is_connected_returns_on_port_listening
test_socks_is_connected_fails_when_port_closed

echo ""
echo "Results: $PASS passed, $FAIL failed (killswitch SOCKS mode)"
exit $(( FAIL > 0 ? 1 : 0 ))
