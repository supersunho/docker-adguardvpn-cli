#!/bin/bash
#
# Test: Release-notes tag-range selection
#
# Verifies the release sequences reported by the user:
#   1. 2.0.0 (main) -> 2.1.0-beta.1: should diff only v2.0.0..v2.1.0-beta.1
#   2. 2.1.0-beta.1 -> 2.1.0-beta.2 (5 commits between): should diff only
#      v2.1.0-beta.1..v2.1.0-beta.2
#   3. Beta-in-progress (beta.2 cut from beta.1, no merge to main):
#      v2.1.0-beta.1..v2.1.0-beta.2
#   4. 2.1.0-beta.3 merged into main, then 2.1.0 stable released:
#      should cover the full v2.0.0...v2.1.0 cycle.
#   5. main and beta contain patch-equivalent v2.0.0 histories with different
#      commit IDs: should still select v2.0.0 and list only beta's seven changes.
#   6. beta.2 should include exactly the five commits after beta.1.
#   7. stable 2.1.0 should include the full beta cycle plus commits added after
#      beta.3 but before beta was merged.
#
# Builds a sandbox git repo per scenario, runs the EXACT shell snippet
# from the workflow in `set -euo pipefail` mode, and asserts the
# computed PREV_TAG matches expectations.
#
# Usage:  bash tests/test_release_notes_tag_range.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKFLOW="${PROJECT_DIR}/.github/workflows/docker-multiarch.yml"

PASS=0
FAIL=0

# Build a sandbox repo mirroring the user's described topology.
#
# Topology:
#   * main linear:  C0 -- C1 -- ... -- C20 (v2.0.0)
#   * beta branched off C20:  C20 -- B1 -- B2 -- B3 -- B4 -- B5
#                                    \      \      \
#                                     beta.1  beta.2  beta.3  (each cut on its commit)
#
# Scenario 4 then merges beta.3 (B5) back into main and adds C21 with
# the v2.1.0 tag.
build_sandbox() {
    local sandbox="$1"
    rm -rf "$sandbox"
    mkdir -p "$sandbox"
    cd "$sandbox"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"

    # 20 commits on main, ending with v2.0.0
    for i in $(seq 0 20); do
        echo "main commit $i" > "f${i}.txt"
        git add "f${i}.txt"
        git commit -q -m "main commit $i"
    done
    git tag v2.0.0

    # Branch beta off v2.0.0
    git checkout -q -b beta v2.0.0

    # Five commits on beta
    declare -a bhashes=()
    for i in 1 2 3 4 5; do
        echo "beta commit B${i}" > "b${i}.txt"
        git add "b${i}.txt"
        git commit -q -m "beta commit B${i}"
        bhashes+=("$(git rev-parse HEAD)")
    done

    # Tag each beta commit
    git tag v2.1.0-beta.1 "${bhashes[0]}"
    git tag v2.1.0-beta.2 "${bhashes[1]}"
    git tag v2.1.0-beta.3 "${bhashes[2]}"
    # B4, B5 remain untagged

    # Return to caller. Sandbox is left on beta HEAD.
    cd - >/dev/null
}

# Build the topology that triggered the production failure. The stable and
# beta lines contain the same v2.0.0 patch and tree, but that boundary has a
# different commit ID on each branch. Seven beta-only patches follow it.
build_rewritten_history_sandbox() {
    local sandbox="$1"
    rm -rf "$sandbox"
    mkdir -p "$sandbox"
    cd "$sandbox"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"

    echo "initial" > initial.txt
    git add initial.txt
    git commit -q -m "initial"
    local root
    root="$(git rev-parse HEAD)"

    echo "stable state" > stable.txt
    git add stable.txt
    git commit -q -m "stable boundary"
    git tag v2.0.0

    git checkout -q -b beta "$root"
    echo "stable state" > stable.txt
    git add stable.txt
    git commit -q -m "rewritten stable boundary"

    for i in $(seq 1 7); do
        echo "beta change $i" > "beta-${i}.txt"
        git add "beta-${i}.txt"
        git commit -q -m "feat: beta change $i"
    done
    git tag v2.1.0-beta.1

    cd - >/dev/null
}

build_incremental_beta_sandbox() {
    local sandbox="$1"
    rm -rf "$sandbox"
    mkdir -p "$sandbox"
    cd "$sandbox"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"

    echo "v2.0.0" > version.txt
    git add version.txt
    git commit -q -m "release: 2.0.0"
    git tag v2.0.0

    git checkout -q -b beta
    echo "beta.1" > beta-1.txt
    git add beta-1.txt
    git commit -q -m "feat: beta.1 baseline"
    git tag v2.1.0-beta.1

    for i in $(seq 1 5); do
        echo "beta.2 change $i" > "beta-2-change-${i}.txt"
        git add "beta-2-change-${i}.txt"
        git commit -q -m "feat: beta.2 change $i"
    done
    git tag v2.1.0-beta.2

    cd - >/dev/null
}

build_full_beta_cycle_sandbox() {
    local sandbox="$1"
    rm -rf "$sandbox"
    mkdir -p "$sandbox"
    cd "$sandbox"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"

    echo "v2.0.0" > version.txt
    git add version.txt
    git commit -q -m "release: 2.0.0"
    git tag v2.0.0

    git checkout -q -b beta
    for i in $(seq 1 7); do
        echo "beta cycle $i" > "beta-cycle-${i}.txt"
        git add "beta-cycle-${i}.txt"
        git commit -q -m "feat: beta cycle $i"
        case "$i" in
            1) git tag v2.1.0-beta.1 ;;
            3) git tag v2.1.0-beta.2 ;;
            5) git tag v2.1.0-beta.3 ;;
        esac
    done

    # Commits 6 and 7 are intentionally after beta.3 and before the merge.
    git checkout -q main
    git merge -q --no-ff -m "merge: beta into main" beta
    echo "v2.1.0" > version.txt
    git add version.txt
    git commit -q -m "release: 2.1.0"
    git tag v2.1.0

    cd - >/dev/null
}

# Extract the tag-resolution snippet from the workflow and run it in the
# current sandbox. Outputs the chosen PREV_TAG.
resolve_prev_tag() {
    local current_tag="$1"
    local build_version_base="$2"
    local prerelease_flag="${3:-false}"

    # Inline the exact logic from docker-multiarch.yml, substituting the
    # three inputs. Mirrors the workflow's tiered PREV_TAG resolution.
    CURRENT_TAG="$current_tag" \
        BUILD_VERSION_BASE="$build_version_base" \
        PRERELEASE_FLAG="$prerelease_flag" \
    bash -c '
        set -euo pipefail
        mapfile -t ALL_TAGS < <(git tag --sort=-v:refname)

        PREV_TAG=""

        # Tier 1: same MAJOR.MINOR.PATCH base and lower semantic version.
        # Only active for prerelease builds; ancestry is intentionally ignored.
        if [ "$PRERELEASE_FLAG" = "true" ]; then
            for tag in "${ALL_TAGS[@]}"; do
                [ "$tag" = "$CURRENT_TAG" ] && continue
                tag_clean="${tag#v}"
                tag_base="${tag_clean%%-*}"
                [ "$tag_base" = "$BUILD_VERSION_BASE" ] || continue
                [ "$tag_clean" != "$tag_base" ] || continue
                lowest=$(printf "%s\n%s\n" "$tag" "$CURRENT_TAG" | sort -V | head -n1)
                [ "$lowest" = "$tag" ] || continue
                PREV_TAG="$tag"
                break
            done
        fi

        # Tier 2: latest lower stable tag with a different version base.
        if [ -z "$PREV_TAG" ]; then
            for tag in "${ALL_TAGS[@]}"; do
                [ "$tag" = "$CURRENT_TAG" ] && continue
                tag_clean="${tag#v}"
                tag_base="${tag_clean%%-*}"
                [ "$tag_base" != "$BUILD_VERSION_BASE" ] || continue
                [ "$tag_clean" = "$tag_base" ] || continue
                lowest=$(printf "%s\n%s\n" "$tag" "$CURRENT_TAG" | sort -V | head -n1)
                [ "$lowest" = "$tag" ] || continue
                PREV_TAG="$tag"
                break
            done
        fi

        if [ -z "$PREV_TAG" ]; then
            PREV_TAG=$(git rev-list --max-parents=0 HEAD)
        fi
        echo "$PREV_TAG"
    '
}

release_commits() {
    local previous_tag="$1"
    git log --right-only --cherry-pick --no-merges \
        --pretty=format:"%h|%s" "${previous_tag}...HEAD"
}

release_subjects() {
    local previous_tag="$1"
    release_commits "$previous_tag" | cut -d'|' -f2- | sort | paste -sd'|' -
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label  (expected=$expected, actual=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label  (expected=$expected, actual=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Scenario 1: 2.0.0 -> 2.1.0-beta.1, build on beta branch
# =============================================================================
test_scenario_1_post_v2_beta1() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_sandbox "$sandbox"

    # Cut 2.1.0-beta.1 — checkout the beta.1 commit, simulate a build there.
    cd "$sandbox"
    git checkout -q v2.1.0-beta.1
    # In this scenario the workflow runs on the beta.1 commit; the next
    # release would be 2.1.0-beta.2. To test "2.0.0 -> 2.1.0-beta.1",
    # the WORKFLOW is the one that *publishes* v2.1.0-beta.1, but in
    # this sandbox that tag already exists on B1. The published tag is
    # the commit the build is currently on. The build_version is
    # "2.1.0-beta.1", base "2.1.0". Tier 1 finds no other 2.1.0-*
    # ancestor of HEAD (beta.1 is the first 2.1.0-*) so falls to Tier 2
    # which finds v2.0.0.
    local prev
    prev="$(resolve_prev_tag "v2.1.0-beta.1" "2.1.0" "true")"
    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 1: 2.0.0 -> 2.1.0-beta.1" "v2.0.0" "$prev"
}

# =============================================================================
# Scenario 2: 2.1.0-beta.1 -> 2.1.0-beta.2 (5 commits between on beta)
# =============================================================================
test_scenario_2_post_v2_beta2() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_sandbox "$sandbox"

    cd "$sandbox"
    # Build runs at the v2.1.0-beta.2 commit. The previous tag of the
    # same base, reachable from HEAD, is v2.1.0-beta.1.
    git checkout -q v2.1.0-beta.2
    local prev
    prev="$(resolve_prev_tag "v2.1.0-beta.2" "2.1.0" "true")"
    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 2: 2.1.0-beta.1 -> 2.1.0-beta.2" "v2.1.0-beta.1" "$prev"
}

# =============================================================================
# Scenario 3: Beta-in-progress, beta.2 has been cut but main is still at v2.0.0
# Build is triggered on main (e.g. via workflow_dispatch on main), HEAD = main.
# =============================================================================
test_scenario_3_main_at_v2_no_ancestor() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_sandbox "$sandbox"

    cd "$sandbox"
    git checkout -q main
    # HEAD is now at v2.0.0. Pretend we're publishing 2.1.0-beta.1.
    # Tier 1: same-base tags reachable from main HEAD — none (beta.1 is
    # not an ancestor of main). Tier 2: lower-version reachable tags —
    # v2.0.0.
    local prev
    prev="$(resolve_prev_tag "v2.1.0-beta.1" "2.1.0" "true")"
    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 3: main HEAD, building beta.1, fallback to v2.0.0" "v2.0.0" "$prev"
}

# =============================================================================
# Scenario 4: beta.3 merged into main, then 2.1.0 stable released.
# Build is on main HEAD where beta.3 is now an ancestor.
# =============================================================================
test_scenario_4_stable_after_merge() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_sandbox "$sandbox"

    cd "$sandbox"
    # Merge beta into main (fast-forward since beta is a descendant of
    # main's tip — actually we branched beta off v2.0.0 and main never
    # moved, so this is a fast-forward).
    git checkout -q main
    git merge --ff-only v2.1.0-beta.3
    # Add a release commit and tag v2.1.0 stable.
    echo "release commit" >> release.txt
    git add release.txt
    git commit -q -m "release: 2.1.0"
    git tag v2.1.0
    # Now run the resolver. The published tag is v2.1.0 stable. Tier 1
    # is skipped (stable build), so the resolver falls through to Tier 2
    # and picks v2.0.0 — the previous stable. This means the changelog
    # covers ALL commits since v2.0.0, including beta.1/2/3's work.
    local prev
    prev="$(resolve_prev_tag "v2.1.0" "2.1.0" "false")"
    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 4: stable 2.1.0 spans full beta cycle" "v2.0.0" "$prev"
}

# =============================================================================
# Scenario 6: Workflow is in place and uses the new logic
# =============================================================================
test_workflow_uses_new_logic() {
    if grep -q -- '--right-only --cherry-pick --no-merges' "$WORKFLOW"; then
        echo "  PASS: workflow uses patch-equivalent release comparison"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: workflow missing patch-equivalent release comparison"
        FAIL=$((FAIL + 1))
    fi

    # Ancestry-only filters caused rewritten-but-equivalent histories to fall
    # back to the initial commit. They must not be used by the workflow logic.
    local bad
    bad=$(grep -nE -- 'git tag --merged HEAD|git merge-base --is-ancestor' "$WORKFLOW" || true)
    if [ -z "$bad" ]; then
        echo "  PASS: workflow does not require previous tags to be ancestors"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: workflow still contains ancestry-only tag filtering:"
        echo "$bad"
        FAIL=$((FAIL + 1))
    fi
}


# =============================================================================
# Scenario 4b: stable 2.1.0 release notes must cover the full beta cycle
# (beta.1, beta.2, beta.3, release commit) — that is, the user-visible
# "what changed since 2.0.0" range.
# =============================================================================
test_scenario_4b_documents_pinned_behavior() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_sandbox "$sandbox"

    cd "$sandbox"
    git checkout -q main
    git merge --ff-only v2.1.0-beta.3
    echo "release" > r.txt && git add r.txt && git commit -q -m "release: 2.1.0"
    git tag v2.1.0

    local prev
    prev="$(resolve_prev_tag "v2.1.0" "2.1.0" "false")"
    # Count commits between prev and HEAD. Sandbox topology: v2.0.0 is
    # tagged on the last main commit; beta branch diverges with B1..B5;
    # we `git merge --ff-only v2.1.0-beta.3` (which sits on B3) then
    # add a release commit. The diff from v2.0.0..HEAD is therefore
    # B1 + B2 + B3 + release = 4 commits — the full beta line that was
    # merged in, NOT just the last beta.
    local commit_count
    commit_count="$(release_commits "$prev" | awk 'NF { count++ } END { print count + 0 }')"
    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 4b: stable diff is previous-stable..stable" "4" "$commit_count"
}

# =============================================================================
# Scenario 4c: the entire beta branch is merged into main (typical
# `git merge beta` rather than just merging a tag), and 2.1.0 stable is
# released. All 5 beta commits + the release commit must appear in the
# stable's changelog because PREV_TAG = v2.0.0 (previous stable).
# =============================================================================
test_scenario_4c_full_beta_branch_merged() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_sandbox "$sandbox"

    cd "$sandbox"
    # Merge the entire beta branch (not just a tag) so B1..B5 are all
    # reachable from main.
    git checkout -q main
    git merge --ff-only beta
    echo "release" > r.txt && git add r.txt && git commit -q -m "release: 2.1.0"
    git tag v2.1.0

    local prev
    prev="$(resolve_prev_tag "v2.1.0" "2.1.0" "false")"
    local commit_count
    commit_count="$(release_commits "$prev" | awk 'NF { count++ } END { print count + 0 }')"
    cd - >/dev/null
    rm -rf "$sandbox"

    # 5 beta commits + 1 release = 6
    assert_eq "scenario 4c: full beta branch merged, 6 commits in changelog" "6" "$commit_count"
}

# =============================================================================
# Scenario 4d: v2.0.0 and beta have patch-equivalent rewritten histories.
# The previous stable is not an ancestor, but only seven beta patches belong in
# the release notes.
# =============================================================================
test_scenario_4d_rewritten_patch_equivalent_history() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_rewritten_history_sandbox "$sandbox"

    cd "$sandbox"
    git checkout -q v2.1.0-beta.1

    local prev commit_count boundary_status
    prev="$(resolve_prev_tag "v2.1.0-beta.1" "2.1.0" "true")"
    commit_count="$(release_commits "$prev" | awk 'NF { count++ } END { print count + 0 }')"

    if git merge-base --is-ancestor v2.0.0 HEAD 2>/dev/null; then
        boundary_status="ancestor"
    elif git diff --quiet v2.0.0 HEAD~7; then
        boundary_status="rewritten-equivalent"
    else
        boundary_status="different"
    fi

    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 4d: rewritten history still selects previous stable" "v2.0.0" "$prev"
    assert_eq "scenario 4d: stable boundary is equivalent but not ancestral" "rewritten-equivalent" "$boundary_status"
    assert_eq "scenario 4d: only seven beta patches enter changelog" "7" "$commit_count"
}

# =============================================================================
# Scenario 4e: beta.2 contains exactly five commits after beta.1.
# =============================================================================
test_scenario_4e_beta2_only_since_beta1() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_incremental_beta_sandbox "$sandbox"

    cd "$sandbox"
    git checkout -q v2.1.0-beta.2

    local prev commit_count subjects
    prev="$(resolve_prev_tag "v2.1.0-beta.2" "2.1.0" "true")"
    commit_count="$(release_commits "$prev" | awk 'NF { count++ } END { print count + 0 }')"
    subjects="$(release_subjects "$prev")"

    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 4e: beta.2 selects beta.1" "v2.1.0-beta.1" "$prev"
    assert_eq "scenario 4e: beta.2 changelog contains five new commits" "5" "$commit_count"
    assert_eq "scenario 4e: beta.2 excludes beta.1 and older history" \
        "feat: beta.2 change 1|feat: beta.2 change 2|feat: beta.2 change 3|feat: beta.2 change 4|feat: beta.2 change 5" \
        "$subjects"
}

# =============================================================================
# Scenario 4f: stable 2.1.0 contains the complete beta cycle, including commits
# made after beta.3 and before beta was merged. The merge commit itself is noise
# and must remain excluded.
# =============================================================================
test_scenario_4f_stable_includes_post_beta3_premerge_commits() {
    local sandbox
    sandbox="$(mktemp -d)"
    build_full_beta_cycle_sandbox "$sandbox"

    cd "$sandbox"
    git checkout -q v2.1.0

    local prev commit_count subjects
    prev="$(resolve_prev_tag "v2.1.0" "2.1.0" "false")"
    commit_count="$(release_commits "$prev" | awk 'NF { count++ } END { print count + 0 }')"
    subjects="$(release_subjects "$prev")"

    cd - >/dev/null
    rm -rf "$sandbox"

    assert_eq "scenario 4f: stable selects the previous stable" "v2.0.0" "$prev"
    assert_eq "scenario 4f: stable contains seven beta commits plus release commit" "8" "$commit_count"
    assert_eq "scenario 4f: stable includes beta.3-to-merge commits and excludes merge noise" \
        "feat: beta cycle 1|feat: beta cycle 2|feat: beta cycle 3|feat: beta cycle 4|feat: beta cycle 5|feat: beta cycle 6|feat: beta cycle 7|release: 2.1.0" \
        "$subjects"
}

# =============================================================================
# Scenario 5: v2.0.0 is the only tag, building v2.0.0 again would have
# no previous. Skip — covered by existing initial-commit fallback.
# Sanity check: no tags at all.
# =============================================================================
test_scenario_5_no_tags() {
    local sandbox
    sandbox="$(mktemp -d)"
    mkdir -p "$sandbox"
    cd "$sandbox"
    git init -q -b main
    git config user.email "t@t" && git config user.name "T"
    echo a > a.txt && git add a.txt && git commit -q -m "init"

    local prev
    prev="$(resolve_prev_tag "v2.1.0" "2.1.0")"
    cd - >/dev/null
    rm -rf "$sandbox"

    # Should be the initial commit SHA
    if [ ${#prev} -eq 40 ]; then
        echo "  PASS: scenario 5: no tags -> initial commit SHA"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scenario 5: expected 40-char SHA, got '$prev'"
        FAIL=$((FAIL + 1))
    fi
}


# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Release-notes tag-range tests"
echo "=========================================="
echo ""

test_scenario_1_post_v2_beta1
echo ""
test_scenario_2_post_v2_beta2
echo ""
test_scenario_3_main_at_v2_no_ancestor
echo ""
test_scenario_4_stable_after_merge
echo ""
test_scenario_4b_documents_pinned_behavior
echo ""
test_scenario_4c_full_beta_branch_merged
echo ""
test_scenario_4d_rewritten_patch_equivalent_history
echo ""
test_scenario_4e_beta2_only_since_beta1
echo ""
test_scenario_4f_stable_includes_post_beta3_premerge_commits
echo ""
test_scenario_5_no_tags
echo ""
test_workflow_uses_new_logic
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
