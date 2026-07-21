#!/bin/bash
#
# AdGuard VPN -- Error handling utilities
#
# Provides robust error management patterns for shell scripts:
#
#   die()       -- Print an error message and exit
#   try()       -- Execute a command with error wrapping
#   retry()     -- Retry a command with backoff
#   setup_traps -- Install standard ERR/EXIT traps
#
# Usage:
#   source /opt/adguardvpn_cli/scripts/lib/error_handling.sh
#   setup_traps
#   die "Something went wrong" 2
#   retry 3 5 curl -fsS https://example.com

# =============================================================================
# Configuration
# =============================================================================

# A global cleanup function that scripts can override.
# Set this before calling setup_traps if custom cleanup is needed.
_CLEANUP_FN="${CLEANUP_FN:-}"

# =============================================================================
# die()  --  Print a fatal error and exit
# =============================================================================

# Usage: die [EXIT_CODE] MESSAGE
#   EXIT_CODE defaults to 1 if not provided or not a number.
die() {
    local exit_code=1
    local message=""

    if [ $# -ge 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        exit_code="$1"
        shift
    fi
    message="$*"
    [ -z "$message" ] && message="Fatal error"

    log ERROR "${message}"
    exit "$exit_code"
}

# =============================================================================
# try()  --  Execute a command with error wrapping
# =============================================================================

# Usage: try COMMAND [ARG...]
#   If the command fails, prints a warning but does NOT exit
#   (caller should check $? or use retry).
# Returns: the exit code of the command
try() {
    if [ $# -eq 0 ]; then
        log WARN "try: nothing to execute"
        return 0
    fi

    local rc=0
    "$@" || rc=$?
    if [ "$rc" -ne 0 ]; then
        log WARN "Command failed (exit ${rc}): $*"
    fi
    return $rc
}

# =============================================================================
# retry()  --  Retry a command with exponential backoff
# =============================================================================

# Usage: retry MAX_RETRIES SLEEP_BASE COMMAND [ARG...]
#   Retries the command up to MAX_RETRIES times.
#   Sleeps SLEEP_BASE seconds between attempts (doubles each retry).
# Returns: 0 on success, exit code of the last failure otherwise.
retry() {
    local max_retries="${1:?retry: max_retries required}"
    local sleep_base="${2:?retry: sleep_base required}"
    local attempt=1
    local rc=0

    shift 2

    if [ $# -eq 0 ]; then
        log WARN "retry: nothing to execute"
        return 0
    fi

    while [ "$attempt" -le "$max_retries" ]; do
        if [ "$attempt" -gt 1 ]; then
            local wait_time=$(( sleep_base * (1 << (attempt - 2)) ))
            log INFO "Retry ${attempt}/${max_retries} in ${wait_time}s..."
            sleep "$wait_time"
        fi

        log DEBUG "Executing: $* (attempt ${attempt}/${max_retries})"
        "$@" && rc=0 && break || rc=$?
        attempt=$((attempt + 1))
    done

    if [ "$rc" -ne 0 ]; then
        log ERROR "Command failed after ${max_retries} attempts: $*"
    fi
    return $rc
}

# =============================================================================
# Trap handling
# =============================================================================

# Default cleanup handler (scripts can override by setting CLEANUP_FN).
_default_cleanup() {
    local rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 143 ] && [ "$rc" -ne 130 ]; then
        log WARN "Unexpected exit (code ${rc})"
    fi
}

# Handle ERR trap: print the source location of the error.
_on_error() {
    local rc=$?
    local line="${1:-unknown}"
    local func="${FUNCNAME[1]:-main}"

    # Avoid recursive error handling
    trap '' ERR

    log ERROR "Error at line ${line} in ${func}() — exit code ${rc}"
}

# Install standard traps for ERR and EXIT.
# Usage: setup_traps
setup_traps() {
    # ERR trap with line number for debugging
    trap '_on_error $LINENO' ERR

    # EXIT trap runs _default_cleanup unless CLEANUP_FN is set
    if [ -n "$_CLEANUP_FN" ]; then
        # shellcheck disable=SC2064
        trap "$_CLEANUP_FN" EXIT
    else
        trap '_default_cleanup' EXIT
    fi

    log DEBUG "Error traps installed"
}

# =============================================================================
# strict mode helper
# =============================================================================

# Enable strict shell mode (set -euo pipefail).
# Usage: set_strict_mode
set_strict_mode() {
    set -euo pipefail
}
