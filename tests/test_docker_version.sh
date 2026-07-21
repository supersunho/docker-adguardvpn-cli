#!/bin/bash
set -euo pipefail

# Test: Docker version pinning
#
# Structural tests that validate the Dockerfile consumes AGCLI_VERSION
# and verifies the installed version.
#
# Full Docker integration tests (build + version check) require
# a Docker daemon and are marked accordingly.
#
# Usage:  bash tests/test_docker_version.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# =============================================================================
# Test 1: Dockerfile declares AGCLI_VERSION as ARG
# =============================================================================

test_dockerfile_declares_agcli_version_arg() {
    local dockerfile="${PROJECT_DIR}/Dockerfile"

    if grep -q 'ARG AGCLI_VERSION' "$dockerfile"; then
        echo "  PASS: Dockerfile declares ARG AGCLI_VERSION"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile missing ARG AGCLI_VERSION"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 2: Dockerfile uses AGCLI_VERSION in install
# =============================================================================

test_dockerfile_uses_agcli_version() {
    # shellcheck disable=SC2016
    local dockerfile="${PROJECT_DIR}/Dockerfile"

    # shellcheck disable=SC2016
    if grep -q '\${AGCLI_VERSION}' "$dockerfile" || grep -q '$AGCLI_VERSION' "$dockerfile"; then
        echo "  PASS: Dockerfile references AGCLI_VERSION in install path"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile does not use AGCLI_VERSION"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 3: Dockerfile verifies installed version
# =============================================================================

test_dockerfile_verifies_version() {
    local dockerfile="${PROJECT_DIR}/Dockerfile"

    if grep -q 'adguardvpn-cli --version' "$dockerfile"; then
        echo "  PASS: Dockerfile verifies installed version"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Dockerfile missing version verification"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 4: Workflow passes exact version to Docker build-args
# =============================================================================

test_workflow_passes_exact_version() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    if grep -q 'source_version_exact' "$workflow" && grep -q 'AGCLI_VERSION' "$workflow"; then
        echo "  PASS: Workflow passes source_version_exact as build-arg"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Workflow missing version build-arg"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Docker Version Pinning Tests"
echo "=========================================="
echo ""

test_dockerfile_declares_agcli_version_arg
echo ""
test_dockerfile_uses_agcli_version
echo ""
test_dockerfile_verifies_version
echo ""
test_workflow_passes_exact_version
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
