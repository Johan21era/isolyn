# Metal Integration — Audit, Measurements and Verdict

**Status:** living audit (tier 2). Re-measured 2026-11-14 on the development M3.
Records what the accelerator is, what it measures end to end, and why the
production engine does not call it. **No part of this document is a claim that
the application is GPU-accelerated. It is not.**

> **Parity regression (2026-11-14).** `./Accelerator/build.sh` currently exits 1:
> **94 pass, 6 fail** (four compact-GPU total checks, the closed-position total,
> and the multi-mode scale check). The shader still hard-codes the old `0.25`
> partnership weight while the engine uses `24.0`. Everything below about parity
> describes the last green run, not the current tree; do not treat the backend as
> validated until those checks are restored.

## Verified state of the production path

- `Sources/IsolynEngine`, `Sources/IsolynEngineBridge` and `Sources/IsolynApp`
  contain **no reference** to `Accelerator` (verified by search, 2026-11-14).
- `Package.swift` declares no `Accelerator` target; the code lives outside SPM
  and builds only through `Accelerator/build.sh`.
- Every move the shipped app makes is produced by the CPU search.

The accelerator is therefore a working, tested, *unused* backend.

## What exists

| File | Role |
|---|---|
| `include/IsolynAccelerator.hpp` | stable C++ contract |
| `include/IsolynPositionBatch.hpp` | compact-position encoder |
| `src/MetalAccelerator.mm` | device, pipeline, persistent buffers, dispatch |
| `shaders/evaluation.metal` | canonical MSL kernel |
| `src/CpuBackend.cpp` | deterministic CPU reference |
| `tests/AcceleratorTests.mm` | parity, fallback and benchmark harness |

It computes the eight `EvaluationEngine` components for already-determinized
positions. It never generates moves, validates legality, scores rounds, or
chooses moves. Parity with `EvaluationEngine` passes for 1v1, 1v1v1, 2v2,
closed positions, terminal wins, empty chains, equal ends and one-tile threats on
the last green run; the current tree fails 6 of those checks (see the banner).

## Measured throughput (this machine, 2026-11-14)

From the last green `./Accelerator/build.sh` run (the harness now exits 1):

| Batch | CPU positions/s | Metal positions/s | Metal µs/call |
|---:|---:|---:|---:|
| 1,024 | 7.86M | 4.81M | 213 |
| 4,096 | 17.31M | 14.33M | 286 |
| 16,384 | 16.77M | 50.34M | 325 |
| 65,536 | 16.11M | **172.26M** | 380 |

The kernel is real: 10.7× the CPU at 65K. **Host encoding runs at 9.56M
positions/s** — slower than the CPU evaluator it exists to replace.

## The number that decides it

End-to-end cost, using the measured rates (encode + kernel + one synchronous
dispatch):

| Batch | CPU evaluate | GPU end-to-end | Winner |
|---:|---:|---:|---|
| 4,096 | 0.24 ms | 0.83 ms | CPU |
| 16,384 | 0.98 ms | 2.19 ms | **CPU** |
| 65,536 | 3.90 ms | 7.62 ms | **CPU** |

**The GPU path is slower than the CPU at every batch size**, because encoding a
position costs more than evaluating it on the CPU (~105 ns vs ~60 ns), and the
dispatch/completion floor is 213–380 µs regardless of batch size.

The kernel is not the bottleneck. The data path is.

## What a real search actually needs

Measured over 490 decisions at the master configuration (depth 8, 64 worlds):

| Statistic | Value |
|---|---|
| Nodes per decision | p50 **28,992**, p90 176,819, max 1,631,862 |
| Depth reached | p50 8 |
| Total nodes / 30 games | 38.3M |

Split across 64 determinizations that is ~450 nodes per world — two orders of
magnitude below the 16K batch where the kernel first beats the CPU. A per-move
budget of ~3.3 ms cannot absorb a 213 µs dispatch floor plus marshalling to save
roughly 1 ms of evaluation.

## Verdict

**The accelerator provides no end-to-end acceleration for this engine, and
wiring it into the interactive search would make the product slower.** That is a
measured result, not an opinion, and it is why the engine calls it nowhere.

Two conditions would have to change before GPU use could pay:

1. **The encoder would have to beat the CPU evaluator.** At 9.56M/s it is 1.8×
   slower than the 16.8M/s CPU path. Encoding is a bitmask walk per hand; a
   vectorised, structure-of-arrays encoder could plausibly reach 40–60M/s, which
   would flip the 16K and 65K rows above.
2. **Positions would have to be batched without a host round trip.** The search
   is depth-first with alpha-beta cutoffs, so the positions it evaluates are
   discovered one at a time and most are discarded. Batching them means either a
   frontier search (forfeiting cutoffs — a strength cost the tournament data
   would have to justify) or GPU-resident generation, which is a rewrite.

Where the accelerator *is* legitimately useful is offline batch analysis —
millions of independent positions with no latency constraint — and even there
the encoder, not the kernel, sets the ceiling.

## Non-goals

- Rules or move legality in Metal.
- A second scoring implementation.
- A GPU requirement in the shipped app.
- Reporting acceleration while the CPU fallback is what ran.
