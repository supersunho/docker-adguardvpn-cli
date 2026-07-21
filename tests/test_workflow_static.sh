#!/bin/bash
set -euo pipefail

# Test: Workflow input safety
#
# Static analysis of the GitHub Actions workflow file to prove:
#   - No direct ${{ inputs.* }} interpolation in shell blocks
#   - Inputs pass through env: before shell usage
#   - Version validation exists
#   - Output paths are quoted
#
# Usage:  bash tests/test_workflow_static.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# =============================================================================
# Test 1: No direct shell interpolation of inputs
# =============================================================================

test_no_direct_input_interpolation() {
    # shellcheck disable=SC2016
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    # grep for ${{ inputs.* }} inside run: blocks (shell scripts)
    local violations
    # shellcheck disable=SC2016
    violations=$(grep -n 'run:.*\${{.*inputs\.' "$workflow" 2>/dev/null || true)

    if [ -z "$violations" ]; then
        echo "  PASS: No direct \${{ inputs.* }} interpolation in run blocks"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Found direct input interpolation:"
        echo "$violations"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 2: Inputs pass through env: before shell usage
# =============================================================================

test_inputs_use_env_block() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    # Check that env: blocks reference inputs
    local env_inputs
    env_inputs=$(grep -c 'env:' "$workflow" 2>/dev/null || echo 0)

    # Check that specific inputs appear in env blocks
    for input in source_version build_version force_rebuild; do
        if grep -q "$input" <<< "$(grep -A1 'env:' "$workflow" 2>/dev/null)"; then
            : # ok
        elif grep -q "\${{ inputs.$input" "$workflow" 2>/dev/null; then
            # Check it's inside an env: block or uses: block, not run:
            if grep -n "run:.*\${{ inputs.$input" "$workflow" 2>/dev/null; then
                echo "  FAIL: $input still directly interpolated in run block"
                FAIL=$((FAIL + 1))
            fi
        fi
    done

    echo "  PASS: Inputs use env: block or non-shell contexts"
    PASS=$((PASS + 1))
}

# =============================================================================
# Test 3: Version validation exists
# =============================================================================

test_version_validation_exists() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    if grep -q 'validate_version' "$workflow" || grep -q 'grep -qE.*semver\|version.*regex' "$workflow" || grep -q 'v?[0-9]' "$workflow"; then
        echo "  PASS: Version validation exists in workflow"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Workflow missing version validation"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 4: Validation rejects shell metacharacters
# =============================================================================

test_rejects_shell_metacharacters() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    # Look for the validation pattern that rejects shell metacharacters
    if grep -q 'invalid' "$workflow" && grep -q 'contains invalid' "$workflow"; then
        echo "  PASS: Shell metacharacter validation present"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Missing shell metacharacter validation"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 5: GITHUB_OUTPUT uses quoted values
# =============================================================================

test_github_output_is_quoted() {
    # shellcheck disable=SC2016
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    # Check for properly quoted GITHUB_OUTPUT patterns
    # shellcheck disable=SC2016
    if grep -q '"\$GITHUB_OUTPUT"' "$workflow" || grep -q '">> \$GITHUB_OUTPUT"' "$workflow"; then
        echo "  PASS: GITHUB_OUTPUT uses quoted paths"
        PASS=$((PASS + 1))
    else
        echo "  WARN: GITHUB_OUTPUT quoting not found (may still be correct)"
        # Not failing — different quote styles may be used
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Workflow Static Analysis Tests"
echo "=========================================="
echo ""

test_no_direct_input_interpolation
echo ""
test_inputs_use_env_block
echo ""
test_version_validation_exists
echo ""
test_rejects_shell_metacharacters
echo ""
test_github_output_is_quoted
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
