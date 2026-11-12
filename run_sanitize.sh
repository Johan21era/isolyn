#!/usr/bin/env bash
# Sanitizer sweep for the whole native stack (FIX-20 infra / core-hardening
# roadmap Phase 3b).
#
#   ./run_sanitize.sh address   # ASan + UBSan: ALL 19 engine test binaries
#                               # AND the bridge suite (SmokeTest + SoakTest)
#   ./run_sanitize.sh thread    # TSan on the genuinely-threaded parts:
#                               # SmokeTest + SearchEngineCancellationTests
#
# Design notes:
#  * Mirrors run_bridge_tests.sh's compile-once/link-many pattern so the
#    expensive sanitizer instrumentation happens once per translation unit,
#    not once per test binary.
#  * -fno-sanitize-recover=all makes every UB finding a hard failure -- a
#    "recoverable" UB report that doesn't fail the suite would be theater.
#  * Security.framework linked on Darwin (same audit F-02 lesson as the
#    other scripts; EntropySource calls SecRandomCopyBytes).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MODE="${1:-address}"
CXX="${CXX:-g++}"
STD_FLAGS="-std=c++20 -Wall -Wextra -Wpedantic -g -fno-omit-frame-pointer"

case "$MODE" in
    address)
        SAN_FLAGS="-fsanitize=address,undefined -fno-sanitize-recover=all"
        ;;
    thread)
        SAN_FLAGS="-fsanitize=thread"
        ;;
    *)
        echo "usage: $0 [address|thread]" >&2
        exit 2
        ;;
esac

# FIX-27 companion (audit OA-1 verification, remediation roadmap P1): clang's
# AddressSanitizer holds freed memory in a quarantine before recycling it. At
# the DEFAULT quarantine size (~256MB) that fill-out reaches far past this
# suite's 200-cycle soak warmup, so SoakTest's post-warmup RSS-growth check
# ended up measuring THE QUARANTINE, not the program -- a ~27KB/cycle false
# alarm under macOS clang (the native-allocator truth on the same machine,
# same day: 8.4 bytes/cycle, flat checkpoints). A deliberately SMALL
# quarantine saturates INSIDE the warmup window -- which is precisely what
# the soak's warmup phase exists to absorb -- so the instrumented signal
# measures post-warmup churn again. Both directions verified live this
# session, same binary, same workload:
#   default quarantine     : 32,610 B/cycle -> [FAIL] (plateau artifact)
#   quarantine_size_mb=16  :    136 B/cycle -> [pass] (flat checkpoints)
# LeakSanitizer itself is unavailable on this platform ("detect_leaks is not
# supported"), so the independent detectors here are: the native-allocator
# soak run, and this de-confounded instrumented run.
if [ "$MODE" = "address" ]; then
    ASAN_OPTIONS="quarantine_size_mb=16"
    export ASAN_OPTIONS
fi

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
    PLATFORM_FLAGS="-framework Security"
fi

INCLUDES="-ISources/IsolynEngine/include"
BUILD_DIR="build/sanitize/$MODE"
mkdir -p "$BUILD_DIR/obj"

echo "== [$MODE] compiling engine objects once =="
ENGINE_OBJS=()
FAILED=0
for src in Sources/IsolynEngine/*.cpp; do
    name="$(basename "$src" .cpp)"
    obj="$BUILD_DIR/obj/$name.o"
    if ! $CXX $STD_FLAGS $SAN_FLAGS $INCLUDES -c "$src" -o "$obj" 2> "$BUILD_DIR/obj/$name.compile.log"; then
        echo "  *** COMPILE FAILED: $src ***"
        cat "$BUILD_DIR/obj/$name.compile.log"
        FAILED=1
    fi
    ENGINE_OBJS+=("$obj")
done

BRIDGE_OBJS=()
if [ "$MODE" = "address" ]; then
    for src in Sources/IsolynEngineBridge/IsolynBridge.cpp; do
        name="$(basename "$src" .cpp)"
        obj="$BUILD_DIR/obj/$name.o"
        if ! $CXX $STD_FLAGS $SAN_FLAGS -ISources/IsolynEngine/include -ISources/IsolynEngineBridge/include -c "$src" -o "$obj" 2> "$BUILD_DIR/obj/$name.compile.log"; then
            echo "  *** COMPILE FAILED: $src ***"
            cat "$BUILD_DIR/obj/$name.compile.log"
            FAILED=1
        fi
        BRIDGE_OBJS+=("$obj")
    done
fi

if [ "$FAILED" -ne 0 ]; then
    echo "instrumented compilation failed -- aborting"
    exit 1
fi
echo "  compiled cleanly under $SAN_FLAGS"

TOTAL_PASS=0
TOTAL_FAIL=0
EXECUTABLES=0
RUNTIME_FAILURES=""

run_one() {
    local test_file="$1"; shift
    local name="$(basename "$test_file" .cpp)"
    local exe="$BUILD_DIR/$name"
    echo "--- [$MODE] $name ---"
    if ! $CXX $STD_FLAGS $SAN_FLAGS $INCLUDES ${BRIDGE_INCLUDES:-} -pthread $PLATFORM_FLAGS -o "$exe" "$test_file" "${ENGINE_OBJS[@]}" "$@" 2> "$BUILD_DIR/$name.compile.log"; then
        echo "  *** LINK FAILED ***"
        cat "$BUILD_DIR/$name.compile.log"
        RUNTIME_FAILURES="$RUNTIME_FAILURES $name(link)"
        return
    fi
    EXECUTABLES=$((EXECUTABLES+1))
    if ! out=$(run_with_timeout 600 "$exe" 2>&1); then
        echo "$out"
        echo "  *** RUNTIME FAILURE (finding / crash / nonzero exit / timeout) ***"
        RUNTIME_FAILURES="$RUNTIME_FAILURES $name"
        TOTAL_FAIL=$((TOTAL_FAIL+1))
    else
        local pass fail
        pass=$(echo "$out" | grep -c '\[pass\]' || true)
        fail=$(echo "$out" | grep -c '\[FAIL\]' || true)
        TOTAL_PASS=$((TOTAL_PASS+pass))
        TOTAL_FAIL=$((TOTAL_FAIL+fail))
        echo "$out" | grep -E '\[FAIL\]|ERROR|runtime error|SUMMARY|all checks passed' | head -5
        echo "  $pass passed, $fail failed, sanitizer clean"
    fi
}

if [ "$MODE" = "address" ]; then
    echo
    echo "== [$MODE] engine suite: all 19 binaries under ASan+UBSan =="
    for t in Tests/IsolynEngineTests/*Tests.cpp; do
        run_one "$t"
    done
    echo
    echo "== [$MODE] bridge suite: SmokeTest + SoakTest under ASan+UBSan =="
    BRIDGE_INCLUDES="-ISources/IsolynEngineBridge/include"
    for t in Tests/IsolynEngineBridgeTests/SmokeTest.cpp Tests/IsolynEngineBridgeTests/SoakTest.cpp; do
        run_one "$t" ${BRIDGE_OBJS[@]+"${BRIDGE_OBJS[@]}"}
    done
else
    echo
    echo "== [$MODE] threaded parts only: SmokeTest + SearchEngineCancellationTests under TSan =="
    for t in Tests/IsolynEngineBridgeTests/SmokeTest.cpp Tests/IsolynEngineTests/SearchEngineCancellationTests.cpp; do
        extra=()
        if [[ "$t" == *BridgeTests* ]]; then
            BRIDGE_INCLUDES="-ISources/IsolynEngineBridge/include"
            # Bridge tests need the bridge TU instrumented too; rebuild it here.
            bobj="$BUILD_DIR/obj/IsolynBridge.tsan.o"
            if [ ! -f "$bobj" ]; then
                $CXX $STD_FLAGS $SAN_FLAGS -ISources/IsolynEngine/include -ISources/IsolynEngineBridge/include -c Sources/IsolynEngineBridge/IsolynBridge.cpp -o "$bobj" 2>/dev/null || true
            fi
            extra+=("$bobj")
        else
            BRIDGE_INCLUDES=""
        fi
        run_one "$t" ${extra[@]+"${extra[@]}"}
    done
fi

echo
echo "================================================"
echo "[$MODE] Executables run: $EXECUTABLES"
echo "[$MODE] TOTAL CHECKS PASSED: $TOTAL_PASS"
echo "[$MODE] TOTAL CHECKS FAILED: $TOTAL_FAIL"
echo "[$MODE] Runtime failures: $([ -z "$RUNTIME_FAILURES" ] && echo none || echo "$RUNTIME_FAILURES")"
echo "================================================"

[ "$TOTAL_FAIL" -eq 0 ] && [ -z "$RUNTIME_FAILURES" ]
