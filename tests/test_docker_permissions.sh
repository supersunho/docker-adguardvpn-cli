#!/bin/bash
set -euo pipefail

# Test: Docker data directory permissions
#
# These are structural/static tests that validate the source code
# implements the correct permission checks. Full Docker integration
# tests (id -u == 1001, unwritable bind mount behavior) require
# a Docker daemon and are marked accordingly.
#
# Usage:  bash tests/test_docker_permissions.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# =============================================================================
# Test 1: docker-entrypoint.sh contains the fail-fast writable check
# =============================================================================

test_entrypoint_has_writable_check() {
    local entrypoint="${PROJECT_DIR}/scripts/docker-entrypoint.sh"

    # Must have exit 78 for unwritable data directory
    if grep -q 'exit 78' "$entrypoint"; then
        echo "  PASS: docker-entrypoint.sh contains exit 78 for unwritable data dir"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: docker-entrypoint.sh missing exit 78 for unwritable data dir"
        FAIL=$((FAIL + 1))
    fi

    # Must contain the chown hint
    if grep -q 'chown' "$entrypoint"; then
        echo "  PASS: docker-entrypoint.sh contains chown hint"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: docker-entrypoint.sh missing chown hint"
        FAIL=$((FAIL + 1))
    fi

    # Must use log_force for the error (visible even when SHOW_LOG=false)
    if grep -q 'log_force ERROR.*Data directory' "$entrypoint"; then
        echo "  PASS: docker-entrypoint.sh uses log_force for data dir error"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: docker-entrypoint.sh missing log_force for data dir error"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 2: docker-compose.yml has no runtime PUID/PGID
# =============================================================================

test_compose_no_runtime_puid_pgid() {
    local compose="${PROJECT_DIR}/docker-compose.yml"

    # Check that PUID/PGID are NOT in the environment block
    # Check that PUID is not referenced in the environment block (without expansion)
    if grep -q 'PUID=' "$compose" 2>/dev/null; then
        echo "  FAIL: docker-compose.yml still contains PUID/PGID in environment"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: docker-compose.yml has no runtime PUID/PGID"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 3: .env.example has no PUID/PGID
# =============================================================================

 test_dotenv_has_no_puid_pgid() {
    local dotenv="${PROJECT_DIR}/.env.example"

    if grep -q '^PUID=' "$dotenv" 2>/dev/null || grep -q '^PGID=' "$dotenv" 2>/dev/null; then
        echo "  FAIL: .env.example still contains PUID/PGID"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: .env.example has no PUID/PGID entries"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 4: Dockerfile retains PUID/PGID as build args
# =============================================================================

test_dockerfile_has_build_args() {
    local dockerfile="${PROJECT_DIR}/Dockerfile"

    if grep -q 'ARG PUID=' "$dockerfile" && grep -q 'ARG PGID=' "$dockerfile"; then
        echo "  PASS: Dockerfile has PUID/PGID as build args"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile missing PUID/PGID build args"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 5: Compose ports are restricted to localhost by default
# =============================================================================

test_compose_ports_are_localhost_only() {
    local compose="${PROJECT_DIR}/docker-compose.yml"

    if grep -q '^version:' "$compose"; then
        echo "  FAIL: docker-compose.yml still declares obsolete top-level version"
        FAIL=$((FAIL + 1))
    elif grep -q '127.0.0.1:1080:1080' "$compose" && \
         grep -q '127.0.0.1:6089:6089' "$compose"; then
        echo "  PASS: Compose ports are localhost-only by default"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Compose ports are not localhost-only by default"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 6: Dockerfile installs sudoers via /etc/sudoers.d/ (hygiene + visudo gate)
# =============================================================================

test_dockerfile_uses_sudoers_d_file() {
    local dockerfile="${PROJECT_DIR}/Dockerfile"

    # The legacy pattern `echo ... >> /etc/sudoers` is forbidden because the
    # main /etc/sudoers is a single point of failure.  A dedicated file under
    # /etc/sudoers.d/ with mode 0440 and a visudo -cf build gate is the
    # supported path.
    if grep -qE '^[^#]*>>[[:space:]]*/etc/sudoers([[:space:]]|$)' "$dockerfile"; then
        echo "  FAIL: Dockerfile still appends to /etc/sudoers directly"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Dockerfile does not append to /etc/sudoers"
        PASS=$((PASS + 1))
    fi

    if grep -q '/etc/sudoers.d/adguardvpn-cli' "$dockerfile"; then
        echo "  PASS: Dockerfile installs /etc/sudoers.d/adguardvpn-cli"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile missing /etc/sudoers.d/adguardvpn-cli install"
        FAIL=$((FAIL + 1))
    fi

    if grep -q 'chmod 0440 /etc/sudoers.d/adguardvpn-cli' "$dockerfile"; then
        echo "  PASS: Dockerfile pins sudoers file to mode 0440"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile missing chmod 0440 on sudoers file"
        FAIL=$((FAIL + 1))
    fi

    if grep -q 'visudo -cf /etc/sudoers.d/adguardvpn-cli' "$dockerfile"; then
        echo "  PASS: Dockerfile validates sudoers with visudo -cf"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile missing visudo -cf build gate"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 7: docker-compose.yml retains NET_ADMIN for persistent identity
# =============================================================================

test_compose_keeps_net_admin_capability() {
    local compose="${PROJECT_DIR}/docker-compose.yml"

    if grep -qE 'NET_ADMIN' "$compose"; then
        echo "  PASS: docker-compose.yml retains NET_ADMIN for ip link set"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: docker-compose.yml lost NET_ADMIN capability"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Docker Permissions Tests"
echo "=========================================="
echo ""

test_entrypoint_has_writable_check
echo ""
test_compose_no_runtime_puid_pgid
echo ""
test_dotenv_has_no_puid_pgid
echo ""
test_dockerfile_has_build_args
echo ""
test_compose_ports_are_localhost_only
echo ""
test_dockerfile_uses_sudoers_d_file
echo ""
test_compose_keeps_net_admin_capability
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
