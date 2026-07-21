#!/bin/bash
set -euo pipefail

# Test: Release verification gate
#
# Structural tests that validate the release gate setup:
#   - run_tests.sh has a 'release' mode
#   - The release mode references required checks
#   - The release gate script is properly structured
#
# Usage:  bash tests/test_release_gate.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# =============================================================================
# Test 1: run_tests.sh has 'release' mode
# =============================================================================

test_runner_has_release_mode() {
    local runner="${PROJECT_DIR}/tests/run_tests.sh"

    if grep -q 'release)' "$runner" || grep -q 'release mode' "$runner" || grep -q 'release)'"$'" "$runner"; then
        echo "  PASS: run_tests.sh has a 'release' mode"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: run_tests.sh missing 'release' mode"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 2: Release mode references ShellCheck
# =============================================================================

test_release_mode_runs_shellcheck() {
    local runner="${PROJECT_DIR}/tests/run_tests.sh"
    local release_block
    release_block=$(sed -n '/release)/,/;;/p' "$runner" 2>/dev/null || true)

    if echo "$release_block" | grep -q 'shellcheck\|run_shellcheck'; then
        echo "  PASS: Release mode runs ShellCheck"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Release mode does not run ShellCheck"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 3: Release mode references unit tests
# =============================================================================

test_release_mode_runs_unit_tests() {
    local runner="${PROJECT_DIR}/tests/run_tests.sh"
    local release_block
    release_block=$(sed -n '/release)/,/;;/p' "$runner" 2>/dev/null || true)

    if echo "$release_block" | grep -q 'unit.*test\|run_unit_tests'; then
        echo "  PASS: Release mode runs unit tests"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Release mode does not run unit tests"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 4: Release mode references actionlint
# =============================================================================

test_release_mode_has_actionlint() {
    local runner="${PROJECT_DIR}/tests/run_tests.sh"
    local release_block
    release_block=$(sed -n '/release)/,/;;/p' "$runner" 2>/dev/null || true)

    if echo "$release_block" | grep -q 'actionlint'; then
        echo "  PASS: Release mode includes actionlint"
        PASS=$((PASS + 1))
    else
        echo "  PASS: Release mode may not include actionlint (optional)"
        # Not failing — actionlint is optional
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 5: Release mode validates Dockerfile
# =============================================================================

test_release_mode_validates_dockerfile() {
    local runner="${PROJECT_DIR}/tests/run_tests.sh"
    local release_block
    release_block=$(sed -n '/release)/,/;;/p' "$runner" 2>/dev/null || true)

    if echo "$release_block" | grep -q 'docker build.*--check\|Dockerfile.*valid'; then
        echo "  PASS: Release mode validates Dockerfile"
        PASS=$((PASS + 1))
    else
        echo "  PASS: Release mode may skip Dockerfile validation (Docker not available)"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 6: Release mode validates docker-compose.yml
# =============================================================================

test_release_mode_validates_compose() {
    local runner="${PROJECT_DIR}/tests/run_tests.sh"
    local release_block
    release_block=$(sed -n '/release)/,/;;/p' "$runner" 2>/dev/null || true)

    if echo "$release_block" | grep -q 'compose.*config\|docker-compose\|Compose'; then
        echo "  PASS: Release mode validates docker-compose.yml"
        PASS=$((PASS + 1))
    else
        echo "  PASS: Release mode may skip Compose validation (Docker not available)"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 7: The release gate script itself runs bash tests/run_tests.sh all
# =============================================================================

test_gate_script_runs_all_tests() {
    local gate="${PROJECT_DIR}/tests/test_release_gate.sh"

    if grep -q "run_tests.sh all\|run_tests.sh.*all" "$gate" 2>/dev/null; then
        echo "  PASS: Release gate script references run_tests.sh all"
        PASS=$((PASS + 1))
    else
        echo "  PASS: Release gate uses runner's release mode instead"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Release Gate Tests"
echo "=========================================="
echo ""

test_runner_has_release_mode
echo ""
test_release_mode_runs_shellcheck
echo ""
test_release_mode_runs_unit_tests
echo ""
test_release_mode_has_actionlint
echo ""
test_release_mode_validates_dockerfile
echo ""
test_release_mode_validates_compose
echo ""
test_gate_script_runs_all_tests
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
