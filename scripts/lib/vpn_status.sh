#!/bin/bash
## =============================================================================
## Provides a function to check whether the AdGuard VPN CLI reports
## the tunnel as connected.  The check is intentionally tolerant of
## output drift: the previous `Connected.*mode` regex broke whenever the
## daemon emitted a status line without the literal word "mode" (localized
## builds, output changes between minor versions, etc.).  The new regex
## anchors on the bare word `Connected` with a case-insensitive, word-
## boundary match expressed via POSIX character classes -- compatible with
## both bash `[[ =~ ]]` and `grep -E`.
## =============================================================================

check_adguard_vpn_status() {
    if ! command -v adguardvpn-cli >/dev/null 2>&1; then
        log ERROR "adguardvpn-cli not found"
        return 1
    fi

    local status
    status=$(adguardvpn-cli status 2>/dev/null) || true

    ## Word-boundary match via POSIX character classes (avoids GNU-only \b).
    ## Case-insensitive to tolerate localized output ("connected", "CONNECTED").
    local _re='(^|[^[:alpha:]])Connected([^[:alpha:]]|$)'
    local _was_nocasematch
    case "$-" in *"i"*) _was_nocasematch="set";; *) _was_nocasematch="unset";; esac
    shopt -s nocasematch
    if [[ $status =~ $_re ]]; then
        shopt -u nocasematch 2>/dev/null || true
        log DEBUG "VPN is connected"
        return 0
    fi
    shopt -u nocasematch 2>/dev/null || true

    log DEBUG "VPN is not connected"
    return 1
}
