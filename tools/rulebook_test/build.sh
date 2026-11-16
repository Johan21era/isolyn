#!/bin/bash
# Build the rulebook exam against the real engine.
#
# Same platform handling as tools/selfplay/build.sh: macOS links Security for
# EntropySource, Linux uses getrandom(2) and must not link the framework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${ISOLYN_RULEBOOK_OUT:-$ROOT/tools/rulebook_test/build}"
CXX="${CXX:-c++}"

case "$(uname -s)" in
  Darwin) PLATFORM_FLAGS=(-framework Security) ;;
  Linux)  PLATFORM_FLAGS=() ;;
  *) echo "rulebook_test build: unsupported platform $(uname -s)" >&2; exit 2 ;;
esac

if ! command -v "$CXX" >/dev/null 2>&1; then
  echo "rulebook_test build: compiler not found: $CXX" >&2
  exit 2
fi

mkdir -p "$OUT"
"$CXX" -std=c++20 -O2 -pthread \
  -I"$ROOT/Sources/IsolynEngine/include" \
  "$ROOT/tools/rulebook_test/main.cpp" \
  "$ROOT"/Sources/IsolynEngine/*.cpp \
  "${PLATFORM_FLAGS[@]}" \
  -o "$OUT/rulebook_test"

echo "built $OUT/rulebook_test"
