# Metal Accelerator

**Status:** real standalone batch-evaluation backend, 2026-11-11. The generic
linear kernel and the compact `EvaluationEngine` kernel compile at runtime and
pass CPU/GPU parity tests on Apple M3. Search integration is the next phase; the
backend is not yet linked into the SPM target or allowed to influence moves.

## Decision

The accelerator is a **first-class GPU compute backend**, not a small
optimization. The goal is a large strength increase on Apple Silicon through
batched evaluation and parallel search across determinizations.

The CPU engine remains the reference implementation and the fallback. The GPU
must earn its place through measured speed **and** measured playing strength.

## Why a naive GPU port would fail

`SearchEngine` is recursive and mutates a `GameState` tree in place. That shape
is hostile to GPU execution: divergent branches, pointer-heavy state, and
per-node synchronization would erase any throughput gain.

The viable decomposition is:

1. **Batched leaf evaluation.** Many independent positions → one dispatch →
   per-player evaluation values.
2. **Parallel root determinizations.** Sample many hidden worlds and evaluate
   them together.
3. **GPU-resident frontier search.** Only after 1 and 2 are correct and fast.

This implementation covers the first building block and defines the contract
needed for step 2. It is not a search-tree port.

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
                        └── runtime-compiled MSL source
```

### Contracts

`BatchView` is the generic linear contract: row-major weighted feature rows in,
one value per position/player out.

`PositionRow` is the compact evaluator contract. The host encodes:

- four hand bitmasks,
- chain left/right ends,
- current player and mode,
- closed flag, closer, and closed-round participant scores.

The GPU computes mobility, blocking, expected hand value, closing opportunity,
immediate win threat, pip control, tempo, and 2v2 team support, then writes one
total per player. The host does not run `EvaluationEngine` on this path.

### Backend rules

- The accelerator never generates moves, validates legality, or scores rounds.
- It returns evaluation totals to C++; the C++ search makes every decision.
- It fails closed: no device, malformed batch, oversized batch, or kernel error
  returns `nullptr`/`false` so the caller can use the CPU path.
- Equal scores must still resolve identically in C++; GPU scheduling never
  chooses a move.

## Integration plan

1. **Scaffold.** C++ interface, Metal capability probe, placeholder shader,
   ADR/docs. Complete.
2. **CPU parity harness.** Generic and compact parity, malformed/fail-closed
   tests, closed/terminal coverage. Complete for the standalone evaluator.
3. **Search leaf batching.** Collect independent leaf positions, encode them,
   dispatch one or more batches, and feed totals back into the CPU search.
   Pending.
4. **Parallel determinizations.** Batch independent worlds; measure
   time-to-depth and ladder strength. Pending.
5. **GPU-resident frontier.** Conditional on 3–4 proving a real gain.

SPM still does not build this `.mm`/runtime-MSL path cleanly for this project.
`Accelerator/build.sh` is the current executable path; the Xcode/Objective-C++
target remains a packaging task.

## Build and run

```bash
./Accelerator/build.sh
```

The installed command-line Metal tool cannot emit a `metallib` in this
environment:

```text
error: cannot execute tool 'metal' due to missing Metal Toolchain
```

The backend deliberately avoids that tool by compiling its MSL source at
runtime with `newLibraryWithSource:`. The standalone build links Metal and
Foundation directly and runs the parity/benchmark harness.

## Correctness gates

Exercised by `Accelerator/tests/AcceleratorTests.mm`:

- generic CPU/GPU parity on synthetic feature rows;
- compact parity against `EvaluationEngine` for 1v1, 1v1v1, 2v2, closed
  positions, terminal wins, empty chains, equal chain ends, and one-tile
  immediate threats;
- terminal winner/loser scoring;
- null, empty, malformed, and oversized batches fail closed;
- the 65,536-position maximum is accepted with CPU-matching output, while
  the 65,537-position request is rejected;
- CPU reference remains deterministic and independent of Metal.

Before the accelerator can influence move selection:

- leaf-batch search integration must preserve deterministic tie-breaking;
- hidden-information safety must be demonstrated: the accelerator sees only
  the concrete state rows the caller supplies;
- a fixed-time-control ladder must show a strength or time-to-depth gain, not
  just a faster microbenchmark.

## Measured throughput

Development Apple M3, standalone batch evaluator, repeated 1v1 positions,
warmed median of 32 dispatches per size (ranges cover repeated runs):

```text
batch      CPU positions/s   Metal positions/s   Metal us/call
1,024      ~17M              ~4.3-5.2M           ~196-215
4,096      ~17M              ~17.3-18.6M         ~221-237
16,384     ~17M              ~62-66M             ~247-260
65,536     ~17M              ~196-209M           ~313-334
host encode                   ~55M positions/s
```

The compact kernel now reuses persistent shared `MTLBuffer`s, uses a
28-entry tile-geometry lookup table, and accepts up to 65,536 positions. The
latest kernel additionally precomputes seven face masks: mobility and
immediate-threat checks use two `popcount` operations instead of scanning all
28 tiles, and pip control reuses the already-computed mobility value. The final
three-run 65K range is 196-209M positions/s (313-334us); an earlier 10-run
median was 168.7M/s, showing normal GPU clock/scheduler variance. The 16K
median is 63.8M/s.

An earlier LUT-only A/B at 65,536 positions measured 68-69M/s for the
arithmetic shader versus 129-136M/s for the table-driven shader (~1.9x). After
the face-mask rewrite, the max-size kernel is about 9.8-10.3x the CPU
evaluator. Host encoding is still the end-to-end bottleneck: encoding plus one
max-size dispatch is about 41M positions/s.

Dispatch and completion have a roughly 200us floor. At 65K the kernel moves
about 3.9MB of row data plus 0.5MB of output in roughly 0.4ms (about 11GB/s),
so it is compute/dispatch-bound rather than bandwidth-bound. The synchronous
`waitUntilCompleted` contract remains; an asynchronous batch API would be
needed to overlap encoding with GPU work.

These are evaluator throughput numbers, not a search speedup and not a strength
claim. Dispatch and buffer setup still dominate at smaller batches, which is
why search integration must batch real leaves rather than perform one Metal call
per position. The accelerator remains standalone and is not wired into
`SearchEngine`.

## Files

- `Accelerator/include/IsolynAccelerator.hpp` — stable C++ contract.
- `Accelerator/include/IsolynEvaluationBatch.hpp` — weighted-component encoder.
- `Accelerator/include/IsolynPositionBatch.hpp` — compact-position encoder.
- `Accelerator/src/MetalAccelerator.mm` — runtime shader compilation and dispatch.
- `Accelerator/src/CpuBackend.cpp` — deterministic linear CPU reference.
- `Accelerator/src/EvaluationBatch.cpp`, `src/PositionBatch.cpp` — host encoders.
- `Accelerator/shaders/evaluation.metal` — canonical MSL reference.
- `Accelerator/tests/AcceleratorTests.mm` — parity, failure, and benchmark harness.
- `Accelerator/README.md` — implementation status and guardrails.

## Non-goals

- A second game engine.
- Game rules or move generation in Metal.
- Replacing the CPU search before parity and search integration are proven.
- Shipping a GPU requirement in the app.
- Calling the batch microbenchmark a playing-strength result.
