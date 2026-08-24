#!/usr/bin/env bash
# Compiles Sources/IsolynEngine + Sources/IsolynEngineBridge ONCE into
# reusable .o files, then links every Tests/IsolynEngineBridgeTests/*.cpp
# against them individually. Deliberately not recompiling the engine per
# test file, unlike the original run_tests.sh -- see docs/BRIDGE_TESTING.md.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CXX="${CXX:-g++}"
STD_FLAGS="-std=c++20 -Wall -Wextra -Wpedantic"
# Portable timeout: macOS lacks GNU coreutils' timeout(1); fall back to an
# unguarded direct run there so local dev still works (CI images can install
# coreutils to regain the hang guard).
run_with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}

PLATFORM_FLAGS=""
if [ "$(uname)" = "Darwin" ]; then
    # FIX (audit F-02): SecRandomCopyBytes requires Security.framework at link time on Apple platforms.
    PLATFORM_FLAGS="-framework Security"
fi
INCLUDES="-ISources/IsolynEngine/include -ISources/IsolynEngineBridge/include"
BUILD_DIR="build/bridge"
mkdir -p "$BUILD_DIR/obj"

echo "== compiling engine + bridge once =="
OBJS=()
FAILED=0
for src in Sources/IsolynEngine/*.cpp Sources/IsolynEngineBridge/IsolynBridge.cpp; do
    name="$(basename "$src" .cpp)"
    obj="$BUILD_DIR/obj/$name.o"
    if ! $CXX $STD_FLAGS $INCLUDES -c "$src" -o "$obj" 2> "$BUILD_DIR/obj/$name.compile.log"; then
        echo "  *** COMPILE FAILED: $src ***"
        cat "$BUILD_DIR/obj/$name.compile.log"
        FAILED=1
    fi
    OBJS+=("$obj")
done
if [ "$FAILED" -ne 0 ]; then
    echo "engine/bridge compilation failed -- aborting before running any tests"
    exit 1
fi
echo "  compiled $(echo "${OBJS[@]}" | wc -w) object files cleanly"

echo
echo "== linking + running each bridge test =="
TOTAL_PASS=0
TOTAL_FAIL=0
EXECUTABLES=0
COMPILE_FAILURES=0
RUNTIME_FAILURES=""

for test_file in Tests/IsolynEngineBridgeTests/*.cpp; do
    [ -e "$test_file" ] || continue
    case "$(basename "$test_file")" in
        Fuzz*.cpp) continue ;; # libFuzzer harnesses have their own main() via -fsanitize=fuzzer -- see run_bridge_fuzz.sh
    esac
    name="$(basename "$test_file" .cpp)"
    exe="$BUILD_DIR/$name"
    echo "--- $name ---"
    if ! $CXX $STD_FLAGS $INCLUDES -pthread $PLATFORM_FLAGS -o "$exe" "$test_file" "${OBJS[@]}" 2> "$BUILD_DIR/$name.compile.log"; then
        echo "  *** COMPILE FAILED ***"
        cat "$BUILD_DIR/$name.compile.log"
        COMPILE_FAILURES=$((COMPILE_FAILURES+1))
        continue
    fi
    EXECUTABLES=$((EXECUTABLES+1))
    if ! out=$(run_with_timeout 60 "$exe" 2>&1); then
        echo "$out"
        echo "  *** RUNTIME FAILURE (nonzero exit or timeout) ***"
        RUNTIME_FAILURES="$RUNTIME_FAILURES $name"
    else
        pass=$(echo "$out" | grep -c '\[pass\]' || true)
        fail=$(echo "$out" | grep -c '\[FAIL\]' || true)
        TOTAL_PASS=$((TOTAL_PASS+pass))
        TOTAL_FAIL=$((TOTAL_FAIL+fail))
        echo "$out" | grep -E '\[FAIL\]|\[info\]|all checks passed|check\(s\) failed'
        echo "  $pass passed, $fail failed"
    fi
done

echo
echo "================================================"
echo "Executables run: $EXECUTABLES"
echo "TOTAL CHECKS PASSED: $TOTAL_PASS"
echo "TOTAL CHECKS FAILED: $TOTAL_FAIL"
echo "Compile failures: $([ $COMPILE_FAILURES -eq 0 ] && echo none || echo $COMPILE_FAILURES)"
echo "Runtime failures: $([ -z "$RUNTIME_FAILURES" ] && echo none || echo "$RUNTIME_FAILURES")"
echo "================================================"

[ "$TOTAL_FAIL" -eq 0 ] && [ "$COMPILE_FAILURES" -eq 0 ] && [ -z "$RUNTIME_FAILURES" ]
