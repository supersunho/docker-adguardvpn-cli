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
    ## Normalize the status before matching so the caller's `nocasematch`
    ## shell option is not changed as a side effect.
    local _re='(^|[^[:alpha:]])connected([^[:alpha:]]|$)'
    local status_lower
    status_lower=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')
    if [[ $status_lower =~ $_re ]]; then
        log DEBUG "VPN is connected"
        return 0
    fi

    log DEBUG "VPN is not connected"
    return 1
}
