#!/bin/bash
#
# AdGuard VPN -- .env.example generator
#
# Reads the config schema from lib/config.sh and writes
# a complete .env.example file with all variables, types,
# defaults, and descriptions.
#
# Usage:
#   scripts/generate-dotenv.sh > .env.example

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export HOME="${HOME:-/home/appuser}"

# Source config schema directly from local path
_CONFIG_KEYS=()
for _module in logging.sh config.sh; do
    _path="${SCRIPT_DIR}/lib/${_module}"
    if [ -f "$_path" ]; then
        source "$_path"
    fi
done

# Generate the dotenv content to stdout
cat << 'HEADER'
# AdGuard VPN CLI — Environment Configuration
#
# Copy this file to .env and adjust values for your setup.
#
#   cp .env.example .env
#
# NOTE: Authentication is now web-based (OAuth device code flow).
# Run the container and follow the URL printed in the logs to
# authenticate in your browser.
#
HEADER

config_generate_dotenv
