# Strength Baseline — the only home for playing-strength claims

> **Status: living measurement record (tier 2). Started 2026-11-14, empty on
> purpose.** The rulebook changed on 2026-11-14 and every earlier strength figure
> became a measurement of a different game. Those live on deliberately stamped
> **VOID** in `PROJECT_OVERDRIVE.md`, `EXPERIMENT_REGISTRY.md` and
> `BENCHMARK_BASELINE.md`; none of them may be quoted as current.

**Rules version:** `79ca7387ac7ac5b85b93b4cee3818defaf4a1d3f406c0d6186edbc60261cfd55`

> The normative rule text is unchanged from the 2026-11-14 dictation. This seal
> reflects the implementation-status corrections (R-06, R-07, R-15, R-17, R-18
> and R-22 now ENFORCED; R-17's public reveal removed; R-12's assertion updated); it is not a
> rule change, and it does not invalidate measurements of the same rule text.

**Current strength claim: none.** No engine configuration has been measured under
these rules. The champion label (depth 8, 64 samples, 8 workers) is a label from
the previous rule set and has not been re-earned.

## Measured search depth under the 15-second budgets (not a strength claim)

On 2026-11-15, four fixed 1v1 openings (seeded decks, misdeals rejected) were
searched with 8 workers, `endgameTileLimit = 8`, the configured sample counts,
the R-15 root-draw policy (one draw at the current decision, re-search after
it), and the deep-tier PVS/LMR search path:

| Tier | Samples | Completed depth (4 positions) | Elapsed |
|---|---:|---:|---:|
| Legendary | 80 | 24, 24, 24, 24 | 15,000 ms budget; all finished early |
| Mythical | 160 | 27, 26, 26, 27 | 15,000 ms budget |

Reproduce with `./scripts/ci/depth_probe.sh 80 4 15000` (the script also runs
the 160-sample tier). The probe uses fixed seeded decks, not fresh entropy, so
the same four openings are measured on repeat runs.

This is a depth measurement, not a strength result. **Mythical's configured 48
is a search ceiling, not a normal game depth:** a double-six hand has at most
28 tiles, and every placement or voluntary/forced draw consumes one (27 tile
actions in 1v1v1, where 0-0 is removed; passes add plies but no tiles). The
Legendary completed its configured 24-ply ceiling on all four positions.
Mythical did not reach 48; it completed 26–27 plies. The tier labels must not be
described as having reached 48, and a deeper Mythical setting needs a real
strength measurement before it can be called stronger than Legendary.

## What changed, and why the old numbers do not transfer

The rulebook now says:

- the winner of a hand is credited with the loser's total (R-03, R-05), where the
  old implementation let the losing hand accumulate its own points;
- the double blank is worth ten alone and zero when paired (R-19);
- 1v1v1 plays to 151, not 101 (R-06), and a player who reaches it is eliminated
  into a carried-points 1v1 (R-22);
- drawing is unlimited once the first draw of a hand has happened (R-15; the
  live turn has no cap, while one search decision evaluates at most one draw
  and re-searches after it, because a draw leaves the same player to move).

`ClosingOpportunityHeuristic` had its sign inverted to match the new meaning of
`roundScores`. That single line changes how the engine judges a close, so the
configurations measured against the old sign are not the configurations running
now.

## Protocol for any number recorded here

1. Fix the rules version: the hash above must equal `docs/rules/RULES_VERSION`.
2. Fixed seed, alternating seats, and at least 1,000 rounds before believing
   anything.
3. Report the 95% interval, not the win rate. A 52% result with ±20 Elo is not a
   result.
4. State depth, determinizations, worker count and wall-clock cost.
5. Run `./scripts/ci/local.sh` first: a strength number from a tree with failing
   correctness checks is not admissible.

`scripts/rules_audit.py` enforces the first point mechanically: change the
rulebook and this file fails the gate until it is re-measured under the new hash.

## The tomorrow run — plan before games

The harness is `tools/selfplay/build/selfplay` (see
[`../../tools/selfplay/README.md`](../../tools/selfplay/README.md)). One
head-to-head pair:

```bash
./tools/selfplay/build/selfplay \
  --games <N> --mode 1v1 \
  --depth 8 --determinizations 64 \
  --opponent-depth 4 --opponent-determinizations 24 \
  --time-ms 100 --seed <S> --output lab/data/h2h-<label>.csv
```

**Volume, stated honestly.** Recorded timings on this machine are roughly 53 s
per 1,000 rounds at depth 4 and about 230 s per 1,000 at depth 8. At those rates
one million rounds is on the order of 15 hours at depth 4 and 2.7 days at depth
8; ten million is roughly six days and four weeks respectively. A 5–10 million
game run is therefore a multi-day job, not an overnight one, and it should be
split by seed and mode rather than launched as a single command.

Recommended order for tomorrow:

1. **Timing run, 1,000 rounds**, same configuration as the real run. This
   replaces the estimates above with a measured rate on the current machine.
2. Choose N from that rate and the time actually available, then run in seeded
   chunks so a crash costs one chunk.
3. Record the result here with its interval, then — and only then — decide
   whether the champion label survives.

## Results

None yet. This section stays empty until a run completes under the hash above.

## E-101 — Compact transposition key (2026-11-15)

**Verdict: no detectable strength effect. The mechanism engaged; the strength did not.**

`GameState::hash()` mixed the whole move list into the transposition key, but the
only consumer of that history is `RulesEngine::determineCloser`, which reads two
facts: who played last, and (in 1v1) who played the most recent non-double.
`TranspositionKeyMode::CloserSummary` keeps exactly those and drops the rest, so
positions reached by different move orders share an entry.

| Field | Value |
|---|---|
| A configuration | depth 8, 64 determinizations, `TranspositionKeyMode::CloserSummary` |
| B configuration | depth 8, 64 determinizations, `TranspositionKeyMode::FullHistory` |
| Rounds | 9,960 (10 seeds: 101–110, one shard cut at 960) |
| A score | 0.50467 |
| **Elo (A − B)** | **+3.2, 95% CI [−3.6, +10.1]** |
| SPRT (θ = 5 Elo, α = β = 0.05) | LLR 0.307, undecided |

**Mechanism check** (same runs, so this isolates whether the change did anything):
1,633 TT hits per decision for the compact key against 31.6 for the full key —
**52× more** — and 97,390 nodes per decision against 121,143, **20% fewer**.

So the key behaves exactly as designed and the search gets a fifth cheaper per
decision, and the win rate moves by an amount the interval cannot distinguish
from zero. This is evidence for the reading that the engine is **resolution-starved
rather than node-starved**: it does not need more search, because more search is
not what its evaluation can use.

**Caveat that must travel with this number.** Depth was fixed and there was no
time limit, so saved nodes were simply not spent. Under the 15-second budgeted
tiers those nodes would convert into depth, and this measurement says nothing
about that case. Re-running with `--time-ms 15000` per side is the test that would
close that gap; it has not been done.

Reproduce:

```bash
./tools/selfplay/build/selfplay --depth 8 --determinizations 64 \
  --opponent-depth 8 --opponent-determinizations 64 --games 1000 \
  --tt-key closer --opponent-tt-key full --seed 101
```

## E-102 — What the positional evaluation is actually worth (2026-11-15)

**Verdict: the seven positional terms are worth about 15 Elo in total. The
two-regime design is not worth pursuing, and it is not being adopted.**

The engine's evaluation is a ±1000 step function (an immediate domino) plus seven
small terms that are the only signal in the 92% of positions where no step fires.
A two-regime evaluation -- a second weight vector for those quiet positions -- was
designed to give that field its own shape.

Rather than test the design directly, this measures its **ceiling**: how much are
those seven terms worth at all? Side B keeps the standard vector when a domino is
available and is given **every weight zeroed** when it is not, so in quiet
positions its evaluation is exactly zero. Side A is the shipped engine.

| Field | Value |
|---|---|
| A configuration | depth 8, 64 determinizations, shipped weights |
| B configuration | depth 8, 64 determinizations, positional weights all zero |
| Rounds | 3,000 (seeds 201–203) |
| A score | 0.52100 |
| **Elo (A − B)** | **+14.6, 95% CI [+2.2, +27.0]** |

**Wiring was proven before the number was read**, because a null here would
otherwise be indistinguishable from a broken flag: the harness echoes both sides'
regime settings at startup, and all eight leaf-evaluation call sites in
`SearchEngine.cpp` pass the second vector (`grep -n "evaluateAll("` shows the
pointer at each one).

**What this means.** Any reweighting of those seven terms -- conditional or not --
operates on a quantity worth roughly 15 Elo end to end. The best possible outcome
of the two-regime programme was a fraction of that, which is below the ruler's
resolution for a realistic effort. The machine stays in the tree, default off, as
an instrument; the *idea* is retired.

**What it points at instead.** The engine is not short of search (E-101) and not
short of positional tuning (E-102). It is short of **any graded signal at all** in
the quiet majority of positions. That is a term that does not exist yet, not a
weight that needs moving.

Reproduce:

```bash
./tools/selfplay/build/selfplay --depth 8 --determinizations 64 \
  --opponent-depth 8 --opponent-determinizations 64 --games 1000 \
  --opponent-conditional-weights \
  --opponent-positional-weights mobility=0,blocking=0,expectedValue=0,\
closingOpportunity=0,winThreat=0,pipControl=0,tempo=0,teamSupport=0 --seed 201
```

## E-103 — Exact endgame solving, two tiles earlier (2026-11-16)

**Verdict: no detectable effect. Perfect play from ten remaining tiles is worth
the same as perfect play from eight, at twice the cost.**

The search stops estimating and solves the sampled world exactly once the
boneyard is empty and at most `endgameTileLimit` tiles remain across all hands.
Raising that limit replaces heuristic endgame judgement with proof. This is a
different kind of change from a weight or a depth setting: it cannot make the
evaluation wrong inside the solved region, only outside it.

| Field | Value |
|---|---|
| A configuration | depth 8, 64 determinizations, `endgameTileLimit = 10` |
| B configuration | depth 8, 64 determinizations, `endgameTileLimit = 8` |
| Rounds | 3,302 (seeds 301–303, one shard cut at 802) |
| A score | 0.50091 |
| **Elo (A − B)** | **+0.6, 95% CI [−11.2, +12.5]** |
| Cost | 100 rounds: 7 s at limit 8, 13 s at 10, 23 s at 11, 57 s at 12 |

The interval excludes anything above +12 Elo. With 3,302 rounds it does not
exclude a small gain; it does exclude the kind of gain that would justify paying
twice for every endgame decision.

**Why this matters more than another null.** Combined with E-101 (a 52× better
transposition table: no effect), E-102 (the entire positional evaluation: ~15 Elo)
and the earlier depth result, four independent levers now measure zero or nearly
zero. The engine's decisions are remarkably insensitive to *how well it searches
and how well it scores positions*. That is not what a weak-but-tunable engine
looks like; it is what an engine whose decisions are dominated by something else
looks like.

The remaining explanation the data supports is that the handcrafted evaluation
family has been mined out. The next step that can plausibly move the number is
not another term or another ply: it is **fitting the weights to outcomes** rather
than choosing them by hand, using the per-decision evaluation breakdowns and
per-round results the tournament already writes.

**Caveat.** One shard was cut at 802 rounds by a command timeout; shards are
independent seeds, so the pooled figure is valid, but the sample is 3,302 rather
than the 4,000 planned.

## E-104 — Weights fitted to outcomes, and why they lose (2026-11-16)

**Verdict: the evaluation does predict round outcomes (AUC 0.65), but transplanting
the fitted coefficients into the search costs −9.2 Elo [−21.6, +3.2]. The two
objectives are not the same one.**

Every self-play row records the eight evaluation terms from the acting player's
view, and every round records its winner. `scripts/fit_weights.py` fits a logistic
model of "this side wins the round" over those terms by gradient descent on
standardised features.

| Field | Value |
|---|---|
| Decisions fitted | 30,000 sampled deterministically from 286,597 |
| Files | 17 local self-play CSVs |
| Acting-side win rate | 0.5081 |
| Log-loss | 0.64411 |
| **AUC** | **0.6546** |

Contribution to the logit, `coefficient x feature sd` — the only fair comparison
between a ±1000 term and a 0..7 term:

| Term | Contribution sd |
|---|---|
| `winThreat` | 139.50 |
| `expectedValue` | 7.18 |
| `mobility` | 0.15 |
| `pipControl` | 0.08 |
| `blocking` | 0.014 |
| `closingOpportunity`, `tempo`, `teamSupport` | 0 (constant in this log) |

Fitted weights, normalised to `expectedValue = 1`: `mobility=2.28`,
`blocking=0.18`, `pipControl=4.56`, `winThreat=0.039`.

**Measured in play**, keeping `winThreat = 1.0` (attenuating it is already known
to cost Elo) and `closingOpportunity = 1.0` (too few closed positions to estimate):
3,000 rounds, depth 8/64, seeds 401–403 → **score 0.48683, −9.2 Elo
[−21.6, +3.2]**.

**The diagnosis.** A coefficient in this model answers "given this position, how
often does this side win?" The search does not ask that question; it asks "which
move is better than its siblings?" A feature can be highly predictive of the final
result and still be a poor *ranking* signal across plies, and the threat term is
the clearest case: it is a step that the search converts into an actual win one
ply later, so its honest proportional weight inside the tree is far larger than a
saturated logistic coefficient suggests.

**Structural finding worth keeping.** Three terms are *constant* in this log, so no
amount of data can estimate them here: `tempo` is always 1 because the evaluator is
called for the player to move; `teamSupport` is always 0 in 1v1; and
`closingOpportunity` is 0 outside the rare closed position. Their zero coefficients
are an artefact of the logging, not a statement about their usefulness.

**What this rules out,** for the price of one afternoon: fitting weights to
round outcomes is not the path. What remains is tuning against the objective the
engine is actually judged by — self-play results — where each candidate weight set
is scored by wins, not by correlation.

Reproduce: `python3 scripts/fit_weights.py '/tmp/tt_s1*.csv' '/tmp/egA*.csv' '/tmp/cw_blind2*.csv' --max-rows 30000`

## E-105 — The objective is flat in weight space (2026-11-16)

**Verdict: perturbing the positional weights by up to ±40% changes what the search
explores and never changes what it plays. 350 decisions, 350 identical moves.**

E-101 through E-104 each measured "no effect" and left the reason open. This one
closes it, by looking at the engine's decisions instead of its results.

Two weight sets differing on `mobility`, `blocking`, `pipControl` and
`closingOpportunity` by up to ±40%, identical seed, depth 8 / 64 determinizations:

| Measurement | Result |
|---|---|
| Decisions compared | 350 |
| Identical chosen move | **350 / 350** |
| Identical node count | 215 / 350 |
| Different search tree, same move | 135 / 350 |

The node counts are the important half. The engine *did* explore differently —
the evaluation shifted, move ordering shifted, pruning shifted — and the selected
move did not move once. The decision is not "the evaluation ranking with noise on
top"; it is determined by something the positional terms never reach.

**What that something is.** `winThreat` contributes 139.5 logit units against
0.15 for mobility and 0.014 for blocking (E-104). An immediate domino is worth
orders of magnitude more than any positional consideration, so the search's
decision margin is saturated by threat detection, and every other term sits below
the granularity of a choice. The engine is, in effect, a threat solver with a
positional tiebreak that almost never fires.

**Why this retires a whole class of work.** Any method that searches weight space —
logistic fitting (E-104, −9.2 Elo), grid search, SPSA, gradient-free tuning — is
optimising a **piecewise-constant** objective. Candidates separated by ±40% play
byte-identical games, so every gradient estimate is exactly zero and every
comparison is a coin flip. Measured directly: an SPSA iteration at
`c = 0.39` produced a paired difference of **+0.0000 (SE 0.0000)** over 200 rounds,
because both arms were the same game.

`scripts/tune_weights.py` is kept — it is correct, resumable and logged — but it
cannot succeed while the objective is flat, and the flatness is a property of the
engine, not of the tuner.

**What this means for "smarter".** The plateau is not a tuning problem. The
decision procedure has to change so that evaluation can influence a choice at all:
the search must be made to distinguish lines that its threat term currently
collapses to equal. Until then, every additional evaluation term, ply, or table
optimisation is measured work with a known-zero expected return.

Reproduce: `--weights` with the two sets in this section at `--seed 77`, then
compare `move` (identical) and `nodes` (differing).

## E-106 — A two-tier root decision (2026-11-16)

**Status: UNRESOLVED. The point estimate is positive and the mechanism is proven,
but the interval crosses zero. Do not cite this as an improvement.**

E-105 showed that perturbing the evaluation changes the search tree and never the
chosen move: the dense positional terms are nearly constant across sampled worlds,
so they cancel in the average while the sparse threat term supplies the variance.
The fix is not a weight but a decision rule — `Config::positionalBand`. Candidates
within the band of the best sampled value are treated as equivalent, and the tie is
broken by a positional-only evaluation of the **real** position, which no averaging
can erase.

**The mechanism engages**, unlike every weight change measured so far:

| Change | Decisions altered |
|---|---|
| Weights ±40% (E-105) | 0 / 350 |
| `positionalBand = 2` | first change at decision 338 of 3,561 |
| `positionalBand = 10` | first change at decision 124 |

**Measured** (A = banded engine at side 0, B = default; depth 8 / 64):

| Setting | Rounds | Score | Elo |
|---|---|---|---|
| band 2 | 3,000 | 0.51200 | **+8.3 [−4.1, +20.8]** |
| band 10 | 2,897 | 0.50121 | +0.8 [−11.8, +13.5] |

The effect is **not dose-dependent**: a wider band scores worse, which is what the
design predicts (a band wide enough to override genuine value differences gives
value away). Only the narrow band is a candidate.

**Why it is not resolved.** At 3,000 rounds the interval is ±12 Elo; a +8 Elo
effect needs roughly 9,000–12,000 rounds to exclude zero. Two further shards
(941 rounds) were collected but a host failure prevented pooling and completion.
The flag defaults to `0.0`, so shipped behaviour is unchanged.

**Next:** pool the partial shards, extend band 2 to ~12,000 rounds, and only then
promote it. A preliminary +8 Elo is exactly the size of result this project has
learned to distrust.
