# Offline Lab & Trainer

**Status:** current on 2026-11-15. The C++ self-play generator is real, supports
side-alternated head-to-head configurations, and the Python lab has a working
calibration report. `./scripts/lab run` drives resumable sharded runs, so a
multi-million-game dataset is one restartable command; the app's Lab screen
drives the same runner through a staged copy outside the checkout. Measured on
the owner's Mac at symmetric depth 8 / 64 samples with eight batches: about
22.7 games/s, so 5,000,000 games is roughly 61 hours. There is still no trainer
or exported weight set, and no Elo claim against external engines. Strength
claims, if any, live only in `docs/research/STRENGTH_BASELINE.md`.

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
- The `.app` ships no Python runtime; the Lab screen runs a staged copy of
  `lab/` from `~/Library/Application Support/IsolynV2.0/Lab`, never the
  checkout.
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
- `src/isolyn_lab/` — streaming CSV folding, calibration reports, the resumable
  sharded runner (`runner.py`), and training/evaluation scaffolding.
- `data/` — CLI-generated datasets/weights (gitignored). Runs started from the
  app live in `~/Library/Application Support/IsolynV2.0/runs` instead, so the
  app never reads the Desktop checkout.
- `pyproject.toml` — no runtime dependencies; optional `train` extras.

## Cloud batch bridge (2026-11-14)

Kaggle is wired as a **batch worker for the same harness**, never as a host for
the app. `scripts/lab cloud` plans contiguous shards, packages a private code
dataset through an explicit allowlist, generates one private CPU-only notebook
per session, and accepts output only after a receipt/hash/game-count check. The
C++ engine remains the only rules authority; the worker just builds
`tools/selfplay` and runs its planned shards.

The worker uses the portable build and the in-tree stable RNG. A clean source
state and SHA-256 code digest are required before packaging, and every receipt
carries the source commit, code digest, dataset reference and exact
configuration. The app has no Git checkout in Application Support: `run.sh`
stages an allowlisted source bundle plus `source.json` (commit, clean flag, file
hashes and code digest), and the driver verifies that immutable record instead
of invoking Git there. `fetch` validates in a temporary directory and refuses
overwrite; `assemble` re-verifies every session and refuses gaps, overlaps or
incomplete receipts; `collect` is the status-guarded fetch/verify/assemble path
used by the app.

**No live Kaggle session has been run in this checkout.** The local driver and
worker are covered by offline tests, but the first 10,000-game session is still
the acceptance gate. Commands, account setup and limits are in
[`cloud/README.md`](../../cloud/README.md); the design arithmetic is in
[`docs/research/KAGGLE_BRIDGE.md`](../research/KAGGLE_BRIDGE.md).

## App integration (2026-11-14)

The Lab screen removes the terminal from the loop without changing what a run is.

- `run.sh` stages `scripts/lab`, `lab/src/isolyn_lab`, `lab/configs`, the
  built `selfplay` binary, the allowlisted cloud source and `source.json` into
  `~/Library/Application Support/IsolynV2.0/Lab`. The app resolves that copy
  first, so it never reads the checkout (a TCC-protected Desktop folder) and a
  rebuild cannot invalidate a permission. The bundle records a dirty tree
  rather than hiding it; the driver refuses cloud work until it is clean.
- The Cloud tab is the one-click external path: it fixes the first run at
  10,000 games in one 4-shard session, confirms the private upload once, and
  runs plan → prepare → push through the staged driver. **Check Kaggle status**
  is the only action after upload; **Collect verified results** appears only
  once that check reports the notebook complete, then fetches, verifies and
  assembles it. The Kaggle token is never read by the app.
- App runs are written to `~/Library/Application Support/IsolynV2.0/runs`; the
  runner accepts `--runs-dir` (and honours `ISOLYN_RUNS_DIR`) so a single
  invocation can target that store. The CLI default remains `lab/data/runs`.
- One run at a time is enforced three ways: a service guard, a short repeat
  window, and the runner's `run.lock`. The app attaches to a run that is already
  active instead of starting a second process. A merge is a tracked child too;
  it blocks Start and Delete until it exits.
- The run library is read from a cached, once-a-second directory scan rather
  than on every redraw, and shows Started / Games / Mode / Depth / Worlds /
  Seed / Progress / Status as columns. The manifest publishes partial shard
  progress every two seconds, so a long shard moves the bar instead of looking
  frozen. Analyses read finished CSVs only, and stream them one game at a time;
  a multi-million-row report no longer requires holding the CSV in memory.
- The detail sheet follows the live manifest, lists failed-shard reasons, and
  opens the runner or failed-shard log. Deleting a run requires confirmation and
  is refused while its lock is active. Analyses can be stopped, their log opened,
  their report copied, and the last report set is reloaded after relaunch.
- A minimized window is restored by the app delegate on Dock reopen or
  activation; `Window ▸ Show Isolyn Window` (⌘0) is the manual fallback.

## Data contracts

Every dataset must eventually carry:

- engine commit,
- creation timestamp,
- seeds and configuration,
- game mode and strength tier,
- hardware/OS for benchmark rows.

The current generator emits seeds and configuration but not an engine commit
or timestamp yet; those remain lab packaging requirements, not claims already
met by the CSV. Cloud sessions add them at the session level: the plan, worker
receipt and local assembly summary record the source commit, code digest,
timestamp, seeds, configuration, platform and verified row counts without
changing the CSV schema.

Rows for one game are contiguous and game ids increase within a shard. The
streaming reader relies on that shape and rejects a file whose ids go backwards
rather than folding it incorrectly; `runner merge` renumbers shards into the
same shape. The calibration report uses exact weighted-rank counts, so its
memory is bounded by distinct hand/result values rather than by corpus size.
A manifest records a per-shard `progress` count and a `resumed_at` timestamp;
both are advisory display fields and never substitute for a verified `done`
shard. Measured pipeline timings live in [`lab/README.md`](../../lab/README.md),
not duplicated here.

A finished or interrupted run gets generated `README.md`, `report.html`,
`summary.json` and `shards/README.md` beside `manifest.json`; runs up to 100,000
hands also get `games.csv`. The README is the plain-language entry point:
verdict, counts, who won, what is good, what needs attention, what to do next,
how to reproduce, file map and glossary. `report.html` presents the same
material as a self-contained offline page for double-click reading.
`shards/README.md` maps the raw files and defines every CSV column. Small or
shallow batches are labelled smoke tests; incomplete batches are NOT READY. The
report reads finished shard CSVs only and never edits them; `lab report
<run-id>` rebuilds it, and a raw CSV malformed enough to prevent a tidy fold
removes the partial `games.csv` instead of presenting it as complete.

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

From the app, `./run.sh` builds, stages and launches; the Lab tab runs the
same commands below. From a terminal:

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

> **VOID (2026-11-14).** The ladder below predates the rulebook and measures a
> different game. Do not cite it. Current strength claims, if any, live only in
> `docs/research/STRENGTH_BASELINE.md`.

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

All four rows were recomputed from the lab's CSVs on 2026-11-13 with
`PYTHONPATH=src python3 -m isolyn_lab.cli evaluate --input <file>`. Those data
files are not committed, so this table is historical and not reproducible from
a clean clone (see the VOID note below).

**Historical, VOID (2026-11-14): the 4,000-game ladder below is not a current claim.**
It was recorded before the rulebook change, and its source CSVs (`lab/data/*`)
are not committed, so it cannot be reproduced from a clean clone. It is kept
only as history. Current claims belong to `docs/research/STRENGTH_BASELINE.md`,
which currently records none.

| A vs B | Games | A score | Elo(A) | 95% CI | Resolved? |
|---|---:|---:|---:|---|---|
| 2/8 vs 3/16 | 4,000 | 47.9% | −14.8 | [−25.6, −4.0] | **yes** |
| 3/16 vs 4/24 | 4,000 | 47.9% | −14.9 | [−25.7, −4.2] | **yes** |
| 4/24 vs 5/40 | 600 | 44.3% | −39.5 | [−67.5, −11.6] | **yes** |

These rows must not be cited as evidence for the current difficulty ladder. The
five `DifficultyModel` bands are ordered by construction, but their separation
has not been measured under the 2026-11-14 rules, and the data behind this table
is absent from the repository.

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
