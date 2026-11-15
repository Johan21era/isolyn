#!/usr/bin/env bash
# Compiles and runs the randomized whole-game rules conformance soak.
#
#   ./scripts/ci/rules_soak.sh 1000000
#
# The unit suites prove each rule in isolation. This one drives complete
# games through the same MatchController/MoveGenerator/GameState path the
# app uses, asserting tile conservation, legal-move validity, forced-draw
# completeness and both end conditions after every action. It is opt-in
# because a million games is a nightly confidence run, not an edit loop.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GAMES="${1:-1000000}"
SEED="${2:-12648430}"
BUILD_DIR="build/conformance"
mkdir -p "$BUILD_DIR"

PLATFORM_FLAGS=""
if [ "$(uname)" = "Darwin" ]; then
    PLATFORM_FLAGS="-framework Security"
fi

echo "== compiling rules conformance soak =="
g++ -std=c++20 -O2 -Wall -Wextra -Wpedantic $PLATFORM_FLAGS \
    -ISources/IsolynEngine/include \
    -o "$BUILD_DIR/rules_soak" \
    tools/conformance/rules_soak.cpp \
    Sources/IsolynEngine/*.cpp

echo "== running =="
"$BUILD_DIR/rules_soak" "$GAMES" "$SEED"