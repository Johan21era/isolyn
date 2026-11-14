# IsolynV2.0 Self-Play Generator

**Status:** working engine-vs-engine generator, updated 2026-11-14. It links
the real `IsolynEngine` and emits one CSV row per move. It is not a strength
claim and it is not a trainer.

## Build and run

```bash
./tools/selfplay/build.sh
./tools/selfplay/build/selfplay --check
./tools/selfplay/build/selfplay --help

# One reproducible 1v1 round:
./tools/selfplay/build/selfplay \
  --games 1 --mode 1v1 --depth 4 --determinizations 20 \
  --time-ms 100 --seed 7 --output lab/data/selfplay.csv

# Head-to-head strength comparison (A vs B, sides alternate each game):
./tools/selfplay/build/selfplay \
  --games 200 --mode 1v1 --depth 3 --determinizations 16 \
  --opponent-depth 4 --opponent-determinizations 24 \
  --time-ms 100 --seed 7 --output lab/data/h2h.csv
```

The binary is written to `tools/selfplay/build/`, which is gitignored. The
default output path is `lab/data/selfplay.csv`.

`build.sh` is portable: it links Apple's Security framework only on Darwin, uses
`-pthread` on both macOS and Linux, and honours `ISOLYN_SELFPLAY_OUT` so a batch
worker can write to a mounted output directory. It uses the in-tree
`StableRandom.hpp` instead of implementation-defined distribution mappings, so
the same seed and configuration should reproduce the same deals across
platforms. `StableRandomTests` pins the expected sequence. Actual Linux
compilation is exercised by the first Kaggle session; the build-script test only
pins the platform flags.

## Modes

- `--mode 1v1`
- `--mode 1v1v1`
- `--mode 2v2`

All three use the production rules, dealer sizing, scoring, belief state, and
search. The only lab-specific code is the seeded deal wrapper, because the
production `Dealer` deliberately uses OS CSPRNG and calibration needs
reproducibility.

`--depth`/`--determinizations` configure side A. The optional
`--opponent-depth`/`--opponent-determinizations` configure side B and alternate
which physical player/team gets A on each game. Reports group results by side,
so a first-player advantage is not silently attributed to search strength.

## CSV fields

Each row is one decision, repeated with the round's final result:

```text
game, seed, mode, config_a_depth, config_a_determinizations,
config_b_depth, config_b_determinizations, participant_side0..3,
move, player, tile_low, tile_high, side,
depth_reached, nodes, tt_hits, exact_endgame,
eval_total, mobility, blocking, expected_value, closing_opportunity,
win_threat, pip_control, tempo, team_support,
initial_hand0..3,
final_hand0..3, participant_count, participant_score0..3,
outcome, deciding_player
```

`initial_hand0..3` are each player's pip total immediately after the deal and
before the mandated opening tile is removed. They are the starting-hand
quality signal used by the lab's calibration report. For 2v2, the lab combines
the two partner values before correlating hand quality with the team result.

`depth_reached` is the deepest fully completed iterative-deepening depth.
`tt_hits` and `nodes` are search diagnostics. `exact_endgame` is set when the
late-endgame solver ran to the terminal instead of stopping at a heuristic
horizon.

## What it deliberately does not do yet

- No voluntary-draw policy: forced draws are resolved exactly, but the engine
  does not yet choose to draw proactively.
- No trainer, weight export, or Elo measurement. Those belong to `lab/`.
- No opening book. Both sides use the same search/evaluation; only the
  difficulty/search configuration differs.
- No Metal path in self-play yet. The standalone batch evaluator exists in
  `Accelerator/`; search integration is still pending.

Those are the next lab milestones, not hidden behavior.
