# Project Overdrive — Research Journal

**Status:** living research journal (tier 2). Started 2026-11-14. This is the
entry point for the strength programme; it records what is true *now*, not what
was hoped for. Measured figures live in `docs/research/BENCHMARK_BASELINE.md`,
per-change records in `docs/research/EXPERIMENT_REGISTRY.md`, and the GPU audit
in `docs/research/METAL_INTEGRATION.md`.

**Why four files instead of ten.** The original mission brief named ten journal
files (RESEARCH_LOG, ARCHITECTURE_MAP, NEXT_ACTIONS, KNOWN_LIMITATIONS and so
on). Six of them would have held a paragraph each and drifted out of sync, which
is exactly the duplication this repository's documentation rules forbid. Their
content is consolidated here; the four files that survive each have a distinct
reader and a distinct update cadence.

## Charter

Maximise **actual playing strength** — not nodes, not cores, not GPU
utilisation. Every change is judged by tournament results against a fixed
opponent at a fixed seed, with a confidence interval, and is reverted if it
does not pay.

## Standing method

1. One hypothesis at a time, against a recorded baseline.
2. Fixed seeds, alternating seats, ≥1,000 games before believing anything.
3. Report the CI, not just the win rate. A 52% result with a ±20 Elo interval is
   not a result.
4. Correctness suites run before any strength number is trusted: 429 engine
   checks, 73 bridge checks, 75 Swift tests.
5. Never overwrite the baseline configuration that produced a published number.

## Current champion

| Field | Value |
|---|---|
| Revision | working tree on top of `2b07564` (parallel root search) |
| 1v1 configuration | depth 4, 64 determinizations, `workerThreads = 8` |
| Measured vs sequential 20-sample engine | **+17.6 Elo**, 95% CI [+6.8, +28.3], n=4,000 |
| Correctness | 429 engine, 73 bridge, 75 Swift — all passing |

## What is known to be weak

Ranked by expected strength return, not by how interesting the work is.

**Compute scaling is exhausted (measured 2026-11-14).** More worlds stop paying
at 64, and depth 10 loses to depth 8 at 4.3× the cost. Any further strength must
come from better decisions per node, not from more nodes.

1. **The difficulty ladder is not validated per tier.** Adjacent tiers differ by
   ~10–13 Elo and two of the three adjacent comparisons are inside noise at
   1,000 games. Only the 4/24 → 5/40 pair resolved (−39.5 Elo). The five labels
   are therefore presentation, not proven strength.
2. **CPU is under-used end-to-end.** Root sampling is now parallel, but total
   CPU work rose ~47% (TT dilution across lanes); effective core use measured
   3.3× of 8. Thread-level work is done; the waste is allocator contention and
   load imbalance across samples.
3. **The transposition table is close to useless across move orders.** Its key
   includes play history and the full boneyard order, so two routes to the same
   board never share an entry. It also flushes all 250k entries on overflow.
4. **1v1v1 has no pruning and no exact endgame.** `searchMulti` is full-width
   and `isExactEndgame` returns false for that mode, so three-player play is far
   weaker per unit of time than 1v1.
5. **No quiescence.** Leaves are scored mid-exchange, so horizon blunders are
   possible.
6. **Determinization samples are independently plausible, not jointly correct**,
   and root selection averages them — the classic strategy-fusion exposure.
7. **Metal accelerates a leaf evaluator the search never asks for.** 168.7M
   positions/s against ~17M/s on CPU, with no caller.

## Next actions, in order

| # | Action | Why it is next |
|---|---|---|
| 1 | **Calibrate the eight evaluation weights against tournament results** | E-007–E-009 show compute scaling is exhausted; evaluation is now the binding constraint |
| 2 | Re-derive difficulty tiers from measured head-to-head results | five labels currently overstate five strengths |
| 3 | Replace the TT key and add depth-preferred replacement | the stated blocker on deeper search: tables are diluted across lanes |
| 4 | Add pruning to 1v1v1 | the weakest mode, and the fix is well understood |
| 5 | Add a tactical-stability (quiescence) pass | removes a whole class of blunder |
| 6 | Decide the accelerator's fate: batch real leaves, or archive it | 1,700 lines with zero effect today |

**Superseded.** The earlier first action — raise the app's `determinizationCount` —
is withdrawn. The shipped elite tier already runs 8/64, which E-007 places at the
sampling operating point; raising it would cost latency and buy nothing.

## Limitations of the current evidence

- All strength numbers are **self-play**, not against external engines or human
  players. There is no absolute Elo claim and none should be made.
- Paired results are seed-controlled but not seed-averaged; a single seed can
  favour one configuration. Replication across ≥3 seeds is required before
  promoting any change to the champion.
- Worker count changes decisions (each lane owns its table), so reproducible
  comparisons must pin `workerThreads`.
