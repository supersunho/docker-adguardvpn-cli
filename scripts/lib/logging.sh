#!/bin/bash
#
# AdGuard VPN -- Logging utilities
#
# Provides leveled logging with ISO-8601 timestamps. All output is in English.
# Supports DEBUG, INFO, WARN, ERROR levels, controlled by ADGUARD_SHOW_LOG_LEVEL.
#
# Usage:
#   source /opt/adguardvpn_cli/scripts/lib/logging.sh
#   log INFO "Container starting"
#   log DEBUG "IP detection attempt 1/3"
#   log ERROR "VPN connection failed"
#
# Default level is INFO when ADGUARD_SHOW_LOG_LEVEL is unset or empty.

# =============================================================================
# Configuration
# =============================================================================

# Log level names and their numeric values (higher = more verbose)
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Mapping from name to numeric value
# NOTE: Uses echo (not return) because return codes 1/2/3 are treated as
# failures by set -e, causing the shell to abort.
_log_name_to_level() {
    local level="${1:-info}"
    case "${level,,}" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;  # default: INFO
    esac
}

# =============================================================================
# Core logging function — implementation
# =============================================================================

# Internal implementation.  Public entry point is log() below.
_log_real() {
    local level="${1:-INFO}"
    local message="${2:-}"

    # Shift arguments so the rest is the message
    shift 2 2>/dev/null || true
    if [ $# -gt 0 ]; then
        message="$*"
    fi

    local level_upper
    level_upper="$(echo "$level" | tr '[:lower:]' '[:upper:]')"

    # Get effective log level from environment with safe default
    local configured_level="${ADGUARD_SHOW_LOG_LEVEL:-INFO}"

    # Check if this message should be shown
    local msg_num
    local cfg_num
    msg_num=$(_log_name_to_level "$level_upper")
    cfg_num=$(_log_name_to_level "$configured_level")

    if [ "$msg_num" -lt "$cfg_num" ]; then
        return 0  # Message level too low, skip
    fi

    # ADGUARD_SHOW_LOG=false suppresses all container output.
    # Use safe default (true) when unset so logging works before config initialisation.
    local show_log="${ADGUARD_SHOW_LOG:-true}"
    if [ "${show_log,,}" = "false" ]; then
        return 0  # Log output disabled
    fi

    # Build timestamp
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '0000-00-00T00:00:00Z')"

    # Determine caller script name (basename without .sh)
    local caller_name
    caller_name="$(basename "${BASH_SOURCE[2]:-$0}" .sh 2>/dev/null || echo 'unknown')"

    # Print to stderr so stdout stays clean for pipe consumers
    echo "[${timestamp}] [${level_upper}] [${caller_name}] ${message}" >&2
}

# =============================================================================
# Public log function  —  handles both modern and legacy calling conventions.
# =============================================================================
#
# Modern:  log INFO "message"
#          log ERROR "Something went wrong"
# Legacy:  log "message"           (treated as INFO)
#
# The legacy-compatibility detection lives here (inside the function itself)
# so that existing scripts calling log "message" continue to work without
# a separate wrapper — and without recursion risk.

log() {
    # If the first argument is a recognised log level, pass through as-is.
    case "${1,,}" in
        debug|info|warn|error)
            _log_real "$@"
            ;;
        *)
            # Bare message without a level — treat as INFO (legacy compat).
            _log_real INFO "$@"
            ;;
    esac
}

# Shorthand aliases (optional, for scripting convenience)
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }
log_debug() { log DEBUG "$@"; }

# Force-print a message, bypassing ADGUARD_SHOW_LOG.
# Use ONLY for critical output that must always be visible (e.g. OAuth URL).
# Usage: log_force <level> <message>
log_force() {
    local level="${1:-INFO}"
    local message="${2:-}"
    shift 2 2>/dev/null || true
    [ $# -gt 0 ] && message="$*"

    local level_upper
    level_upper="$(echo "$level" | tr '[:lower:]' '[:upper:]')"

    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '0000-00-00T00:00:00Z')"

    local caller_name
    caller_name="$(basename "${BASH_SOURCE[2]:-$0}" .sh 2>/dev/null || echo 'unknown')"

    echo "[${timestamp}] [${level_upper}] [${caller_name}] ${message}" >&2
}
