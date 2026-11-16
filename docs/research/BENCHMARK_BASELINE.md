# Benchmark Baseline (VOID)
**Status: VOID — pre-rulebook measurements, not a claim about the current engine.**

> ## ⛔ VOID — DO NOT CITE, DO NOT BUILD ON
>
> **Every number in this file was measured under the pre-rulebook rules**, before
> the owner's rulebook (RULES_VERSION 1) took effect on 2026-11-14. They are void
> because the game they measured no longer exists:
>
> - **Scoring inverted.** The winner is now credited with the loser's total
>   (R-03, R-05); these runs let the losing hand accumulate its own points, so
>   every closing decision in them was optimised against the opposite incentive.
> - **The evaluator changed.** `ClosingOpportunityHeuristic` had its sign flipped
>   when `roundScores` changed meaning, so the engine in these runs is not the
>   engine in the tree.
> - **Hand values changed.** A lone double blank is now worth ten (R-19).
> - **1v1v1 changed.** It plays to 151, not 101 (R-06), and the first player to
>   reach or pass it wins the set outright (R-22: no elimination).
> - **Draws changed.** The rulebook allows unlimited draws per turn (R-15); these
>   runs capped a turn at one.
>
> These results are **not reproducible from the current tree**, and none of them
> is a strength claim about the current engine. They are retained only so this
> reset can be audited. Current claims belong to
> [`STRENGTH_BASELINE.md`](STRENGTH_BASELINE.md) and nowhere else.
>
> **Rules version at measurement: PRE-RULEBOOK (void).**

**Rules version:** PRE-RULEBOOK — VOID

## Environment

**⛔ VOID (pre-rulebook) — the row below is not a current result and must not be cited.**

| Field | Value |
|---|---|
| Hardware | Apple M3, 8 cores (4 performance + 4 efficiency) |
| OS | macOS 27.2 |
| Compiler | Apple clang, C++20, `-O2` (self-play harness) |
| Build | `tools/selfplay/build.sh` |
| Evaluation | `PYTHONPATH=lab/src python3 -m isolyn_lab.cli evaluate --input <csv>` |

## Reference configurations

A configuration is `depth/determinizations`. These are the six
`DifficultyModel` profiles plus the sequential control.

**⛔ VOID (pre-rulebook) — the row below is not a current result and must not be cited.**

| Name | Depth | Determinizations | Notes |
|---|---:|---:|---|
| 2/8 | 2 | 8 | weakest tier (strength 100–400) |
| 3/16 | 3 | 16 | tier 900 |
| 4/24 | 4 | 24 | tier 1600 |
| 5/40 | 5 | 40 | tier 2300 |
| 8/64 | 8 | 64 | master tier (strength 3000) |
| seq-20 | 4 | 20 | single-threaded control, app default shape |
| par-64 | 4 | 64 | 8 workers — current champion |

## Measured 1v1 ladder (seed 42, alternating seats, no time cap)

Positive Elo favours side A. Intervals are 95%.

**⛔ VOID (pre-rulebook) — the row below is not a current result and must not be cited.**

| A vs B | Games | A wins | A score | Elo(A) | 95% CI | Resolved? |
|---|---:|---:|---:|---:|---|---|
| 2/8 vs 3/16 | 4,000 | 1,915 | 47.9% | **−14.8** | [−25.6, −4.0] | **yes** |
| 3/16 vs 4/24 | 4,000 | 1,914 | 47.9% | **−14.9** | [−25.7, −4.2] | **yes** |
| 4/24 vs 5/40 | 600 | 266 | 44.3% | −39.5 | [−67.5, −11.6] | **yes** |

Earlier 1,000-game runs of the first two pairs read −13.2 [−34.7, +8.3] and
−10.4 [−32.0, +11.1]; at 4,000 games both resolve. **The difficulty ladder is
correctly ordered and every adjacent step tested is statistically separable**, at
roughly **15 Elo per tier** for the lower three steps and ~40 for the fourth.

That is a real but modest separation. Fifteen Elo means the stronger tier wins
about 52% of head-to-head games — measurable, not dramatic. Presenting the five
bands as five clearly different opponents is defensible on ordering and
separation, but not on magnitude.

**Correction to an earlier record:** `docs/subsystems/LAB.md` reported 4/24
*beating* 5/40 (205–195 over 400 games). That does not reproduce at seed 42 over
600 games, where 5/40 wins at 55.7% with an interval excluding zero. The earlier
result was a 400-game sample of a small effect.

## Timing

**⛔ VOID (pre-rulebook) — the row below is not a current result and must not be cited.**

| Workload | Games | Wall | Notes |
|---|---:|---:|---|
| 2/8 vs 3/16 | 1,000 | 1.97 s | |
| 3/16 vs 4/24 | 1,000 | 4.94 s | |
| 4/24 vs 5/40 | 600 | 7.79 s | |
| 8/64 vs 8/64, sequential | 60 | 7.55 s | 955 decisions, ~7.9 ms/move |
| 8/64 vs 8/64, 8 workers | 60 | 3.18 s | 2.4× wall-clock |

Per-move cost at the master tier is ~7.9 ms single-threaded. The parallel path
uses 3.3 effective cores of 8, and performs ~47% more total CPU work than the
sequential path (per-lane tables hold fewer entries, so fewer hits).

## Other modes (seed 42, 500 games each, 2/8 vs 5/40)

Until 2026-11-14 every strength claim in this repository was 1v1-only. These are
the first measured multiplayer baselines.

**⛔ VOID (pre-rulebook) — the row below is not a current result and must not be cited.**

| Mode | A seats | A wins | A seat win% | B seats | B wins | B seat win% | Wall |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1v1v1 | 500 | 160 | 32.0% | 1,000 | 340 | 34.0% | 9.63 s |
| 2v2 (teams) | 500 | 248 | 49.6% | 500 | 252 | 50.4% | 5.69 s |

Read these with care:

- In 1v1v1 the B configuration occupies **two** seats per round, so seat
  percentages — not raw win counts — are the comparable number. 32.0% against
  34.0% is a small edge to the deeper side and is not a resolved result.
- In **2v2 the 5× compute advantage buys nothing at all** (49.6% vs 50.4%). That
  is the same message as E-007–E-009 from a different angle: more search does not
  produce better partnership play, so the deficiency is strategic, not
  computational.
- Closed-round frequency differs sharply by mode: 32% in 1v1v1 and 24% in 2v2,
  against ~21% in 1v1. Endgame and blocking skills matter more in multiplayer
  than the 1v1 tuning assumes.

## Game shape

At depth 4 over 1,000 games: ~17 decisions per round, 79% of rounds decided by a
Domino (emptied hand) rather than a Close, and first-player advantage is small —
player 1 wins 50.3–50.5%, so seat does not mask a strength difference.

---

## ⛔ Everything above this line is VOID

Every measurement in this file predates the 2026-11-14 rulebook and describes a
game that is no longer played: scoring inverted, the closing heuristic changed
sign, hand values changed, 1v1v1 changed shape, and draws were capped. It is kept
for audit only. Cite [`STRENGTH_BASELINE.md`](STRENGTH_BASELINE.md) instead — and
if that file has no result under the current rules hash, then there is no
strength claim to cite at all.
