#!/bin/bash
#
# AdGuard VPN -- Configuration schema, defaults, and validation
#
# Central registry for all environment variables.  Every variable the
# container uses is declared here with its type, default, and description.
# Validation is optional (call config_validate after sourcing).
#
# Usage:
#   source /opt/adguardvpn_cli/scripts/lib/config.sh
#   config_export_defaults   # export all defaults into the environment
#   config_validate           # check types / ranges, die on error

# =============================================================================
# Schema entry format  (associative arrays, populated below)
# =============================================================================
#
# _CONFIG_KEYS ordered list of key names
# _CONFIG_TYPE[key]       type: bool|port|positive_int|ip|dns|enum|string
# _CONFIG_DEFAULT[key]    default value
# _CONFIG_DESC[key]       human-readable description
# _CONFIG_ENUM[key]       comma-separated valid values (for type=enum)
#
# =============================================================================

# ---- Schema population ------------------------------------------------------
# (called once at import time)
_config_define_schema() {
    # ---------- Connection ----------
    _config_add "ADGUARD_CONNECTION_LOCATION" \
        "string" "JP" \
        "VPN server location code (e.g. JP, US, SG, NL)"

    _config_add "ADGUARD_CONNECTION_TYPE" \
        "enum" "TUN" \
        "Connection mode: TUN (kernel-level tunnel) or SOCKS (SOCKS5 proxy)" \
        "TUN,SOCKS"

    # ---------- SOCKS proxy ----------
    _config_add "ADGUARD_SOCKS5_USERNAME" \
        "string" "username" \
        "SOCKS5 proxy username"

    _config_add "ADGUARD_SOCKS5_PASSWORD" \
        "string" "password" \
        "SOCKS5 proxy password"

    _config_add "ADGUARD_SOCKS5_HOST" \
        "ip" "127.0.0.1" \
        "SOCKS5 proxy host address"

    _config_add "ADGUARD_SOCKS5_PORT" \
        "port" "1080" \
        "SOCKS5 proxy port"

    # ---------- Kill switch ----------
    _config_add "ADGUARD_USE_KILL_SWITCH" \
        "bool" "true" \
        "Enable kill switch to prevent IP leaks when VPN drops"

    _config_add "ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL" \
        "positive_int" "15" \
        "Kill switch check interval in seconds"

    _config_add "ADGUARD_MAX_LEAK_TOLERANCE" \
        "positive_int" "0" \
        "Number of leak detections before termination (0 = immediate)"

    _config_add "ADGUARD_LEAK_WARNING_ONLY" \
        "bool" "false" \
        "Only warn on leaks, do not terminate"

    _config_add "ADGUARD_MAX_IP_DETECTION_RETRIES" \
        "positive_int" "3" \
        "Maximum IP detection retry attempts"

    _config_add "ADGUARD_IP_DETECTION_RETRY_DELAY" \
        "positive_int" "10" \
        "Delay in seconds between IP detection retries"

    # ---------- DNS ----------
    _config_add "ADGUARD_USE_CUSTOM_DNS" \
        "bool" "true" \
        "Use a custom DNS server instead of the system default"

    _config_add "ADGUARD_CUSTOM_DNS" \
        "dns" "1.1.1.1" \
        "Custom DNS server address"

    _config_add "ADGUARD_SET_SYSTEM_DNS" \
        "bool" "false" \
        "Allow AdGuard VPN to change the system DNS configuration"

    # ---------- Privacy & reporting ----------
    _config_add "ADGUARD_SEND_REPORTS" \
        "bool" "false" \
        "Send crash reports to AdGuard"

    _config_add "ADGUARD_TELEMETRY" \
        "bool" "false" \
        "Send anonymous telemetry data"

    # ---------- Application ----------
    _config_add "ADGUARD_AUTO_UPDATE" \
        "bool" "false" \
        "Automatically update AdGuard VPN CLI on startup"

    _config_add "ADGUARD_UPDATE_CHANNEL" \
        "enum" "release" \
        "Update channel: release, beta, or dev" \
        "release,beta,dev"

    _config_add "ADGUARD_SHOW_HINTS" \
        "enum" "on" \
        "Show CLI usage hints (on/off)" \
        "on,off"

    _config_add "ADGUARD_DEBUG_LOGGING" \
        "enum" "on" \
        "Enable debug logging in AdGuard CLI (on/off)" \
        "on,off"

    _config_add "ADGUARD_SHOW_NOTIFICATIONS" \
        "enum" "on" \
        "Show desktop notifications (on/off)" \
        "on,off"

    _config_add "ADGUARD_PROTOCOL" \
        "enum" "auto" \
        "VPN protocol (auto, TCP, QUIC)" \
        "auto,TCP,QUIC"

    _config_add "ADGUARD_POST_QUANTUM" \
        "enum" "off" \
        "Post-quantum encryption (on/off)" \
        "on,off"

    _config_add "ADGUARD_TUN_ROUTING_MODE" \
        "enum" "AUTO" \
        "TUN routing mode (AUTO, TUN_ONLY, PROXY_ONLY)" \
        "AUTO,TUN_ONLY,PROXY_ONLY"

    _config_add "ADGUARD_BOUND_IF_OVERRIDE" \
        "string" "" \
        "Override bound network interface for VPN (empty = auto)"

    # ---------- User permissions ----------
    _config_add "PUID" \
        "positive_int" "1000" \
        "User ID for the container's app user"

    _config_add "PGID" \
        "positive_int" "1000" \
        "Group ID for the container's app user"

    # ---------- Logging ----------
    _config_add "ADGUARD_LOG_LEVEL" \
        "enum" "INFO" \
        "Container log level: DEBUG, INFO, WARN, ERROR" \
        "DEBUG,INFO,WARN,ERROR"
}

# ---- Internal helpers -------------------------------------------------------

declare -A _CONFIG_TYPE
declare -A _CONFIG_DEFAULT
declare -A _CONFIG_DESC
declare -A _CONFIG_ENUM
_CONFIG_KEYS=()

_config_add() {
    local key="$1" type="$2" default="$3" desc="$4" enum="${5:-}"
    _CONFIG_KEYS+=("$key")
    _CONFIG_TYPE["$key"]="$type"
    _CONFIG_DEFAULT["$key"]="$default"
    _CONFIG_DESC["$key"]="$desc"
    if [ -n "$enum" ]; then
        _CONFIG_ENUM["$key"]="$enum"
    fi
}

# ---- Initialisation (runs once at import) -----------------------------------

if [ ${#_CONFIG_KEYS[@]} -eq 0 ]; then
    _config_define_schema
fi

# ---- Public: config_export_defaults -----------------------------------------

# Export every variable with its default if not already set.
config_export_defaults() {
    local key
    for key in "${_CONFIG_KEYS[@]}"; do
        if [ -z "${!key:-}" ]; then
            export "${key}=${_CONFIG_DEFAULT[$key]}"
        fi
    done
}

# ---- Public: config_validate -------------------------------------------------

# Validate currently-set configuration.  Dies on first error.
config_validate() {
    local key val err=0

    for key in "${_CONFIG_KEYS[@]}"; do
        val="${!key:-}"
        [ -z "$val" ] && val="${_CONFIG_DEFAULT[$key]}"

        case "${_CONFIG_TYPE[$key]}" in
            bool)
                case "${val,,}" in
                    true|false) ;;
                    *) log ERROR "${key}: must be true or false (got '${val}')"; err=1 ;;
                esac
                ;;
            port)
                if ! [[ $val =~ ^[0-9]+$ ]] || [ "$val" -lt 1 ] || [ "$val" -gt 65535 ]; then
                    log ERROR "${key}: must be a port number 1-65535 (got '${val}')"
                    err=1
                fi
                ;;
            positive_int)
                if ! [[ $val =~ ^[0-9]+$ ]] || [ "$val" -lt 1 ]; then
                    log ERROR "${key}: must be a positive integer (got '${val}')"
                    err=1
                fi
                ;;
            ip)
                if ! [[ $val =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    log ERROR "${key}: must be a valid IPv4 address (got '${val}')"
                    err=1
                fi
                ;;
            dns)
                # Accept IPv4 or hostname (simple check)
                if ! [[ $val =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
                   ! [[ $val =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
                    log ERROR "${key}: must be a valid DNS server (got '${val}')"
                    err=1
                fi
                ;;
            enum)
                local valid=false IFS=,
                for e in ${_CONFIG_ENUM[$key]}; do
                    if [ "$val" = "$e" ]; then valid=true; break; fi
                done
                if [ "$valid" = false ]; then
                    log ERROR "${key}: must be one of ${_CONFIG_ENUM[$key]} (got '${val}')"
                    err=1
                fi
                ;;
            string)
                # Any value is acceptable
                ;;
            *)
                log WARN "${key}: unknown type '${_CONFIG_TYPE[$key]}'"
                ;;
        esac
    done

    return $err
}

# ---- Public: config_get (read a single config value) -------------------------

config_get() {
    local key="$1"
    local val="${!key:-}"
    echo "${val:-${_CONFIG_DEFAULT[$key]:-}}"
}

# ---- Public: config_generate_dotenv ------------------------------------------

# Print a .env file (key=value with comments) based on the schema.
config_generate_dotenv() {
    local key desc line
    local prev_category=""

    for key in "${_CONFIG_KEYS[@]}"; do
        desc="${_CONFIG_DESC[$key]}"

        # Insert a blank line + category comment on category transitions
        # (derived from the first word of the description when it changes
        #  pattern; this is a simple heuristic.)
        echo "# ${desc}"
        echo "# Type: ${_CONFIG_TYPE[$key]}  Default: ${_CONFIG_DEFAULT[$key]}"
        echo "${key}=${_CONFIG_DEFAULT[$key]}"
        echo ""
    done
}
