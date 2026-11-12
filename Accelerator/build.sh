#!/usr/bin/env bash
# Standalone Metal accelerator build and parity test.
#
# This intentionally does not use SPM: SPM does not build .mm/.metal files
# cleanly for this project yet. The runtime compiles the MSL source, so the
# missing command-line metallib tool is not required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Accelerator/build"
CXX="${CXX:-clang++}"

mkdir -p "$OUT"

"$CXX" -std=c++20 -O2 -fobjc-arc \
  -I"$ROOT/Accelerator/include" \
  -I"$ROOT/Accelerator/src" \
  -I"$ROOT/Sources/IsolynEngine/include" \
  -I"$ROOT/Tests/IsolynEngineTests" \
  "$ROOT/Accelerator/tests/AcceleratorTests.mm" \
  "$ROOT/Accelerator/src/CpuBackend.cpp" \
  "$ROOT/Accelerator/src/EvaluationBatch.cpp" \
  "$ROOT/Accelerator/src/PositionBatch.cpp" \
  "$ROOT/Accelerator/src/MetalAccelerator.mm" \
  "$ROOT"/Sources/IsolynEngine/*.cpp \
  -framework Metal \
  -framework Foundation \
  -framework Security \
  -o "$OUT/accelerator_tests"

echo "built $OUT/accelerator_tests"
exec "$OUT/accelerator_tests"
