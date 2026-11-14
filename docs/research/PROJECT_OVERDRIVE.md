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
| Revision | parallel root search (`dc1f757`) + partnership weight (`teamSupport = 24`) |
| 1v1 configuration | depth 4, 64 determinizations, `workerThreads = 8` |
| 1v1 vs sequential 20-sample engine | **+17.6 Elo**, 95% CI [+6.8, +28.3], n=4,000 |
| Depth 5 vs 4 (1v1, 64 samples) | **+16.9 Elo**, 95% CI [+4.5, +29.4], n=3,000, ~1.3x cost |
| Depth 8 vs 5 (1v1, 64 samples) | **+20.9 Elo**, 95% CI [+5.6, +36.1], n=2,000, ~2.6x cost |
| Depth 8 + draws vs depth 4 | **+22.3 Elo**, 95% CI [+9.8, +34.7], n=3,000 |
| 2v2 vs the old 0.25 partnership weight | **+15.8 Elo**, 95% CI [+10.2, +21.3], pooled n=15,000 across 5 seeds |
| 1v1 control for the 2v2 weight change | −1.0 Elo [−16.3, +14.2] — no effect, as constructed |
| Correctness | 429 engine, 73 bridge, 75 Swift — all passing |

## What is known to be weak

Ranked by expected strength return, not by how interesting the work is.

**Compute scaling is exhausted (measured 2026-11-14).** More worlds stop paying
at 64, and depth 10 loses to depth 8 at 4.3× the cost. Any further strength must
come from better decisions per node, not from more nodes.

**The evaluation is a binary threat detector with a tie-breaker (measured).**
One ±1000 term — an immediate Domino win is available — carries 98% of the
evaluation's variance and is zero in 92% of positions; the other seven terms sum
to a standard deviation of ~15. Attenuating that term (100) costs 24 Elo and
removing it costs 16, so its dominance is earned, but the engine has **no graded
notion of winning chance** between "threat exists" and "threat does not"
(E-018, E-019). That is the most promising remaining evaluation gap.

### Missing action: voluntary draw

> **Status 2026-11-14 (E-024, E-025): now executable, measured, neutral.**
> E-024's first attempt scored −38.4 Elo at n=400 and was invalid: `Move` cannot
> represent a draw, so the branch changed leaf scores the engine could not act
> on. The decision contract was then extended (`SearchDecision::isDraw`,
> `Config::maxVoluntaryDraws`, applied by the caller without advancing the turn)
> and the action re-measured properly: **1,484 draws in 10,650 1v1 decisions
> (14%)**, but pooled **+2.5 Elo, 95% CI [−4.7, +9.7]** over 9,000 rounds — not
> resolved. Capability kept, **default off**; 1v1v1 has no branch and 2v2 never
> chose a draw in 10,426 decisions. One ply deeper the action **resolves**:
> **+9.4 Elo [+0.4, +18.3]** over 5,798 rounds at depth 5, with 16.3% of
> decisions being draws. The value is horizon-dependent — it is a positional
> investment — which is why the shipped depth-4 configuration shows nothing.

**This is the largest structural gap found so far, and it is a missing move, not
a missing weight.**

The rules allow a player to draw from the boneyard voluntarily:
`MatchController::voluntaryDraw()` exists, and `MatchController.hpp` states that
"WHETHER to voluntarily draw" is a strategic choice belonging to search. Search
never makes it. `Move` deliberately cannot represent a draw (its header says so),
`MoveGenerator` emits placements only, and the search's `resolveForcedDraws`
flies tiles in solely to escape a stuck position.

Meanwhile `docs/design/STRATEGY_NOTES.md` treats drawing as a first-class axis —
it argues that drawing *heavily*, even emptying the boneyard, is the high-skill
inversion of conventional wisdom, and that opponents counter by forcing extra
draws. The engine therefore cannot play the strategy its own design documents
describe, and no amount of samples, depth or weight tuning reaches it: **the
action is absent from the game tree.**

Implementation is a real project, not a patch: a draw must enter `Move` (or a
sibling action type), `MoveGenerator`, `MoveExecutor`/undo, the transposition-key
scheme, and the belief updates that observe a draw. It also needs a bound on
consecutive draws to keep the tree finite. It is the top candidate for the next
block of work.

**2v2 converts compute into nothing (measured twice), but partnership weight
converts into wins.** The configuration edge worth **+27.4 Elo in 1v1** scores
**49.7% in 2v2**, replicating an earlier 49.6% null. Yet raising the single
partnership term from 0.25 to 24 (E-023) is worth **+15.8 Elo [+10.2, +21.3]**
over 15,000 pooled rounds. So 2v2's deficit is representational: search effort
is wasted there, but the partnership signal was simply mis-scaled. One term is
still a thin model of a teammate — the compute null is untouched by the fix.

1. **The difficulty ladder is ordered but the separation is modest.** At 4,000
   games the 2/8 → 3/16 and 3/16 → 4/24 steps resolve at −14.8 and −14.9 Elo,
   and 4/24 → 5/40 resolves at −39.5. Every adjacent step tested is separable,
   at roughly a 52% head-to-head win rate per tier — real, but not the dramatic
   difficulty cliff the labels imply. The 5/40 → 8/64 step has not been measured
   directly.
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
| 1 | **Wire the now-executable draw action through the bridge and app, then re-test at greater depth** | measurable at last, but neutral at depth 4 (E-025); the bridge still cannot play a `SearchDecision::isDraw` |
| 2 | **Deepen 2v2 partnership modelling beyond one mobility term** | re-weighting was worth +15.8 Elo (E-023); the representation is still one scalar |
| 3 | Build a budgeted joint weight optimizer | single-weight effects sit below the ~15 Elo resolution of ablation (E-015 – E-017) |
| 4 | Replace the TT key and add depth-preferred replacement | the stated blocker on deeper search: tables are diluted across lanes |
| 5 | Add pruning to 1v1v1 | the weakest mode, and the fix is well understood |
| 6 | Add a tactical-stability (quiescence) pass | removes a whole class of blunder |
| 7 | Decide the accelerator's fate: batch real leaves, or archive it | measured end-to-end slower than the CPU at every batch size |

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
