#!/bin/bash
#
# AdGuard VPN -- Logging utilities
#
# Provides leveled logging with ISO-8601 timestamps. All output is in English.
# Supports DEBUG, INFO, WARN, ERROR levels, controlled by ADGUARD_LOG_LEVEL.
#
# Usage:
#   source /opt/adguardvpn_cli/scripts/lib/logging.sh
#   log INFO "Container starting"
#   log DEBUG "IP detection attempt 1/3"
#   log ERROR "VPN connection failed"
#
# Default level is INFO when ADGUARD_LOG_LEVEL is unset or empty.

# =============================================================================
# Configuration
# =============================================================================

# Log level names and their numeric values (higher = more verbose)
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Mapping from name to numeric value
_log_name_to_level() {
    case "${1,,}" in
        debug) return 0 ;;
        info)  return 1 ;;
        warn)  return 2 ;;
        error) return 3 ;;
        *)     return 1 ;;  # default: INFO
    esac
}

# =============================================================================
# Core logging function
# =============================================================================

# Usage: log <LEVEL> <MESSAGE>
# LEVEL is one of DEBUG, INFO, WARN, ERROR (case-insensitive)
log() {
    local level="${1:-INFO}"
    local message="${2:-}"

    # Shift arguments so the rest is the message
    shift 2 2>/dev/null || true
    if [ $# -gt 0 ]; then
        message="$*"
    fi

    local level_upper
    level_upper="$(echo "$level" | tr '[:lower:]' '[:upper:]')"

    # Get effective log level from environment
    local configured_level="${ADGUARD_LOG_LEVEL:-INFO}"

    # Check if this message should be shown
    local msg_num
    local cfg_num
    _log_name_to_level "$level_upper"
    msg_num=$?
    _log_name_to_level "$configured_level"
    cfg_num=$?

    if [ "$msg_num" -lt "$cfg_num" ]; then
        return 0  # Message level too low, skip
    fi

    # Build timestamp
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '0000-00-00T00:00:00Z')"

    # Determine caller script name (basename without .sh)
    local caller_name
    caller_name="$(basename "${BASH_SOURCE[1]:-$0}" .sh 2>/dev/null || echo 'unknown')"

    # Print to stderr so stdout stays clean for pipe consumers
    echo "[${timestamp}] [${level_upper}] [${caller_name}] ${message}" >&2
}

# Shorthand aliases (optional, for scripting convenience)
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }
log_debug() { log DEBUG "$@"; }
