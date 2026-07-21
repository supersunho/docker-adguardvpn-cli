#!/bin/bash
set -euo pipefail

# Import utility functions
source /opt/adguardvpn_cli/scripts/utils.sh

# Bootstrap configuration before any side effects
config_bootstrap

setup_traps

# =============================================================================
# Configuration defaults — all provided by config_bootstrap() above
# =============================================================================

# Derive ADGUARD_DEBUG_LOGGING from SHOW_LOG_LEVEL (internal, not user-set).
# When SHOW_LOG_LEVEL=DEBUG, enable AdGuard CLI debug logging.
if [ "${ADGUARD_SHOW_LOG_LEVEL:-INFO}" = "DEBUG" ]; then
    export ADGUARD_DEBUG_LOGGING="on"
else
    export ADGUARD_DEBUG_LOGGING="off"
fi

# =============================================================================
# OAuth / Web Authentication
# =============================================================================

AUTH_FILE="${HOME}/.local/share/adguardvpn-cli/vpn.pid"

_oauth_login() {
    log_force INFO ""
    log_force INFO "=============================================="
    log_force INFO "      WEB AUTHENTICATION REQUIRED"
    log_force INFO "=============================================="
    log_force INFO ""
    log_force INFO "AdGuard VPN requires browser-based authentication."
    log_force INFO ""
    log_force INFO "The login command below will display a URL."
    log_force INFO "Open that URL in your browser, complete the"
    log_force INFO "authentication, and the process will continue"
    log_force INFO "automatically."
    log_force INFO ""
    log_force INFO "NOTE: ADGUARD_USERNAME/ADGUARD_PASSWORD are no"
    log_force INFO "longer used. Please authenticate via the URL."
    log_force INFO "=============================================="
    log_force INFO ""

    local temp_file
    temp_file="$(mktemp /tmp/adguard-login-XXXXXX 2>/dev/null)" || temp_file="/tmp/adguard-login-$$"

    adguardvpn-cli login > "$temp_file" 2>&1 &
    local login_pid=$!

    tail -f "$temp_file" 2>/dev/null &
    local tail_pid=$!

    sleep 3 &
    wait $! 2>/dev/null || true

    local timeout=1800
    local elapsed=0
    local url_printed=false
    local timed_out=false

    while kill -0 "$login_pid" 2>/dev/null; do
        if [ "$url_printed" = false ] && \
           grep -qE 'https://auth\.adguard\.io/device_code' "$temp_file" 2>/dev/null; then
            local device_url
            device_url=$(grep -oE 'https://auth\.adguard\.io/device_code\?user_code=[A-Z0-9-]+' \
                         "$temp_file" 2>/dev/null | head -1)

            log_force INFO ""
            log_force INFO "=============================================="
            log_force INFO "  OPEN THIS LINK IN YOUR BROWSER:"
            log_force INFO ""
            log_force INFO "  ${device_url}"
            log_force INFO ""
            log_force INFO "  Authenticate in your browser, then wait here."
            log_force INFO "  The container will detect the login"
            log_force INFO "  automatically and continue."
            log_force INFO "=============================================="
            log_force INFO ""

            url_printed=true
        fi

        sleep 5 &
        wait $! 2>/dev/null || true
        elapsed=$((elapsed + 5))

        if [ "$elapsed" -ge "$timeout" ]; then
            timed_out=true
            log_force WARN "Login timed out after ${timeout}s"
            kill "$login_pid" 2>/dev/null || true
            break
        fi
    done

    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    rm -f "$temp_file" 2>/dev/null || true

    local login_exit=0
    wait "$login_pid" 2>/dev/null && login_exit=$? || login_exit=$?

    if [ "$timed_out" = true ]; then
        log_force ERROR "Authentication timed out after ${timeout}s"
        return 1
    fi

    if [ "$login_exit" -ne 0 ]; then
        log_force ERROR "adguardvpn-cli login failed (exit code: ${login_exit})"
        return 1
    fi

    log_force INFO "Authentication completed successfully"
    return 0
}

# =============================================================================
# Authentication
# =============================================================================

if [ -f "$AUTH_FILE" ]; then
    log_force INFO "Authentication credentials found. Using existing session."
else
    log_force INFO "No authentication credentials found."
    if ! _oauth_login; then
        log_force ERROR "Authentication failed. Container cannot connect to VPN."
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
