#!/bin/bash
set -euo pipefail

# Test: Multi-architecture manifest publishing idempotency
#
# Static analysis of the GitHub Actions workflow to prove:
#   - Digest is exported for both build and skip paths
#   - GHCR login is unconditional (needed for digest resolution)
#   - Merge-manifests requires all 3 architectures (amd64, arm64, armv7)
#   - Digest upload is unconditional
#   - Verification steps use set -euo pipefail
#   - No || echo failure patterns in verification steps
#   - Pre-release manifests preserve the full version and skip latest
#
# Usage:  bash tests/test_manifest_workflow.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

WORKFLOW="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

# =============================================================================
# Test 1: GHCR login is unconditional (no if: condition)
# =============================================================================

test_ghcr_login_unconditional() {
    # Find the GHCR login step — it should not have an 'if:' condition
    # Extract the block around "Login to GHCR"
    local login_block
    login_block=$(sed -n '/Login to GHCR/,/uses:/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$login_block" | grep -q 'if:'; then
        echo "  FAIL: GHCR login has an if: condition (should be unconditional)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: GHCR login is unconditional"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 2: Skip-path digest resolution exists
# =============================================================================

test_skip_path_digest_resolution() {
    # Look for the digest export/resolve step that handles both build and skip
    if grep -q 'Export or resolve digest\|Resolving existing image digest' "$WORKFLOW"; then
        echo "  PASS: Skip-path digest resolution exists"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Missing skip-path digest resolution"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 3: Digest upload is unconditional
# =============================================================================

test_digest_upload_unconditional() {
    # Find the Upload digest artifact step — should not have if: build_image
    local upload_block
    upload_block=$(sed -n '/Upload digest artifact/,/retention-days/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$upload_block" | grep -q 'if:'; then
        echo "  FAIL: Digest artifact upload has an if: condition"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Digest artifact upload is unconditional"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 4: Merge-manifests requires all 3 architecture digests
# =============================================================================

test_merge_requires_all_archs() {
    # Look for the required architectures check
    if grep -q 'REQUIRED_ARCHS\|All required architectures\|Missing.*architectures' "$WORKFLOW"; then
        echo "  PASS: Merge-manifests requires all architectures"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Merge-manifests missing architecture requirement check"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 5: All three architectures (amd64, arm64, armv7) are required
# =============================================================================

test_three_architectures_required() {
    if grep -q 'amd64.*arm64.*armv7\|REQUIRED_ARCHS=' "$WORKFLOW"; then
        echo "  PASS: All three architectures (amd64, arm64, armv7) are required"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Missing explicit list of all three architectures"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 6: Build verification step uses set -euo pipefail
# =============================================================================

test_verification_uses_strict_mode() {
    # Extract the verification block
    local verify_block
    verify_block=$(sed -n '/Comprehensive container verification/,/^            - name:/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$verify_block" | grep -q 'set -euo pipefail'; then
        echo "  PASS: Build verification uses set -euo pipefail"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Build verification missing set -euo pipefail"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 7: Merge-manifest step uses set -euo pipefail
# =============================================================================

test_merge_uses_strict_mode() {
    # Extract the merge-manifest creation block
    local merge_block
    merge_block=$(sed -n '/Create multi-arch manifests/,/^            - name:/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$merge_block" | grep -q 'set -euo pipefail'; then
        echo "  PASS: Merge-manifest step uses set -euo pipefail"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Merge-manifest step missing set -euo pipefail"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 8: No || echo failure patterns in verification steps
# =============================================================================

test_no_echo_failure_pattern() {
    # Extract only the verification step (between "verification" and next step)
    local verify_block
    verify_block=$(sed -n '/Comprehensive container verification/,/^            - name:/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$verify_block" | grep -q '||.*echo.*fail'; then
        echo "  FAIL: Verification step has || echo failure pattern"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: No || echo failure patterns in verification step"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Test 9: Digest export step handles both build and skip paths
# =============================================================================

test_digest_export_handles_both_paths() {
    # The digest step should reference both build_image=true and build_image=false (or equivalent)
    local digest_block
    digest_block=$(sed -n '/Export or resolve digest/,/^            - name:/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$digest_block" | grep -q 'build_image.*true\|steps.build.outputs.digest' && \
       echo "$digest_block" | grep -q 'build_image.*false\|Resolving existing\|skip'; then
        echo "  PASS: Digest export handles both build and skip paths"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Digest export missing build or skip path handling"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 10: Merge fails if any architecture digest is missing
# =============================================================================

test_merge_fails_on_missing_arch() {
    # The merge should exit 1 when an architecture is missing
    local merge_block
    merge_block=$(sed -n '/Create multi-arch manifests/,/^            - name:/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$merge_block" | grep -q 'exit 1'; then
        echo "  PASS: Merge fails when architecture is missing"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Merge does not fail on missing architecture"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 11: Manifest version preserves pre-release suffix
# =============================================================================

test_manifest_uses_full_build_version() {
    if grep -q "VERSION=\"\${{ needs.prepare.outputs.build_version_tag }}\"" "$WORKFLOW" && \
       grep -q "ARCH_IMAGES+=(\"\${PREFIX}:\${VERSION}-\${arch}\")" "$WORKFLOW"; then
        echo "  PASS: Version manifests use the full project version"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Manifest creation does not use the full project version"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 12: Latest manifest is conditional
# =============================================================================

test_latest_manifest_is_conditional() {
    local merge_block
    merge_block=$(sed -n '/Create multi-arch manifests/,/^    # 4)/p' "$WORKFLOW" 2>/dev/null || true)

    if echo "$merge_block" | grep -q 'PUBLISH_LATEST' && \
       echo "$merge_block" | grep -q 'Skipping latest manifest for pre-release'; then
        echo "  PASS: Latest manifest is skipped for pre-releases"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Latest manifest is created unconditionally"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Manifest Publishing Workflow Tests"
echo "=========================================="
echo ""

test_ghcr_login_unconditional
echo ""
test_skip_path_digest_resolution
echo ""
test_digest_upload_unconditional
echo ""
test_merge_requires_all_archs
echo ""
test_three_architectures_required
echo ""
test_verification_uses_strict_mode
echo ""
test_merge_uses_strict_mode
echo ""
test_no_echo_failure_pattern
echo ""
test_digest_export_handles_both_paths
echo ""
test_merge_fails_on_missing_arch
echo ""
test_manifest_uses_full_build_version
echo ""
test_latest_manifest_is_conditional
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
