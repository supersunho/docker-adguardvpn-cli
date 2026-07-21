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
# Legacy compatibility — no-op
# =============================================================================
#
# The log() function in lib/logging.sh already handles both modern
# (log INFO "message") and legacy (log "message") calling conventions
# natively.  No wrapper needed here — callers that source this file
# get the correct behaviour directly.
