#!/usr/bin/env bash
# Builds Tests/IsolynEngineBridgeTests/FuzzBridge.cpp with
# clang++ -fsanitize=fuzzer,address,undefined against the real engine +
# bridge, then runs it for SECONDS (default 120) of real wall-clock fuzzing.
# See docs/BRIDGE_TESTING.md for how to read the output and for the
# specific run `docs/BRIDGE_TESTING.md` cites results from.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SECONDS_TO_RUN="${1:-120}"
BUILD_DIR="build/fuzz"
mkdir -p "$BUILD_DIR/corpus"

# Some Xcode toolchains do not ship the libFuzzer runtime for macOS
# (libclang_rt.fuzzer_osx.a). Detect and fall back to a standalone driver
# that exercises the identical LLVMFuzzerTestOneInput harness under
# ASan+UBSan with pseudo-random + mutation inputs. Less coverage-guided
# than real libFuzzer, but it keeps adversarial-input execution available
# on every Mac instead of hard-failing at link time.
STANDALONE=0
if ! echo 'int main(){return 0;}' | clang++ -x c++ -std=c++20 -fsanitize=fuzzer -o "$BUILD_DIR/libfuzzer_probe" - 2>/dev/null; then
    STANDALONE=1
    echo "libFuzzer runtime unavailable on this toolchain -- standalone driver fallback enabled"
fi

if [ "$STANDALONE" -eq 0 ]; then
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
else
    # ~2.5k execs/sec observed historically for this harness under ASan.
    ITERS=$(( SECONDS_TO_RUN * 2500 ))
    echo "== building standalone fuzz harness (clang++, ASan+UBSan) =="
    if ! clang++ -std=c++20 -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all \
        -ISources/IsolynEngine/include -ISources/IsolynEngineBridge/include \
        $( [ "$(uname)" = "Darwin" ] && echo "-framework Security" ) \
        -o "$BUILD_DIR/fuzz_standalone" \
        Tests/IsolynEngineBridgeTests/StandaloneFuzzDriver.cpp Tests/IsolynEngineBridgeTests/FuzzBridge.cpp Sources/IsolynEngineBridge/IsolynBridge.cpp Sources/IsolynEngine/*.cpp \
        2> "$BUILD_DIR/compile.log"; then
        echo "*** COMPILE FAILED ***"
        cat "$BUILD_DIR/compile.log"
        exit 1
    fi
    echo "  built ok"

    echo
    echo "== running ~${ITERS} executions (standalone fallback for ${SECONDS_TO_RUN}s budget) =="
    "$BUILD_DIR/fuzz_standalone" "$ITERS" 0xC0FFEE 2>&1 | tee "$BUILD_DIR/run.log"
fi

echo
if grep -qE "ERROR:|SUMMARY:|runtime error|AddressSanitizer|UndefinedBehaviorSanitizer" "$BUILD_DIR/run.log"; then
    echo "================================================"
    echo "FUZZING FOUND A REAL ISSUE -- see $BUILD_DIR/run.log and any crash-* artifact in $BUILD_DIR/"
    echo "================================================"
    exit 1
fi
execs=$(grep -oE '#[0-9]+' "$BUILD_DIR/run.log" | tail -1 | tr -d '#')
if [ -z "$execs" ]; then
    execs=$(grep -oE '[0-9]+ executions' "$BUILD_DIR/run.log" | tail -1 | cut -d' ' -f1)
fi
echo "================================================"
echo "Clean: no sanitizer finding, no crash, no hang across ~${execs:-?} executions in ${SECONDS_TO_RUN}s"
echo "Corpus size: $(ls "$BUILD_DIR/corpus" 2>/dev/null | wc -l) inputs saved to $BUILD_DIR/corpus"
echo "================================================"
