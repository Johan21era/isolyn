#!/bin/bash
# Build the self-play scaffold against the real engine.
#
# macOS and Linux are supported. On macOS, EntropySource uses Security.framework;
# on Linux it uses getrandom(2), so the framework must not be linked there.
# Kaggle datasets are read-only, so ISOLYN_SELFPLAY_OUT lets the notebook build
# into /kaggle/working instead of trying to write beside the sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${ISOLYN_SELFPLAY_OUT:-$ROOT/tools/selfplay/build}"
CXX="${CXX:-c++}"

case "$(uname -s)" in
  Darwin)
    PLATFORM_FLAGS=(-framework Security)
    ;;
  Linux)
    PLATFORM_FLAGS=()
    ;;
  *)
    echo "selfplay build: unsupported platform $(uname -s); expected Darwin or Linux" >&2
    exit 2
    ;;
esac

if ! command -v "$CXX" >/dev/null 2>&1; then
  echo "selfplay build: compiler not found: $CXX" >&2
  exit 2
fi

mkdir -p "$OUT"

if [ "${#PLATFORM_FLAGS[@]}" -gt 0 ]; then
  "$CXX" -std=c++20 -O2 -pthread \
    -I"$ROOT/Sources/IsolynEngine/include" \
    "$ROOT/tools/selfplay/main.cpp" \
    "$ROOT"/Sources/IsolynEngine/*.cpp \
    "${PLATFORM_FLAGS[@]}" \
    -o "$OUT/selfplay"
else
  "$CXX" -std=c++20 -O2 -pthread \
    -I"$ROOT/Sources/IsolynEngine/include" \
    "$ROOT/tools/selfplay/main.cpp" \
    "$ROOT"/Sources/IsolynEngine/*.cpp \
    -o "$OUT/selfplay"
fi

echo "built $OUT/selfplay"
