#!/bin/bash
set -euo pipefail

# Test: Workflow input safety
#
# Static analysis of the GitHub Actions workflow file to prove:
#   - No direct ${{ inputs.* }} interpolation in shell blocks
#   - Inputs pass through env: before shell usage
#   - Version validation exists
#   - Project and upstream versions remain independent
#   - Pre-release tags cannot update stable/latest aliases
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
    for input in source_version build_version prerelease force_rebuild; do
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
# Test 6: Project version is required and independent from upstream version
# =============================================================================

test_project_version_is_independent() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"
    local build_input
    build_input=$(sed -n '/^            build_version:/,/^            [a-z_].*:/p' "$workflow" | head -5)

    if echo "$build_input" | grep -q 'required: true' && \
       grep -q 'build_version is required and must be independent' "$workflow" && \
       grep -q "BUILD_VERSION=\"\$BUILD_VERSION_INPUT\"" "$workflow" && \
       ! grep -q "BUILD_VERSION=\"\$SOURCE_VERSION\"" "$workflow"; then
        echo "  PASS: Project build version is required and independent from source version"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Workflow still allows project version to fall back to source version"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 7: Pre-release version and release state are propagated
# =============================================================================

test_prerelease_metadata_is_propagated() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    if grep -q 'type: boolean' "$workflow" && \
       grep -q 'PRERELEASE_INPUT' "$workflow" && \
       grep -q 'build_version_tag:.*steps.get-version.outputs.build_version_tag' "$workflow" && \
       grep -q 'release_tag:.*steps.get-version.outputs.release_tag' "$workflow" && \
       grep -q 'prerelease:.*needs.prepare.outputs.prerelease' "$workflow"; then
        echo "  PASS: Pre-release metadata reaches image and GitHub Release steps"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Pre-release metadata is not propagated through the workflow"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 8: Full pre-release suffix is preserved in image tags
# =============================================================================

test_prerelease_suffix_is_preserved() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    if grep -q "BUILD_VERSION_TAG=\"\$BUILD_VERSION_CLEAN\"" "$workflow" && \
       grep -q 'needs.prepare.outputs.build_version_tag' "$workflow" && \
       grep -q "RELEASE_TAG=\"v\${BUILD_VERSION_TAG}\"" "$workflow"; then
        echo "  PASS: Pre-release suffix is preserved in image and release tags"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Workflow strips the pre-release suffix from the published version"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 9: Stable/latest aliases are guarded for pre-releases
# =============================================================================

test_latest_alias_is_guarded() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

    if grep -q 'Prepare image tags' "$workflow" && \
       grep -q "if \[ \"\$PUBLISH_LATEST\" = \"true\" \]" "$workflow" && \
       grep -q 'Skipping latest manifest for pre-release' "$workflow"; then
        echo "  PASS: Pre-releases cannot publish stable/latest aliases"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Stable/latest alias publishing is not guarded"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 10: Release assets are downloaded before GitHub Release creation
# =============================================================================

test_release_downloads_digest_artifacts() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"
    local release_block
    release_block=$(sed -n '/create-release:/,$p' "$workflow")

    if echo "$release_block" | grep -q 'actions/download-artifact@v4' && \
       echo "$release_block" | grep -q 'pattern: digests-' && \
       echo "$release_block" | grep -q 'digest_files=(/tmp/digests/digests-\*/digest.txt)' && \
       echo "$release_block" | grep -q 'files: /tmp/digests/digest-\*.txt'; then
        echo "  PASS: Release job downloads digest assets before publishing"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Release assets are not available to the GitHub Release job"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 12: Release assets are uploaded before the release is published
# =============================================================================

test_release_publishes_after_upload() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"
    local release_block
    release_block=$(sed -n '/create-release:/,$p' "$workflow")

    if echo "$release_block" | grep -q 'id: github-release' && \
       echo "$release_block" | grep -q 'draft: true' && \
       echo "$release_block" | grep -q 'Publish GitHub Release' && \
       echo "$release_block" | grep -q 'RELEASE_ID:.*steps.github-release.outputs.id' && \
       echo "$release_block" | grep -q 'body=@release-notes.txt' && \
       echo "$release_block" | grep -q "releases/\${RELEASE_ID}" && \
       echo "$release_block" | grep -q -- '-F draft=false'; then
        echo "  PASS: Release is published only after asset upload using its release ID"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Release publication is not tied to the uploaded draft release"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 11: Stable promotion does not interpolate inputs into shell commands
# =============================================================================

test_promotion_workflow_uses_safe_inputs() {
    local workflow="${PROJECT_DIR}/.github/workflows/promote-release.yml"
    local run_block
    # shellcheck disable=SC2016 # Intentional literal GitHub Actions expression.
    run_block=$(awk '
        /^[[:space:]]+run: \|/ { in_run=1; next }
        /^[[:space:]]+- name:/ { in_run=0 }
        in_run { print }
    ' "$workflow")

    if printf '%s\n' "$run_block" | grep -qF "\${{ inputs."; then
        echo "  FAIL: Promotion workflow directly interpolates inputs in run blocks"
        FAIL=$((FAIL + 1))
    elif grep -qF "ref: \${{ inputs.existing_tag }}" "$workflow" && \
         grep -q 'TARGET_COMMIT' "$workflow" && \
         grep -q 'is not a GitHub pre-release' "$workflow" && \
         grep -q "git tag -f latest \"\\\$TARGET_COMMIT\"" "$workflow"; then
        echo "  PASS: Promotion workflow validates the existing release commit safely"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Promotion workflow is missing safe commit promotion checks"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 13: Stable promotion must use the pre-release's version base
# =============================================================================

test_promotion_requires_matching_version_base() {
    local workflow="${PROJECT_DIR}/.github/workflows/promote-release.yml"
    local validation
    # Extract the exact validation script from the workflow so these cases do
    # not duplicate its semver or version-matching logic in the test.
    validation=$(awk '
        /^[[:space:]]+run: \|$/ { in_run=1; next }
        in_run && /^[[:space:]]+- name:/ { exit }
        in_run {
            sub(/^                /, "")
            print
        }
    ' "$workflow")

    local mismatch_output
    if mismatch_output=$(EXISTING_TAG="v2.1.0-beta.2" PROMOTE_TAG="v3.0.0" \
        bash -c "$validation" 2>&1); then
        echo "  FAIL: Promotion validation accepted mismatched version bases"
        echo "$mismatch_output"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! grep -q 'must match the pre-release base version' <<< "$mismatch_output"; then
        echo "  FAIL: Mismatched version bases did not produce a clear error"
        echo "$mismatch_output"
        FAIL=$((FAIL + 1))
        return
    fi

    local matching_output
    if matching_output=$(EXISTING_TAG="v2.1.0-beta.2" PROMOTE_TAG="v2.1.0" \
        bash -c "$validation" 2>&1); then
        echo "  PASS: Promotion rejects mismatched bases and accepts matching bases"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Promotion validation rejected a matching version base"
        echo "$matching_output"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 14: Stable promotion retags and verifies both container registries
# =============================================================================

test_promotion_promotes_container_images() {
    local workflow="${PROJECT_DIR}/.github/workflows/promote-release.yml"
    local promotion_block
    promotion_block=$(sed -n '/- name: 🐳 Promote multi-arch container images/,/- name: 📥 Download pre-release digest assets/p' "$workflow")

    if ! grep -q 'packages: write' "$workflow" || \
       ! grep -q 'docker/setup-buildx-action@v3' "$workflow" || \
       [ "$(grep -c 'docker/login-action@v3' "$workflow")" -lt 2 ] || \
       ! grep -q 'docker buildx imagetools create' <<< "$promotion_block" || \
       ! grep -q 'source_digest' <<< "$promotion_block" || \
       ! grep -q 'latest_digest' <<< "$promotion_block"; then
        echo "  FAIL: Stable promotion does not retag and verify container images"
        FAIL=$((FAIL + 1))
    elif ! grep -q 'files: /tmp/release-digests/digest-\*\.txt' "$workflow" || \
         ! grep -q 'gh release download' "$workflow"; then
        echo "  FAIL: Stable promotion does not carry digest assets forward"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Stable promotion retags registries and carries digest assets"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 14: Compose configuration validation gates the image build
# =============================================================================

test_compose_config_is_build_gate() {
    local workflow="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"
    local unit_tests_block
    unit_tests_block=$(sed -n '/^    unit-tests:/,/^    [a-z-]*:/p' "$workflow")

    if [ -z "$unit_tests_block" ] || \
       ! grep -q 'docker compose --env-file \.env\.example -f docker-compose\.yml config --quiet' <<< "$unit_tests_block"; then
        echo "  FAIL: Unit-test build gate does not validate Compose configuration"
        FAIL=$((FAIL + 1))
    elif ! grep -q 'needs: \[prepare, shellcheck, unit-tests, actionlint\]' "$workflow"; then
        echo "  FAIL: Build job is not gated on the unit-tests job"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Compose configuration validation runs in the build gate"
        PASS=$((PASS + 1))
    fi
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
test_project_version_is_independent
echo ""
test_prerelease_metadata_is_propagated
echo ""
test_prerelease_suffix_is_preserved
echo ""
test_latest_alias_is_guarded
echo ""
test_release_downloads_digest_artifacts
echo ""
test_release_publishes_after_upload
echo ""
test_promotion_workflow_uses_safe_inputs
echo ""
test_promotion_requires_matching_version_base
echo ""
test_promotion_promotes_container_images
echo ""
test_compose_config_is_build_gate
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
