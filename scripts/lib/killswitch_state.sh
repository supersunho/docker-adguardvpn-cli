#!/bin/bash
#
# AdGuard VPN -- Kill Switch State Machine
#
# A four-state machine that tracks VPN protection status:
#
#   STANDBY      -- Initial state, waiting for VPN tunnel activation
#   PROTECTED    -- VPN is active and IP is protected
#   LEAK_WARNING -- Original IP detected; leak in progress
#   TERMINATING  -- Shutdown triggered (leak persisted or VPN stopped)
#
# Transitions:
#   STANDBY      → PROTECTED     (VPN IP detected, different from real IP)
#   PROTECTED    → LEAK_WARNING  (original IP detected = potential leak)
#   PROTECTED    → TERMINATING   (VPN service stopped)
#   LEAK_WARNING → PROTECTED     (VPN IP recovered)
#   LEAK_WARNING → TERMINATING   (leak persisted beyond tolerance)
#   *            → TERMINATING   (fatal error / signal)
#
# Usage:
#   source /opt/adguardvpn_cli/scripts/lib/killswitch_state.sh
#   ks_set_state STANDBY
#   ks_get_state          # prints current state name

# =============================================================================
# State constants (exported as readonly integers for fast comparison)
# =============================================================================

readonly KS_STANDBY=0
readonly KS_PROTECTED=1
readonly KS_LEAK_WARNING=2
readonly KS_TERMINATING=3

# Human-readable names indexed by state number
_KS_STATE_NAMES=(STANDBY PROTECTED LEAK_WARNING TERMINATING)

# =============================================================================
# State variable
# =============================================================================

_KS_CURRENT_STATE=${KS_STANDBY}
_KS_LEAK_COUNT=0
_KS_HAS_BEEN_PROTECTED=false  # tracks whether we ever reached PROTECTED

# =============================================================================
# Public API
# =============================================================================

# Get the current numeric state
ks_get_state() {
    return $_KS_CURRENT_STATE
}

# Get the current state as a human-readable name
ks_get_state_name() {
    echo "${_KS_STATE_NAMES[$_KS_CURRENT_STATE]:-UNKNOWN}"
}

# Set the state to a new numeric value and log the transition
ks_set_state() {
    local new_state="$1"
    local old_state="$_KS_CURRENT_STATE"

    if [ "$new_state" = "$old_state" ]; then
        return 0  # no-op
    fi

    local old_name="${_KS_STATE_NAMES[$old_state]:-UNKNOWN}"
    local new_name="${_KS_STATE_NAMES[$new_state]:-UNKNOWN}"
    _KS_CURRENT_STATE="$new_state"

    log INFO "Kill switch state: ${old_name} -> ${new_name}"

    if [ "$new_state" = "$KS_PROTECTED" ]; then
        _KS_HAS_BEEN_PROTECTED=true
    fi
}

# Check if a transition is valid per the state machine rules.
# Returns 0 if the transition is allowed, 1 if invalid.
ks_is_valid_transition() {
    local from="$1" to="$2"

    # TERMINATING is always allowed (final state)
    if [ "$to" = "$KS_TERMINATING" ]; then
        return 0
    fi

    case "$from" in
        "$KS_STANDBY")
            [ "$to" = "$KS_PROTECTED" ] && return 0
            ;;
        "$KS_PROTECTED")
            [ "$to" = "$KS_LEAK_WARNING" ] && return 0
            [ "$to" = "$KS_TERMINATING" ] && return 0
            ;;
        "$KS_LEAK_WARNING")
            [ "$to" = "$KS_PROTECTED" ] && return 0
            [ "$to" = "$KS_TERMINATING" ] && return 0
            ;;
    esac

    return 1  # invalid transition
}

# Reset the state machine (for testing / re-initialisation)
ks_reset() {
    _KS_CURRENT_STATE=$KS_STANDBY
    _KS_LEAK_COUNT=0
    _KS_HAS_BEEN_PROTECTED=false
    log DEBUG "Kill switch state machine reset"
}

# Check if the current state is PROTECTED
ks_is_protected() {
    [ "$_KS_CURRENT_STATE" = "$KS_PROTECTED" ]
}

# Check if the current state is TERMINATING
ks_is_terminating() {
    [ "$_KS_CURRENT_STATE" = "$KS_TERMINATING" ]
}
