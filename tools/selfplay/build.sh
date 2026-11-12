#!/bin/bash
# Build the self-play scaffold against the real engine. macOS-only, like Isolyn.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/tools/selfplay/build"
CXX="${CXX:-c++}"

mkdir -p "$OUT"

"$CXX" -std=c++20 -O2 \
  -I"$ROOT/Sources/IsolynEngine/include" \
  "$ROOT/tools/selfplay/main.cpp" \
  "$ROOT"/Sources/IsolynEngine/*.cpp \
  -framework Security \
  -o "$OUT/selfplay"

echo "built $OUT/selfplay"
