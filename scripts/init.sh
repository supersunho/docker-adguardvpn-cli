#!/bin/bash
set -euo pipefail

# Import utility functions
source /opt/adguardvpn_cli/scripts/utils.sh
setup_traps

# =============================================================================
# Configuration defaults
# =============================================================================

export ADGUARD_CONNECTION_LOCATION=${ADGUARD_CONNECTION_LOCATION:-"JP"}
export ADGUARD_CONNECTION_TYPE=${ADGUARD_CONNECTION_TYPE:-"TUN"}
export ADGUARD_SOCKS5_USERNAME=${ADGUARD_SOCKS5_USERNAME:-"username"}
export ADGUARD_SOCKS5_PASSWORD=${ADGUARD_SOCKS5_PASSWORD:-"password"}
export ADGUARD_SOCKS5_HOST=${ADGUARD_SOCKS5_HOST:-"127.0.0.1"}
export ADGUARD_SOCKS5_PORT=${ADGUARD_SOCKS5_PORT:-1080}
export ADGUARD_SEND_REPORTS=${ADGUARD_SEND_REPORTS:-false}
export ADGUARD_SET_SYSTEM_DNS=${ADGUARD_SET_SYSTEM_DNS:-false}
export ADGUARD_USE_CUSTOM_DNS=${ADGUARD_USE_CUSTOM_DNS:-true}
export ADGUARD_CUSTOM_DNS=${ADGUARD_CUSTOM_DNS:-"1.1.1.1"}

# Additional configuration options
export ADGUARD_AUTO_UPDATE=${ADGUARD_AUTO_UPDATE:-false}
export ADGUARD_UPDATE_CHANNEL=${ADGUARD_UPDATE_CHANNEL:-"release"}
export ADGUARD_SHOW_HINTS=${ADGUARD_SHOW_HINTS:-"on"}
export ADGUARD_DEBUG_LOGGING=${ADGUARD_DEBUG_LOGGING:-"on"}
export ADGUARD_SHOW_NOTIFICATIONS=${ADGUARD_SHOW_NOTIFICATIONS:-"on"}
export ADGUARD_PROTOCOL=${ADGUARD_PROTOCOL:-"auto"}
export ADGUARD_POST_QUANTUM=${ADGUARD_POST_QUANTUM:-"off"}
export ADGUARD_TELEMETRY=${ADGUARD_TELEMETRY:-false}
export ADGUARD_TUN_ROUTING_MODE=${ADGUARD_TUN_ROUTING_MODE:-"AUTO"}
export ADGUARD_BOUND_IF_OVERRIDE=${ADGUARD_BOUND_IF_OVERRIDE:-""}

# =============================================================================
# OAuth / Web Authentication
# =============================================================================

AUTH_FILE="${HOME}/.local/share/adguardvpn-cli/vpn.pid"

# Wrapper around adguardvpn-cli login that detects the OAuth device code
# URL in the output and prompts the user to open it in their browser.
#
# adguardvpn-cli login is interactive in a TTY (b/s/x menu), but in a
# Docker container without a TTY it prints the device code URL and then
# periodically polls the auth server until the user completes login.
_oauth_login() {
    log INFO ""
    log INFO "=============================================="
    log INFO "      WEB AUTHENTICATION REQUIRED"
    log INFO "=============================================="
    log INFO ""
    log INFO "AdGuard VPN requires browser-based authentication."
    log INFO ""
    log INFO "The login command below will display a URL."
    log INFO "Open that URL in your browser, complete the"
    log INFO "authentication, and the process will continue"
    log INFO "automatically."
    log INFO ""
    log INFO "NOTE: ADGUARD_USERNAME/ADGUARD_PASSWORD are no"
    log INFO "longer used. Please authenticate via the URL."
    log INFO "=============================================="
    log INFO ""

    # Run login.  In a non-TTY environment (Docker) the command
    # will print the URL and then poll until authentication succeeds
    # or the user completes the flow.
    #
    # We tee the output so it appears in the container logs in
    # real time while we also capture it for URL detection.

    local temp_file
    temp_file="$(mktemp /tmp/adguard-login-XXXXXX 2>/dev/null)" || temp_file="/tmp/adguard-login-$$"

    # Run in background, tee output to both the log and the temp file
    adguardvpn-cli login 2>&1 | tee "$temp_file" &
    local login_pid=$!

    # Wait a moment for initial output, then check for URL
    sleep 3 &

    # Wait for the process with a timeout (so the trap works)
    local timeout=1800  # 30 minutes max for auth
    local elapsed=0

    while kill -0 "$login_pid" 2>/dev/null; do
        # Check for device code URL in captured output
        if grep -qE 'https://auth\.adguard\.io/device_code' "$temp_file" 2>/dev/null; then
            local device_url
            device_url=$(grep -oE 'https://auth\.adguard\.io/device_code\?user_code=[A-Z0-9-]+' "$temp_file" 2>/dev/null | head -1)

            log INFO ""
            log INFO "=============================================="
            log INFO "  OPEN THIS LINK IN YOUR BROWSER:"
            log INFO ""
            log INFO "  ${device_url}"
            log INFO ""
            log INFO "  Authenticate in your browser, then wait here."
            log INFO "  The container will detect the login"
            log INFO "  automatically and continue."
            log INFO "=============================================="
            log INFO ""

            # URL already printed; don't repeat
            > "$temp_file" 2>/dev/null || true
        fi

        sleep 5 &
        wait $!
        elapsed=$((elapsed + 5))

        if [ "$elapsed" -ge "$timeout" ]; then
            log WARN "Login timed out after ${timeout}s"
            kill "$login_pid" 2>/dev/null || true
            break
        fi
    done

    rm -f "$temp_file" 2>/dev/null || true

    # Check return status
    wait "$login_pid" 2>/dev/null || true
    local login_exit=$?

    if [ "$login_exit" -ne 0 ] && [ "$login_exit" -ne 143 ]; then
        log ERROR "adguardvpn-cli login failed (exit: ${login_exit})"
        return 1
    fi

    log INFO "Authentication completed successfully"
    return 0
}

# =============================================================================
# Authentication
# =============================================================================

if [ -f "$AUTH_FILE" ]; then
    log INFO "Authentication credentials found. Using existing session."
else
    log INFO "No authentication credentials found."
    if ! _oauth_login; then
        log ERROR "Authentication failed. Container cannot connect to VPN."
        exit 1
    fi
fi

# =============================================================================
# Auto-update
# =============================================================================

if [ "${ADGUARD_AUTO_UPDATE,,}" = "true" ]; then
    log INFO "Updating AdGuard VPN CLI..."
    adguardvpn-cli update -y
fi

# =============================================================================
# Configuration
# =============================================================================

log INFO "Configuring AdGuard VPN..."
adguardvpn-cli config set-mode "${ADGUARD_CONNECTION_TYPE,,}"

# Only clear SOCKS auth in SOCKS mode (harmless in TUN mode, but semantically correct)
if [ "${ADGUARD_CONNECTION_TYPE,,}" = "socks" ]; then
    adguardvpn-cli config clear-socks-auth
fi

adguardvpn-cli config set-update-channel "$ADGUARD_UPDATE_CHANNEL"
adguardvpn-cli config set-show-hints "$ADGUARD_SHOW_HINTS"
adguardvpn-cli config set-debug-logging "$ADGUARD_DEBUG_LOGGING"
adguardvpn-cli config set-show-notifications "$ADGUARD_SHOW_NOTIFICATIONS"
adguardvpn-cli config set-protocol "$ADGUARD_PROTOCOL"
adguardvpn-cli config set-post-quantum "$ADGUARD_POST_QUANTUM"
adguardvpn-cli config set-telemetry "$([ "${ADGUARD_TELEMETRY,,}" = true ] && echo "on" || echo "off")"
adguardvpn-cli config set-tun-routing-mode "$ADGUARD_TUN_ROUTING_MODE"

if [ -n "$ADGUARD_BOUND_IF_OVERRIDE" ] && [ "$ADGUARD_BOUND_IF_OVERRIDE" != "" ]; then
    adguardvpn-cli config set-bound-if-override "$ADGUARD_BOUND_IF_OVERRIDE"
else
    adguardvpn-cli config set-bound-if-override ""
fi

if [ "${ADGUARD_USE_CUSTOM_DNS,,}" = "true" ]; then
    adguardvpn-cli config set-dns "$ADGUARD_CUSTOM_DNS"
fi

if [ "${ADGUARD_SET_SYSTEM_DNS,,}" = false ]; then
    log INFO "Disabling system DNS changes"
    adguardvpn-cli config set-change-system-dns off
fi

if [ "${ADGUARD_SEND_REPORTS,,}" = false ]; then
    log INFO "Disabling crash reporting"
    adguardvpn-cli config set-crash-reporting off
fi

# =============================================================================
# SOCKS5 setup (only in SOCKS mode)
# =============================================================================

if [ "${ADGUARD_CONNECTION_TYPE,,}" = "socks" ]; then
    log INFO "Setting up SOCKS5 proxy credentials"
    adguardvpn-cli config set-socks-username "$ADGUARD_SOCKS5_USERNAME"
    adguardvpn-cli config set-socks-password "$ADGUARD_SOCKS5_PASSWORD"
    adguardvpn-cli config set-socks-host "$ADGUARD_SOCKS5_HOST"
    adguardvpn-cli config set-socks-port "$ADGUARD_SOCKS5_PORT"
fi

# =============================================================================
# Connect
# =============================================================================

log INFO "Connecting to VPN (location: ${ADGUARD_CONNECTION_LOCATION})..."
adguardvpn-cli connect -l "$ADGUARD_CONNECTION_LOCATION"

log INFO "VPN connection established"
adguardvpn-cli status
