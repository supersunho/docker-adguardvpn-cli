#!/bin/bash
set -euo pipefail

# Test: Configuration documentation drift
#
# Validates that:
#   - scripts/generate-dotenv.sh produces .env.example byte-for-byte
#   - No deprecated variable names exist in docs or .env.example
#   - ADGUARD_SHOW_LOG_LEVEL and ADGUARD_MAX_WAIT_TIME are documented
#   - Backup artifacts are removed
#   - .gitignore covers *.bak and *.bak2
#
# Usage:  bash tests/test_config_docs.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# =============================================================================
# Test 1: generate-dotenv.sh output matches .env.example byte-for-byte
# =============================================================================

test_dotenv_generated_exact() {
    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2064  # intentional: expand tmpfile now (local var)
    trap "rm -f '${tmpfile}'" RETURN

    if ! command -v diff &>/dev/null; then
        echo "  SKIP: diff not available"
        PASS=$((PASS + 1))
        return
    fi

    bash "${PROJECT_DIR}/scripts/generate-dotenv.sh" > "$tmpfile" 2>/dev/null

    if diff "$tmpfile" "${PROJECT_DIR}/.env.example" >/dev/null 2>&1; then
        echo "  PASS: generate-dotenv.sh output matches .env.example byte-for-byte"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: .env.example is out of sync with schema (run scripts/generate-dotenv.sh > .env.example)"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 2: No ADGUARD_LOG_LEVEL (old name) in README or .env.example
# =============================================================================

test_no_deprecated_log_level() {
    local found=0

    if grep -q 'ADGUARD_LOG_LEVEL' "${PROJECT_DIR}/README.md" 2>/dev/null; then
        echo "  FAIL: README.md still references ADGUARD_LOG_LEVEL (should be ADGUARD_SHOW_LOG_LEVEL)"
        found=1
    fi

    if grep -q 'ADGUARD_LOG_LEVEL' "${PROJECT_DIR}/.env.example" 2>/dev/null; then
        echo "  FAIL: .env.example still references ADGUARD_LOG_LEVEL (should be ADGUARD_SHOW_LOG_LEVEL)"
        found=1
    fi

    if [ "$found" -eq 0 ]; then
        echo "  PASS: No deprecated ADGUARD_LOG_LEVEL in docs"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + found))
    fi
}

# =============================================================================
# Test 3: No ADGUARD_DEBUG_LOGGING in README or .env.example
# =============================================================================

test_no_deprecated_debug_logging() {
    local found=0

    if grep -q 'ADGUARD_DEBUG_LOGGING' "${PROJECT_DIR}/README.md" 2>/dev/null; then
        echo "  FAIL: README.md still references ADGUARD_DEBUG_LOGGING"
        found=1
    fi

    if grep -q 'ADGUARD_DEBUG_LOGGING' "${PROJECT_DIR}/.env.example" 2>/dev/null; then
        echo "  FAIL: .env.example still references ADGUARD_DEBUG_LOGGING"
        found=1
    fi

    if [ "$found" -eq 0 ]; then
        echo "  PASS: No deprecated ADGUARD_DEBUG_LOGGING in docs"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + found))
    fi
}

# =============================================================================
# Test 4: ADGUARD_SHOW_LOG_LEVEL is documented in README
# =============================================================================

test_show_log_level_documented() {
    if grep -q 'ADGUARD_SHOW_LOG_LEVEL' "${PROJECT_DIR}/README.md" 2>/dev/null; then
        echo "  PASS: ADGUARD_SHOW_LOG_LEVEL is documented in README"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ADGUARD_SHOW_LOG_LEVEL missing from README"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 5: ADGUARD_MAX_WAIT_TIME is documented in README and .env.example
# =============================================================================

test_max_wait_time_documented() {
    local found_readme=false
    local found_dotenv=false

    if grep -q 'ADGUARD_MAX_WAIT_TIME' "${PROJECT_DIR}/README.md" 2>/dev/null; then
        found_readme=true
    fi

    if grep -q 'ADGUARD_MAX_WAIT_TIME' "${PROJECT_DIR}/.env.example" 2>/dev/null; then
        found_dotenv=true
    fi

    if [ "$found_readme" = true ] && [ "$found_dotenv" = true ]; then
        echo "  PASS: ADGUARD_MAX_WAIT_TIME is in README and .env.example"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ADGUARD_MAX_WAIT_TIME missing from $([ $found_readme = false ] && echo 'README ')$([ $found_dotenv = false ] && echo '.env.example')"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 6: No PUID/PGID in .env.example (build-time only)
# =============================================================================

test_no_puid_pgid_in_dotenv() {
    local found=0

    if grep -q '^PUID=' "${PROJECT_DIR}/.env.example" 2>/dev/null; then
        echo "  FAIL: .env.example contains PUID (should be build-time only)"
        found=1
    fi

    if grep -q '^PGID=' "${PROJECT_DIR}/.env.example" 2>/dev/null; then
        echo "  FAIL: .env.example contains PGID (should be build-time only)"
        found=1
    fi

    if [ "$found" -eq 0 ]; then
        echo "  PASS: No PUID/PGID in .env.example"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + found))
    fi
}

# =============================================================================
# Test 7: Backup files are removed
# =============================================================================

test_backup_files_removed() {
    local found=0

    if [ -f "${PROJECT_DIR}/scripts/lib/killswitch_detector.sh.bak" ]; then
        echo "  FAIL: killswitch_detector.sh.bak still exists"
        found=1
    fi

    if [ -f "${PROJECT_DIR}/scripts/lib/killswitch_detector.sh.bak2" ]; then
        echo "  FAIL: killswitch_detector.sh.bak2 still exists"
        found=1
    fi

    if [ "$found" -eq 0 ]; then
        echo "  PASS: Backup files (.bak) have been removed"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + found))
    fi
}

# =============================================================================
# Test 8: .gitignore covers *.bak and *.bak2
# =============================================================================

test_gitignore_covers_backups() {
    local gitignore="${PROJECT_DIR}/.gitignore"

    if grep -q '^\*\.bak$' "$gitignore" 2>/dev/null && grep -q '^\*\.bak2$' "$gitignore" 2>/dev/null; then
        echo "  PASS: .gitignore covers *.bak and *.bak2"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: .gitignore missing *.bak or *.bak2 entries"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# Test 9: PUID/PGID removed from config schema
# =============================================================================

test_puid_pgid_not_in_schema() {
    local config="${PROJECT_DIR}/scripts/lib/config.sh"

    if grep -q '_config_add "PUID"' "$config" 2>/dev/null; then
        echo "  FAIL: PUID still in config schema (should be Docker build-arg only)"
        FAIL=$((FAIL + 1))
    elif grep -q '_config_add "PGID"' "$config" 2>/dev/null; then
        echo "  FAIL: PGID still in config schema (should be Docker build-arg only)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: PUID/PGID removed from config schema"
        PASS=$((PASS + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

echo "=========================================="
echo " Config Documentation Drift Tests"
echo "=========================================="
echo ""

test_dotenv_generated_exact
echo ""
test_no_deprecated_log_level
echo ""
test_no_deprecated_debug_logging
echo ""
test_show_log_level_documented
echo ""
test_max_wait_time_documented
echo ""
test_no_puid_pgid_in_dotenv
echo ""
test_backup_files_removed
echo ""
test_gitignore_covers_backups
echo ""
test_puid_pgid_not_in_schema
echo ""

echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
