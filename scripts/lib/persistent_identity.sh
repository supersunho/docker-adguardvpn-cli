#!/bin/bash
#
# AdGuard VPN -- opt-in persistent container network identity
#
# The module is definition-only when sourced.  persistent_identity_apply is
# called once by PID1 after DATA_DIR is writable and before any network or CLI
# startup side effect.

# Returns 0 for a valid six-octet unicast MAC.  Existing installations may
# retain a globally administered unicast value; generated values add the local
# administration bit in _persistent_identity_validate_generated_mac.
persistent_identity_validate_mac() {
    local mac="${1:-}"
    [[ "$mac" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || return 1

    local first=$((16#${mac:0:2}))
    (( (first & 1) == 0 )) || return 1
    return 0
}

_persistent_identity_validate_generated_mac() {
    local mac="${1:-}"
    persistent_identity_validate_mac "$mac" || return 1

    local first=$((16#${mac:0:2}))
    (( (first & 2) == 2 )) || return 1
    return 0
}

# Runtime path helpers.  DATA_DIR is deliberately resolved at call time.
persistent_identity_mac_file() {
    printf '%s\n' "${DATA_DIR:?}/identity/mac"
}

_persistent_identity_dir() {
    printf '%s\n' "${DATA_DIR:?}/identity"
}

# Print the first interface attached to a kernel default route.
persistent_identity_primary_interface() {
    local route_output route_line
    route_output="$(ip route show default 2>/dev/null)" || return 1

    while IFS= read -r route_line; do
        [ -n "$route_line" ] || continue
        local -a fields=()
        read -r -a fields <<< "$route_line"
        local index
        for ((index = 0; index + 1 < ${#fields[@]}; index++)); do
            if [ "${fields[$index]}" = "dev" ]; then
                local interface="${fields[$((index + 1))]}"
                if [[ "$interface" =~ ^[A-Za-z0-9_.-]+$ ]]; then
                    printf '%s\n' "$interface"
                    return 0
                fi
            fi
        done
    done <<< "$route_output"

    return 1
}

_persistent_identity_read_effective_mac() {
    local interface="$1" link_output mac
    link_output="$(ip link show dev "$interface" 2>/dev/null)" || return 1
    if [[ "$link_output" =~ link/ether[[:space:]]+([^[:space:]]+) ]]; then
        mac="${BASH_REMATCH[1],,}"
    else
        return 1
    fi

    persistent_identity_validate_mac "$mac" || return 1
    printf '%s\n' "$mac"
}

_persistent_identity_route_contains_interface() {
    local interface="$1" route_output route_line
    route_output="$(ip route show default 2>/dev/null)" || return 1

    while IFS= read -r route_line; do
        [ -n "$route_line" ] || continue
        local -a fields=()
        read -r -a fields <<< "$route_line"
        local index
        for ((index = 0; index + 1 < ${#fields[@]}; index++)); do
            if [ "${fields[$index]}" = "dev" ] && [ "${fields[$((index + 1))]}" = "$interface" ]; then
                return 0
            fi
        done
    done <<< "$route_output"

    return 1
}

_persistent_identity_state_present() {
    local root="${DATA_DIR:?}" entry name active_marker

    if [ -d "${root}/active" ]; then
        active_marker="$(find "${root}/active" -mindepth 1 -print -quit 2>/dev/null || true)"
        [ -n "$active_marker" ] && return 0
    fi

    for entry in "$root"/* "$root"/.[!.]*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name="$(basename "$entry")"
        case "$name" in
            identity|active|quarantine|cli-home|workers|.migrate-manifest|.migrate-staging)
                continue
                ;;
        esac
        return 0
    done

    return 1
}
_persistent_identity_path_has_symlink() {
    local root="$1" parent
    [[ "$root" = /* ]] || return 1
    parent="${root%/*}"
    [ -n "$parent" ] || parent="/"
    if [ -L "$root" ] || [ -L "$parent" ]; then
        return 0
    fi
    return 1
}

_persistent_identity_validate_layout() {
    local root="$1" name path
    for name in active quarantine cli-home workers .migrate-staging; do
        path="${root}/${name}"
        if [ -L "${path}" ] || { [ -e "${path}" ] && [ ! -d "${path}" ]; }; then
            return 1
        fi
    done
    for path in "${root}/cli-home/.local" "${root}/cli-home/.local/share"; do
        if [ -L "${path}" ] || { [ -e "${path}" ] && [ ! -d "${path}" ]; }; then
            return 1
        fi
    done
    path="${root}/.migrate-manifest"
    if [ -L "${path}" ] || { [ -e "${path}" ] && [ ! -f "${path}" ]; }; then
        return 1
    fi
    return 0
}


_persistent_identity_generate_mac() {
    local raw first
    raw="$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')" || return 1
    [[ "$raw" =~ ^[[:xdigit:]]{12}$ ]] || return 1

    first=$((16#${raw:0:2}))
    first=$(( (first & 252) | 2 ))
    local mac
    printf -v mac '%02x:%s:%s:%s:%s:%s' \
        "$first" "${raw:2:2}" "${raw:4:2}" "${raw:6:2}" "${raw:8:2}" "${raw:10:2}"
    _persistent_identity_validate_generated_mac "$mac" || return 1
    printf '%s\n' "${mac,,}"
}

_persistent_identity_read_file() {
    local file="$1" mac
    [ -f "$file" ] || return 1
    IFS= read -r mac < "$file" || return 1
    mac="${mac,,}"
    persistent_identity_validate_mac "$mac" || return 1
    printf '%s\n' "$mac"
}

_persistent_identity_write_file() {
    local file="$1" mac="$2" dir temp old_umask
    dir="$(dirname "$file")"
    mkdir -p "$dir" 2>/dev/null || return 1
    chmod 700 "$dir" 2>/dev/null || return 1

    old_umask="$(umask)"
    umask 077
    if ! temp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null)" || \
       ! printf '%s\n' "$mac" > "$temp"; then
        umask "$old_umask"
        [ -z "$temp" ] || rm -f "$temp" 2>/dev/null || true
        return 1
    fi
    umask "$old_umask"

    if ! chmod 600 "$temp" 2>/dev/null || ! mv -f "$temp" "$file" 2>/dev/null; then
        rm -f "$temp" 2>/dev/null || true
        return 1
    fi
    return 0
}

# PID1 runs as appuser. Keep the runtime UID non-root while using the
# passwordless sudo rule installed by the image for NET_ADMIN mutations.
_persistent_identity_set_mac() {
    local interface="$1" mac="$2"
    mac="${mac,,}"
    persistent_identity_validate_mac "$mac" || return 1
    [ "$mac" != "00:00:00:00:00:00" ] || return 1
    [ "$mac" != "ff:ff:ff:ff:ff:ff" ] || return 1
    if [ -n "${DEVICE_SLOT_BOUNDARY_LOG:-}" ]; then
        [ "$DEVICE_SLOT_BOUNDARY_LOG" = /run/device-slot-boundary.log ] || return 1
        printf '%s\n' MAC_MUTATION >>"$DEVICE_SLOT_BOUNDARY_LOG" || return 1
    fi
    sudo -n ip link set dev "$interface" address "$mac"
}

_persistent_identity_restore_mac() {
    local interface="$1" previous_mac="$2"
    _persistent_identity_set_mac "$interface" "$previous_mac" || true
}

# Initialize, apply, and verify the opt-in persistent identity.
persistent_identity_apply() {
    [ "${ADGUARD_PERSISTENT_IDENTITY:-false}" = "true" ] || return 0

    local root="${DATA_DIR:-}"
    if [ -z "$root" ] || [ "$root" = "/" ] || [ ! -d "$root" ] || [ ! -w "$root" ]; then
        log_force ERROR "Persistent identity requires a writable data directory"
        return 1
    fi
    if _persistent_identity_path_has_symlink "$root"; then
        log_force ERROR "Persistent identity data path contains a symlink"
        return 1
    fi
    if ! _persistent_identity_validate_layout "$root"; then
        log_force ERROR "Persistent identity data layout is unsafe"
        return 1
    fi

    local interface current_mac target_mac identity_file
    interface="$(persistent_identity_primary_interface 2>/dev/null)" || {
        log_force ERROR "Persistent identity could not find a default-route interface"
        return 1
    }
    current_mac="$(_persistent_identity_read_effective_mac "$interface" 2>/dev/null)" || {
        log_force ERROR "Persistent identity could not read the primary interface MAC"
        return 1
    }

    identity_file="$(persistent_identity_mac_file)"
    local identity_dir
    identity_dir="$(_persistent_identity_dir)"
    if [ -L "$identity_dir" ] || \
       { [ -e "$identity_dir" ] && [ ! -d "$identity_dir" ]; }; then
        log_force ERROR "Persistent identity directory is not a directory"
        return 1
    fi
    if ! mkdir -p "$identity_dir" 2>/dev/null || ! chmod 700 "$identity_dir" 2>/dev/null; then
        log_force ERROR "Persistent identity directory could not be secured"
        return 1
    fi
    if [ -L "$identity_file" ]; then
        log_force ERROR "Persistent identity file must not be a symlink"
        return 1
    fi
    local created=false
    if [ -e "$identity_file" ]; then
        target_mac="$(_persistent_identity_read_file "$identity_file" 2>/dev/null)" || {
            log_force ERROR "Persistent identity file is invalid"
            return 1
        }
        chmod 600 "$identity_file" 2>/dev/null || {
            log_force ERROR "Persistent identity file permissions could not be secured"
            return 1
        }
    else
        if _persistent_identity_state_present; then
            target_mac="$current_mac"
        else
            target_mac="$(_persistent_identity_generate_mac 2>/dev/null)" || {
                log_force ERROR "Persistent identity MAC generation failed"
                return 1
            }
        fi
        _persistent_identity_write_file "$identity_file" "$target_mac" || {
            log_force ERROR "Persistent identity could not be persisted"
            return 1
        }
        created=true
    fi

    local changed=false
    if [ "$current_mac" != "$target_mac" ]; then
        if ! _persistent_identity_set_mac "$interface" "$target_mac"; then
            _persistent_identity_restore_mac "$interface" "$current_mac"
            log_force ERROR "Persistent identity MAC apply failed on ${interface}"
            return 1
        fi
        changed=true
    fi

    local effective_mac
    effective_mac="$(_persistent_identity_read_effective_mac "$interface" 2>/dev/null)" || {
        [ "$changed" = true ] && _persistent_identity_restore_mac "$interface" "$current_mac"
        log_force ERROR "Persistent identity MAC verification could not read ${interface}"
        return 1
    }
    if [ "$effective_mac" != "$target_mac" ] || \
       ! _persistent_identity_route_contains_interface "$interface"; then
        [ "$changed" = true ] && _persistent_identity_restore_mac "$interface" "$current_mac"
        log_force ERROR "Persistent identity verification failed on ${interface}"
        return 1
    fi

    if [ "$created" = true ]; then
        log INFO "Persistent container identity initialized on ${interface} (${target_mac})"
    else
        log INFO "Persistent container identity verified on ${interface} (${target_mac})"
    fi
    return 0
}
