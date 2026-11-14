# Metal Integration — Audit and Plan

**Status:** living audit (tier 2). Records what the accelerator actually is, what
it has been measured at, and why the shipped search still does not call it.
Nothing here is a claim of acceleration; the application does not invoke Metal
today.

## What exists

`Accelerator/` is real, standalone, and 1,702 lines. It is **not** an SPM
target — `Accelerator/build.sh` compiles it directly with `clang++`, because SPM
does not build `.mm` plus runtime-compiled MSL cleanly for this project.

| File | Role |
|---|---|
| `include/IsolynAccelerator.hpp` | stable C++ contract |
| `include/IsolynPositionBatch.hpp` | compact-position encoder |
| `include/IsolynEvaluationBatch.hpp` | weighted-component encoder |
| `src/MetalAccelerator.mm` | device, pipeline, persistent buffers, dispatch |
| `shaders/evaluation.metal` | canonical MSL kernel |
| `src/CpuBackend.cpp` | deterministic CPU reference |
| `tests/AcceleratorTests.mm` | parity, fallback and benchmark harness |

It computes the **eight `EvaluationEngine` components** for an already
determinized, already-concrete position. It does not generate moves, validate
legality, score rounds, or choose moves.

## Measured throughput (development M3)

| Batch | CPU positions/s | Metal positions/s |
|---:|---:|---:|
| 1,024 | ~17M | ~4.3–5.2M |
| 4,096 | ~17M | ~17.3–18.6M |
| 16,384 | ~17M | ~62–66M |
| 65,536 | ~17M | ~162–170M |

Best measured 65K median: **168.7M positions/s**, roughly 10× the CPU evaluator.
Host encoding is now the end-to-end bottleneck (~34M/s including one dispatch);
a 65K batch moves ~4.4 MB in ~0.4 ms, so the kernel is not bandwidth-bound. The
synchronous `waitUntilCompleted` path blocks host/GPU overlap, and dispatch has a
~200 µs floor.

**Crossover matters:** below ~4K positions the CPU wins outright. That is close
to the size of a single move's full leaf set, which is precisely why the wiring
question is not trivial.

## Why it is not wired

The search is a recursive, pointer-shaped tree with alpha-beta cutoffs. Leaf
evaluations are discovered one at a time, depth-first, and a cutoff discards most
of them. To use a GPU profitably the engine would have to produce *batches* of
positions whose evaluations are all needed — which means either

1. **batching root determinization evaluation** (every candidate in every sampled
   world, evaluated together), or
2. **a frontier/breadth-first search** that materialises whole levels, or
3. **batching self-play inference**, where thousands of independent positions
   exist by construction.

Option 1 is the smallest change that reaches the ~4K crossover; option 2 is a
rewrite of the search and would forfeit alpha-beta's pruning advantage.

## Measured verdict

E-004 shows the parallel CPU path already wins **+17.6 Elo** (+6.8, +28.3) at
lower per-move cost than the engine it replaced. Metal has not yet been shown to
beat that, and no integrated measurement exists — only isolated kernel
throughput.

## Plan, in cost order

| Step | Work | Gate to pass before it counts |
|---|---|---|
| 1 | Link `Accelerator` into the self-play harness | CPU/GPU parity on real search leaves, not synthetic rows |
| 2 | Batch root candidate × world evaluation through the accelerator | end-to-end move latency must beat the 8-worker CPU path |
| 3 | Fallback and reporting | CPU fallback on device loss; report which path ran |
| 4 | Only then: frontier search | needs a measured strength win, not a speed win |

## Non-goals

- Rules or move legality in Metal.
- A second scoring implementation.
- A GPU requirement in the shipped app.
- Claiming acceleration while the CPU fallback is what actually ran.
