#!/usr/bin/env bash
# Compiles every *Tests.cpp against the full engine source set, using the
# exact flags HANDOFF.md specifies, then runs each resulting executable and
# aggregates pass/fail counts across all of them.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
mkdir -p build

ENGINE_SOURCES=(Sources/IsolynEngine/*.cpp)
INCLUDE_DIR="Sources/IsolynEngine/include"

TOTAL_PASS=0
TOTAL_FAIL=0
COMPILE_FAILURES=()
RUNTIME_FAILURES=()
EXECUTABLES_RUN=0

for test_file in Tests/IsolynEngineTests/*Tests.cpp; do
    name="$(basename "$test_file" .cpp)"
    echo "=== Compiling $name ==="
    if g++ -std=c++20 -Wall -Wextra -Wpedantic -I"$INCLUDE_DIR" -o "build/$name" "$test_file" "${ENGINE_SOURCES[@]}" 2> "build/$name.compile.log"; then
        if [ -s "build/$name.compile.log" ]; then
            echo "  --- compiled, but with warnings: ---"
            cat "build/$name.compile.log"
        else
            echo "  clean compile, zero warnings"
        fi
    else
        echo "  *** COMPILE FAILED ***"
        cat "build/$name.compile.log"
        COMPILE_FAILURES+=("$name")
        continue
    fi

    echo "=== Running $name ==="
    output="$("./build/$name" 2>&1)"
    echo "$output"
    pass_count=$(grep -c '\[pass\]' <<< "$output")
    fail_count=$(grep -c '\[FAIL\]' <<< "$output")
    TOTAL_PASS=$((TOTAL_PASS + pass_count))
    TOTAL_FAIL=$((TOTAL_FAIL + fail_count))
    EXECUTABLES_RUN=$((EXECUTABLES_RUN + 1))
    if [ "$fail_count" -gt 0 ]; then
        RUNTIME_FAILURES+=("$name")
    fi
    echo ""
done

echo "================================================"
echo "Executables run: $EXECUTABLES_RUN"
echo "TOTAL CHECKS PASSED: $TOTAL_PASS"
echo "TOTAL CHECKS FAILED: $TOTAL_FAIL"
if [ ${#COMPILE_FAILURES[@]} -eq 0 ]; then
    echo "Compile failures: none"
else
    echo "Compile failures: ${COMPILE_FAILURES[*]}"
fi
if [ ${#RUNTIME_FAILURES[@]} -eq 0 ]; then
    echo "Runtime failures: none"
else
    echo "Runtime failures: ${RUNTIME_FAILURES[*]}"
fi
echo "================================================"
