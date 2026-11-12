#!/bin/bash
# Build the focused Isolyn CPU microbenchmark against the real engine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build"
CXX="${CXX:-c++}"

mkdir -p "$OUT"

"$CXX" -std=c++20 -O2 \
  -I"$ROOT/Sources/IsolynEngine/include" \
  "$ROOT/tools/bench/main.cpp" \
  "$ROOT"/Sources/IsolynEngine/*.cpp \
  -framework Security \
  -o "$OUT/bench"

echo "built $OUT/bench"
