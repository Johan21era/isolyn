#!/usr/bin/env bash
# Build and run the deep-tier 15-second depth probe. This is a measurement
# tool, not part of the correctness suite; it prints completed depth per
# position and deliberately makes no strength claim.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="build/depth_probe"
mkdir -p "$OUT"
FLAGS=""
if [ "$(uname)" = "Darwin" ]; then FLAGS="-framework Security"; fi

g++ -std=c++20 -O2 -pthread $FLAGS \
    -ISources/IsolynEngine/include \
    -o "$OUT/depth_probe" \
    tools/bench/depth_probe.cpp \
    Sources/IsolynEngine/*.cpp

"$OUT/depth_probe" "${1:-80}" "${2:-4}" "${3:-15000}"
"$OUT/depth_probe" "${4:-160}" "${2:-4}" "${3:-15000}"