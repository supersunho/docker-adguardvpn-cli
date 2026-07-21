#!/bin/bash
#
# AdGuard VPN -- Utility function loader
#
# This file is the single entry point for all utility functions.
# It sources the modular lib/ hierarchy.
#
# Existing callers (docker-entrypoint.sh, init.sh, killswitch.sh)
# continue to work unchanged by sourcing this file.

# =============================================================================
# Library loader
# =============================================================================

_LIB_DIR="/opt/adguardvpn_cli/scripts/lib"

# Source each module in dependency order.
# logging.sh must come first since other modules use log().
# error_handling.sh should be early since it provides die/try/retry.
for _module in \
    logging.sh \
    error_handling.sh \
    network.sh \
    ip_detection.sh \
    vpn_status.sh \
    config.sh \
    killswitch_state.sh \
    killswitch_detector.sh \
    killswitch_actions.sh \
; do
    _path="${_LIB_DIR}/${_module}"
    if [ -f "$_path" ]; then
        # shellcheck source=/dev/null
        source "$_path"
    fi
done

unset _module _path _LIB_DIR

# =============================================================================
# Legacy compatibility wrappers
# =============================================================================
#
# The following aliases map the old function names from the monolith
# utils.sh onto the new modular implementations so that existing
# callers (docker-entrypoint.sh, init.sh, killswitch.sh) work
# unchanged during the transition.

# log()  --  the old signature used a single message and printed
#            "[caller] message".  The new log() in logging.sh uses
#            "[timestamp] [LEVEL] [caller] message" and always expects
#            a level as the first argument.
#
# For backward compatibility, we keep a thin wrapper that treats
# a bare message as level INFO.
_log_legacy() {
    # If the first argument looks like a level (DEBUG/INFO/WARN/ERROR
    # case-insensitive), pass through to the real log.
    case "${1,,}" in
        debug|info|warn|error)
            log "$@"
            ;;
        *)
            log INFO "$@"
            ;;
    esac
}

# Override the log function loaded from logging.sh so old-style
# single-argument calls still work.  Scripts that use the new
# two-argument form also work since we detect the level keyword.
#
# This keeps git blame clean during the transition.
log() {
    _log_legacy "$@"
}
