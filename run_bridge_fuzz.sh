#!/usr/bin/env bash
# Builds Tests/IsolynEngineBridgeTests/FuzzBridge.cpp with
# clang++ -fsanitize=fuzzer,address,undefined against the real engine +
# bridge, then runs it for SECONDS (default 120) of real wall-clock fuzzing.
# See docs/BRIDGE_TESTING.md for how to read the output and for the
# specific run this project's HANDOFF.md cites results from.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SECONDS_TO_RUN="${1:-120}"
BUILD_DIR="build/fuzz"
mkdir -p "$BUILD_DIR/corpus"

echo "== building fuzz harness (clang++, ASan+UBSan+libFuzzer) =="
if ! clang++ -std=c++20 -g -O1 -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=all \
    -ISources/IsolynEngine/include -ISources/IsolynEngineBridge/include \
    $( [ "$(uname)" = "Darwin" ] && echo "-framework Security" ) \
    -o "$BUILD_DIR/fuzz_bridge" \
    Tests/IsolynEngineBridgeTests/FuzzBridge.cpp Sources/IsolynEngineBridge/IsolynBridge.cpp Sources/IsolynEngine/*.cpp \
    2> "$BUILD_DIR/compile.log"; then
    echo "*** COMPILE FAILED ***"
    cat "$BUILD_DIR/compile.log"
    exit 1
fi
echo "  built ok"

echo
echo "== running for ${SECONDS_TO_RUN}s real wall-clock time =="
"$BUILD_DIR/fuzz_bridge" -max_total_time="$SECONDS_TO_RUN" -artifact_prefix="$BUILD_DIR/" "$BUILD_DIR/corpus" \
    2>&1 | tee "$BUILD_DIR/run.log"

echo
if grep -qE "ERROR:|SUMMARY:|runtime error|AddressSanitizer|UndefinedBehaviorSanitizer" "$BUILD_DIR/run.log"; then
    echo "================================================"
    echo "FUZZING FOUND A REAL ISSUE -- see $BUILD_DIR/run.log and any crash-* artifact in $BUILD_DIR/"
    echo "================================================"
    exit 1
fi
execs=$(grep -oE '#[0-9]+' "$BUILD_DIR/run.log" | tail -1 | tr -d '#')
echo "================================================"
echo "Clean: no sanitizer finding, no crash, no hang across ~${execs:-?} executions in ${SECONDS_TO_RUN}s"
echo "Corpus size: $(ls "$BUILD_DIR/corpus" 2>/dev/null | wc -l) inputs saved to $BUILD_DIR/corpus"
echo "================================================"
