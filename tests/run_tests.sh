#!/bin/bash
#
# AdGuard VPN CLI — Test runner
#
# Runs all unit tests and shell checks.
#
# Usage:
#   bash tests/run_tests.sh           # run all tests
#   bash tests/run_tests.sh unit      # run unit tests only
#   bash tests/run_tests.sh shellcheck # run shellcheck only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0
FAIL=0

echo "=========================================="
echo " AdGuard VPN CLI — Test Suite"
echo "=========================================="
echo ""

# --- ShellCheck -------------------------------------------------------------

run_shellcheck() {
    if ! command -v shellcheck &>/dev/null; then
        echo "[SKIP] ShellCheck not installed (install via apt/brew: 'brew install shellcheck')"
        return 0
    fi

    echo "[CHECK] Running ShellCheck on all shell scripts..."
    local errors=0

    while IFS= read -r -d '' script; do
        if shellcheck -x -P "$(dirname "$script")" "$script" 2>&1; then
            echo "  OK: ${script}"
        else
            echo "  FAIL: ${script}"
            errors=$((errors + 1))
        fi
    done < <(find "$PROJECT_DIR" -name '*.sh' -print0)

    if [ "$errors" -eq 0 ]; then
        echo "[PASS] ShellCheck: all scripts pass"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] ShellCheck: ${errors} script(s) have issues"
        FAIL=$((FAIL + 1))
    fi
}

# --- Unit tests -------------------------------------------------------------

run_unit_tests() {
    echo "[TEST] Running unit tests (shunit2)..."
    local errors=0

    while IFS= read -r -d '' test_file; do
        local test_name
        test_name="$(basename "$test_file")"
        echo "  Running: ${test_name}..."

        if bash "$test_file" 2>&1 | tail -5; then
            echo "  PASS: ${test_name}"
        else
            echo "  FAIL: ${test_name}"
            errors=$((errors + 1))
        fi
    done < <(find "$SCRIPT_DIR" -name 'test_*.sh' -not -name 'run_tests.sh' -print0)

    if [ "$errors" -eq 0 ]; then
        echo "[PASS] All unit tests pass"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] ${errors} test(s) failed"
        FAIL=$((FAIL + 1))
    fi
}

# --- Main -------------------------------------------------------------------

case "${1:-all}" in
    unit)
        run_unit_tests
        ;;
    shellcheck)
        run_shellcheck
        ;;
    all)
        run_shellcheck
        run_unit_tests
        ;;
    *)
        echo "Usage: $0 [unit|shellcheck|all]"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

exit $(( FAIL > 0 ? 1 : 0 ))
