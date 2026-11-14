#!/usr/bin/env bash
# Local CI -- the same jobs .github/workflows/ci.yml runs, in the same order,
# on this machine.
#
# GitHub Actions cannot execute on this repository at the moment (the account's
# billing is in arrears, so jobs fail before a runner is assigned). Until that
# is resolved, this script is the authoritative runner. It is NOT a substitute
# for CI when CI is alive: it proves the tree is consistent, not that the hosted
# workflow is.
#
# Every step's full output is kept in build/ci-local/<name>.log; only the line
# that decides the verdict is printed, so a receipt can quote it verbatim.
#
# Usage:  ./scripts/ci/local.sh            # stop-at-nothing, report all steps
#         ./scripts/ci/local.sh --fast     # skip the two long suites
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

LOG_DIR="build/ci-local"
mkdir -p "$LOG_DIR"

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

FAILED=()
PASSED=0

step() {
    local name="$1" label="$2" summary_cmd="$3"
    shift 3
    printf '=== %-10s %s\n' "$name" "$label"
    "$@" > "$LOG_DIR/$name.log" 2>&1
    local code=$?
    local line
    line="$(eval "$summary_cmd" 2>/dev/null | tail -1)"
    if [ "$code" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        printf '    PASS  %s\n' "${line:-ok}"
    else
        FAILED+=("$name")
        printf '    FAIL  %s\n' "${line:-exit $code}"
        printf '    log:  %s/%s.log\n' "$LOG_DIR" "$name"
    fi
}

step rules   "rulebook: every rule names real code and a real assertion" \
             "grep RESULT $LOG_DIR/rules.log" \
             python3 scripts/rules_audit.py

step docs    "documentation gate: links, paths, status, register, figures" \
             "grep RESULT $LOG_DIR/docs.log" \
             python3 scripts/docs_audit.py

step labtest "offline lab + cloud verifier tests" \
             "grep -E 'Ran [0-9]+ tests|OK|FAILED' $LOG_DIR/labtest.log | tail -1" \
             env PYTHONPATH=lab/src python3 -m unittest discover -s lab/tests

step build   "swift package build" \
             "grep -E 'Build complete|error:' $LOG_DIR/build.log" \
             swift build

if [ "$FAST" -eq 0 ]; then
    step swifttest "swift test suite" \
         "grep -E 'Executed [0-9]+ tests, with' $LOG_DIR/swifttest.log" \
         swift test

    step engine  "engine suite (C++ harness)" \
         "grep -E 'TOTAL CHECKS (PASSED|FAILED)|Compile failures|Runtime failures' $LOG_DIR/engine.log | tr '\n' ' '" \
         ./scripts/ci/test_engine.sh

    step bridge  "bridge suite (SmokeTest + SoakTest)" \
         "grep -E 'TOTAL CHECKS (PASSED|FAILED)|Compile failures|Runtime failures' $LOG_DIR/bridge.log | tr '\n' ' '" \
         ./scripts/ci/test_bridge.sh
else
    printf '=== skipped    swift test, engine suite, bridge suite (--fast)\n'
fi

echo
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "LOCAL CI: PASS — $PASSED step(s), 0 failed"
    exit 0
fi
echo "LOCAL CI: FAIL — ${#FAILED[@]} step(s): ${FAILED[*]}"
exit 1
