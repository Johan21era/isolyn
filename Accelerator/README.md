# IsolynV2.0 Metal Accelerator

**Status:** real batch-evaluation backend, 2026-11-11. The generic linear
kernel and the compact `EvaluationEngine` kernel both compile at runtime and
pass CPU/GPU parity tests on Apple M3. The backend is **not yet wired into
`SearchEngine`**, and it is deliberately outside the SPM target.

## Ambition

This is a first-class GPU compute backend for IsolynV2.0, not a token Metal
checkbox. The target is a measured strength and throughput increase from
batched evaluation and parallel determinizations, with the CPU engine remaining
the reference implementation and fallback.

## Why this shape

A recursive, pointer-shaped search tree is a poor direct GPU port. The viable
decomposition is:

1. **Batched leaf evaluation** — independent positions in one dispatch.
2. **Parallel root determinizations** — many sampled worlds at once.
3. **GPU-resident frontier search** — only after 1 and 2 are correct and fast.

This implementation covers the first building block: a real compact-position
evaluator, not a search-tree port.

## Architecture

```text
C++ SearchEngine / EvaluationEngine
        │
        ▼
Accelerator/include/IsolynAccelerator.hpp   stable C++ contract
        │
        ├── CPU reference: Accelerator/src/CpuBackend.cpp
        └── MetalBackend.mm (Objective-C++)
                │
                ├── generic weighted-feature kernel
                └── compact EvaluationEngine kernel
                        │
                        └── runtime-compiled shader source
```

The host encodes concrete, already-determinized state into a compact
`PositionRow`: four hand bitmasks, chain ends, current player, mode, closed
state, closer, and closed-round scores. The GPU computes the same eight
`EvaluationEngine` components as C++, including terminal and closed handling.
The generic `BatchView` path remains available for already-weighted component
rows.

The accelerator never generates moves, validates legality, scores rounds, or
chooses moves. It returns evaluation totals; C++ owns every decision.

## Build and run

```bash
./Accelerator/build.sh
```

The build is standalone Objective-C++ because SPM does not build this
`.mm`/runtime-MSL path cleanly today. The runtime compiles the embedded MSL via
`newLibraryWithSource:`; the installed command-line Metal toolchain currently
cannot emit a `metallib`, so no offline shader packaging step is required.

## Correctness gates

- CPU/GPU parity for the generic feature contract.
- Compact-position parity against `EvaluationEngine` for 1v1, 1v1v1, 2v2,
  closed positions, terminal wins, empty chains, equal chain ends, and one-tile
  immediate threats.
- Malformed and oversized batches fail closed.
- No Metal pipeline or device returns `nullptr`/`false`; callers use CPU.
- Deterministic move selection remains C++-owned.

## Measured throughput

On the development Apple M3, warmed median throughput from the standalone
harness measured approximately:

```text
batch      CPU positions/s   Metal compact positions/s
1,024      ~17M              ~4.3-5.2M
4,096      ~17M              ~17.3-18.6M
16,384     ~17M              ~62-66M
65,536     ~17M              ~162-170M
host encode                   ~43-45M positions/s
```

The compact kernel now reuses persistent shared `MTLBuffer`s, uses a 28-entry
tile-geometry lookup table, and accepts batches up to 65,536 positions. The
latest kernel also uses seven precomputed face masks: mobility/threat checks
become two `popcount` operations, and pip control reuses mobility. The 10-run
65K median is **168.7M positions/s** (full 148-172M/s range); 16K is ~63.8M/s.
The max-size kernel is ~9.8-10.3x the CPU evaluator; host encoding is now the
end-to-end bottleneck (~34M positions/s including one dispatch).

A 65K run moves about 4.4MB of input/output in roughly 0.4ms, so the kernel is
not bandwidth-bound. Dispatch/completion has a ~200us floor, and the
synchronous `waitUntilCompleted` path prevents host/GPU overlap.

These are batch-evaluator numbers from the standalone harness, not a search
speedup or a strength claim. The next step is batching real search leaves and
measuring time-to-depth and ladder strength.

## Files

- `include/IsolynAccelerator.hpp` — stable C++ contract.
- `include/IsolynEvaluationBatch.hpp` — weighted-component encoder.
- `include/IsolynPositionBatch.hpp` — compact-position encoder.
- `src/MetalAccelerator.mm` — runtime shader compilation and dispatch.
- `src/CpuBackend.cpp` — deterministic linear CPU reference.
- `src/EvaluationBatch.cpp`, `src/PositionBatch.cpp` — host encoders.
- `shaders/evaluation.metal` — canonical MSL reference.
- `tests/AcceleratorTests.mm` — parity, fallback, and benchmark harness.
- `../docs/subsystems/ACCELERATOR.md` — architecture and phase gates.

## Non-goals

- Game rules in Metal.
- A second scoring implementation.
- Replacing the CPU engine before parity and search integration are proven.
- Adding a GPU requirement to the app.
