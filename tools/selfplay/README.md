# IsolynV2.0 Self-Play Generator

**Status:** working engine-vs-engine generator, updated 2026-11-16. It links
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

## Set-level matches (best-of-N to 151)

Round mode scores one hand and stops. Add `--sets-to-win 3` (or `4`) to play real
matches under the same `ScoreSystem` the bridge uses: each hand's participant
scores accumulate to the mode's target, the set winner is credited a set, scores
reset, and the match ends when someone reaches N sets. `--games` counts MATCHES
in this mode.

```bash
./tools/selfplay/build/selfplay \
  --mode 1v1 --sets-to-win 3 --games 100 \
  --depth 4 --determinizations 20 \
  --opponent-depth 4 --opponent-determinizations 20 \
  --seed 1 --output lab/data/setplay-1v1-set.csv
```

Two files are written: the match summary to `--output` (one row per match) and
the move rows to `<output>.rounds.csv`, which keeps the round-mode schema. In the
rounds file the `game` column is the match index, so hands from different sets
of the same match share it.

Match CSV:

```text
match, seed, mode, sets_to_win, target, rounds, incomplete,
winner_participant, winner_side, sets_a, sets_b, points_a, points_b,
set_wins_0..3, points_0..3
```

`sets_a`/`sets_b` attribute sets through the same A/B side mapping as round
mode. `points_` are cumulative across sets, not per set.

`--set-target 101` is valid only in 1v1. `--sprt-pairs` is round-scoped and is
rejected with `--sets-to-win`. Same seed and configuration reproduce both CSVs
byte for byte (checked with `cmp`).

### Sequential testing at match level

`--sprt-pairs N` also works in match mode. The cap becomes `2N` matches, each match
is one Bernoulli observation (a match cannot be drawn), and the verdict is read only
after an even number of matches, so every decision rests on an equal number of
A-first and B-first matches. `--sprt-elo0` / `--sprt-elo1` mean the same as in round
mode. `--sprt-pairs` is rejected for 1v1v1 matches, where a match has no single
score for A.

```bash
./tools/selfplay/build/selfplay \
  --mode 1v1 --sets-to-win 3 --sprt-pairs 200 \
  --sprt-elo0 0 --sprt-elo1 50 \
  --depth 4 --determinizations 20 \
  --opponent-depth 2 --opponent-determinizations 6 \
  --seed 3 --output /tmp/match-sprt.csv
```

Calibration: a known 65.5% matchup stopped at **100 matches** (64.0%, LLR 2.998)
where the fixed run needed 400. A mirror reached H0 at 118 matches. A mirror is not
guaranteed to decide before the cap — at p = 0.5 the LLR random-walks, so
"inconclusive" is a valid and common outcome. Accepting H0 means "no edge of
`--sprt-elo1` detected", not "the two are equal".

`--check` now also exercises the sequential arithmetic: Wald's bounds and both
verdicts.

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

Unused participant slots (when `participant_count` is below 4) are zero-filled
in both `participant_side*` and `participant_score*`. Always filter on
`participant_count` before reading them: a pad row carries side 0 and score 0 and
will otherwise overwrite a real side-0 score.

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

## Sequential testing (`--sprt-pairs`)

A fixed `--games` count pays the full price for every experiment, including the
ones whose answer is already unambiguous. `--sprt-pairs N` replaces the fixed
count with a sequential test: play until the evidence crosses a decision
boundary, or until N pairs (2N rounds) have been played.

```bash
./tools/selfplay/build/selfplay \
  --depth 8 --determinizations 64 \
  --opponent-depth 8 --opponent-determinizations 64 \
  --sprt-pairs 5000 --sprt-elo0 0 --sprt-elo1 5 --seed 1
```

**Model.** A round scores 1 (A wins), 0.5 (drawn or closed with equal scores) or
0 (A loses). The log-likelihood ratio accumulates against two Bernoulli
hypotheses — the score A would need against an equal opponent for a difference
of `--sprt-elo0` and `--sprt-elo1` — with Wald bounds at `alpha = beta = 0.05`:
accept H1 above `ln(19)`, accept H0 below `-ln(19)`.

**Seat balance.** Evidence is observed every round but only acted on at pair
boundaries, so every decision rests on an equal number of A-first and B-first
rounds.

**What it saves.** The saving is arithmetic, not a hope. At `elo0 = 0`,
`elo1 = 5`, a true +20 Elo effect drifts the LLR by about 7.1e-4 per round and
decides in roughly 4,100 rounds instead of 10,000; a true +40 Elo effect decides
in roughly 1,900. A null drifts at about -1.1e-4 per round, so it usually runs to
the cap — which is the honest outcome, not a failure.

**What it costs.** Counting a draw as half a win treats each round as if it
carried independent variance and so understates the true sample variance, which
makes a verdict arrive slightly sooner than a fully correct model would. The
bias is toward acting earlier, never toward inventing an effect, and it is
documented rather than hidden.

**Verified 2026-11-15.** Three runs were recomputed independently from their CSVs
with a Python reimplementation of the same statistic; mean score and LLR matched
to four decimals (0.5125 / 0.0512, 0.5075 / 0.0449, 0.4863 / -0.1997). Config
application was confirmed from the same CSVs: the depth-6 side averaged 13,141
nodes per decision against 6.2 for the depth-1 side.

**Not yet exercised.** No available engine contrast is large enough to cross a
boundary quickly, so every run above reached its cap. The early-stop path is
therefore verified by arithmetic and by the null runs, not by a real match that
stopped early.
