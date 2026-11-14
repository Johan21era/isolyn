# Offline Lab & Trainer

**Status:** the C++ self-play generator is real, supports side-alternated
head-to-head configurations, and the Python lab has a working calibration
report plus a measured internal 1v1 ladder. There is still no trainer or
exported weight set, and no Elo claim against external engines.

## Purpose

Give IsolynV2.0 a reproducible place to:

- play engine-vs-engine games,
- calibrate the `DifficultyModel` ladder,
- generate training/evaluation datasets,
- train an optional learned evaluation model,
- measure candidate strength against a baseline.

The lab exists to make strength claims **measurable**, not to add a second game
engine.

## Boundary

```text
C++ engine (rules, search, scoring)
        │  self-play / evaluation output
        ▼
tools/selfplay/  ── CSV/JSONL ──▶  lab/ (Python)
        ▲                              │
        └──── weights / reports ◀──────┘
```

- C++ is the only source of game truth.
- Python reads engine output and produces data/weights/reports.
- Python never reimplements move legality, scoring, or round rules.
- The shipped `.app` never contains a Python runtime.
- A model may influence evaluation only through C++ inference.

## Components

### `tools/selfplay/` — C++ harness

- Links the real `IsolynEngine`.
- Plays legal 1v1, 1v1v1, and 2v2 rounds with deterministic seeds.
- Emits one row per move, including evaluation components and final scores.
- Records mode, search configuration per side, depth reached, nodes, TT hits,
  exact-endgame use, starting-hand quality, winner, and scores. Engine-commit
  capture remains a packaging task.
- Runs on a developer Mac; no UI.

### `lab/` — Python lab

- `configs/` — experiment shape (TOML).
- `src/isolyn_lab/` — CSV loading, calibration reports, training/evaluation
  scaffolding.
- `data/` — generated datasets/weights (gitignored).
- `pyproject.toml` — no runtime dependencies; optional `train` extras.

## Data contracts

Every dataset must eventually carry:

- engine commit,
- creation timestamp,
- seeds and configuration,
- game mode and strength tier,
- hardware/OS for benchmark rows.

The current generator emits seeds and configuration but not an engine commit
or timestamp yet; those remain lab packaging requirements, not claims already
met by the CSV.

Game-level fields (repeated on every move row):

```text
game, seed, mode, config_a_depth, config_a_determinizations,
config_b_depth, config_b_determinizations, participant_side0..3,
initial_hand0..3, final_hand0..3, participant_count,
participant_score0..3, outcome, deciding_player
```

Move rows (implemented):

```text
game, seed, mode, move, player, tile_low, tile_high, side,
depth_reached, nodes, tt_hits, exact_endgame,
eval_total, mobility, blocking, expected_value, closing_opportunity,
win_threat, pip_control, tempo, team_support,
initial_hand0..3,
final_hand0..3, participant_count, participant_score0..3,
outcome, deciding_player
```

Weights must be exported as a documented data format (JSON or ONNX) and loaded
by C++ inference. No pickle files cross the boundary.

## Workflow

1. Build the C++ harness: `./tools/selfplay/build.sh`.
2. Run a small smoke batch (seeds fixed), verify legal games and row counts.
3. Run a side-alternated 1v1 or 2v2 head-to-head batch, then `isolyn-lab evaluate
   --input lab/data/selfplay.csv`.
4. Scale to the calibration grid: depth × determinizations × strength tier.
5. Analyze win rates, score deltas, and hand-quality correlation.
6. Freeze the `DifficultyModel` mapping only after the ladder is monotonic.
7. Optional: train an evaluation model, export weights, run C++ inference,
   measure the ladder again.

## Measured baseline (2026-11-11)

These are 1v1 self-play results with side alternation, no wall-clock cap, and
the full requested depth reached in every sampled move. They are a calibration
baseline, not an Elo claim against external engines. Every row below was
generated after the terminal-utility correction described underneath the table:
a real Domino win is a search score of 2000 plus the losing hand, while a
one-tile playable threat is only 1000.

| A config (depth/det) | B config (depth/det) | Games | A wins | B wins | Elo(A vs B) | 95% CI | Source file |
|---|---:|---:|---:|---:|---:|---:|---|
| 2/8 | 3/16 | 400 | 187 | 213 | −22.6 | [−56.7, +11.5] | `lab/data/ladder-100-900.csv` |
| 3/16 | 4/24 | 400 | **202** | 198 | **+3.5** | [−30.5, +37.5] | `lab/data/ladder-900-1600.csv` |
| 4/24 | 5/40 | 400 | **205** | 195 | **+8.7** | [−25.3, +42.7] | `lab/data/ladder-1600-2300.csv` |
| 2/8 | 8/64 | 1000 | 424 | 576 | −53.2 | [−75.0, −31.4] | `lab/data/ladder-100-3000-8x64.csv` |

All four rows were recomputed from the committed CSVs with
`PYTHONPATH=src python3 -m isolyn_lab.cli evaluate --input <file>` on 2026-11-13;
the report was byte-identical across three runs.

**The ladder is NOT directionally monotonic.** Two of the three adjacent
comparisons favour the *shallower* configuration: 3/16 beats 4/24 by 51.2%,
and 4/24 beats 5/40 by 51.3%. Only the widest gap (2/8 vs 8/64, 42.4%) is
statistically resolved; every adjacent interval crosses zero. An earlier version
of this table reported 190/210 and 196/204 for those two rows, which does not
reproduce from the committed data.

Consequence: the five `DifficultyModel` bands are labels, not measured
strengths. The top band is genuinely stronger than the bottom band; the
intermediate ordering is unproven. No adjacent comparison clears the 55%
milestone. The honest summary of measured 1v1 strength is "two tiers:
2/8 and 8/64, with three unvalidated points between them."

The depth increase was measured separately rather than assumed. In 1,000-game
1v1 matches: 2/8 vs 6/8 was -18.8 Elo ([-40.3, +2.8]), 6/8 vs 6/64 was -8.3
([-29.9, +13.2]), and 6/64 vs 8/64 was -14.6 ([-36.1, +6.9]). The combined
bottom-vs-top result is the clear one; the individual factors are small enough
that only their combination currently clears zero. The elite tier is therefore
8/64, but it is roughly 2.6x the median node count of depth 6 and is not a
free upgrade.

The calibration run exposed a search-scoring inversion: an actual win was valued
only at the opponent's remaining pips (often ~20), while a non-terminal one-tile
threat was valued at 1000. A bounded search could therefore prefer preserving a
threat over taking the win. The fix is search-only: a completed Domino win adds a
terminal bonus above the threat band, while `EvaluationEngine`'s reported
breakdown keeps its original zero-for-empty-hand contract. Root zero-sum move
selection also compares the alpha-beta score rather than a raw vector from a
transposition-table bound.

## Milestones

| # | Milestone | Exit criterion |
|---|---|---|
| 1 | Self-play seam | 100 legal games, deterministic from seed, CSV schema stable |
| 2 | Calibration | Head-to-head reports + adjacent tiers: stronger wins ≥55% over N≥200 games |
| 3 | Dataset | Move rows with evaluation breakdown and belief sample counts |
| 4 | Learned evaluation (optional) | Candidate beats hand-tuned baseline at fixed time control |
| 5 | Reproducibility | A clean clone can regenerate a dataset from commit + seeds |

## Non-goals

- A Python game engine.
- A Python runtime in the app.
- Training before the self-play/calibration baseline exists.
- Replacing the C++ search with a model.
- Shipping datasets or weights in the app bundle by default.

## Related decisions

- `docs/engineering/OPEN_DECISIONS.md` — ADR-001, ADR-002, ADR-004.
- `docs/subsystems/ACCELERATOR.md` — how stronger evaluation/search is accelerated.
- `tools/selfplay/README.md` — self-play generator contract and limitations.
- `lab/README.md` — lab layout and milestones.
