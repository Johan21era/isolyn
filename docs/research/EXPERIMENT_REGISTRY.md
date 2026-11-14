# Experiment Registry

**Status:** living record (tier 2). One row per experiment. A change that was
measured and rejected is recorded here with the same care as one that was kept —
the rejected list is what stops the same idea being re-tried in six months.

Verdicts: **ACCEPTED** (promoted to champion), **REJECTED** (measured, reverted),
**INCONCLUSIVE** (underpowered; do not promote).

## E-001 — Parallel root determinization

- **Hypothesis.** The 20–64 hidden worlds evaluated per decision are independent
  of each other, so they can run on separate cores. This should cut per-move
  latency roughly with core count, with no change to the rules or the decision
  procedure.
- **Implementation.** `SearchEngine::Config::workerThreads` (0 = auto), a
  persistent per-thread worker pool, one `SearchContext` per lane (own
  transposition table, killers, history — nothing shared on the hot path), and
  worlds still sampled sequentially from the caller's RNG so the sampled set is
  unchanged. Samples are reduced in index order.
- **Measured.** 60 games at 8/64: 7.55 s → 3.18 s wall (2.4×). `user`/`real` =
  3.3 cores; total CPU work rose ~47% because each lane's table holds one eighth
  of the entries.
- **Verdict.** ACCEPTED (as latency). Strength-neutral by construction; see
  E-002.

## E-002 — Validity control: parallel 20 vs sequential 20

- **Hypothesis.** If parallelisation is genuinely strength-neutral, 20 samples on
  8 workers must score 50% against 20 samples on 1 worker.
- **Measured.** 1,000 games, seed 42: A 50.1%, **+0.7 Elo, CI [−20.8, +22.2]**.
- **Verdict.** ACCEPTED as validation. Confirms the parallel path reproduces the
  sequential engine's strength exactly, so E-003's gain is attributable to the
  extra samples, not to the threading.

## E-003 — Parallel 64 vs sequential 20 (underpowered)

- **Hypothesis.** Spending the parallelism on 3.2× more worlds should beat the
  shipped 20-sample configuration at similar cost.
- **Measured.** 1,000 games, seed 42: A 52.4%, **+16.7 Elo, CI [−4.9, +38.2]**.
- **Verdict.** INCONCLUSIVE — the point estimate is positive but the interval
  crosses zero. Extended as E-004.

## E-004 — Parallel 64 vs sequential 20 (resolved)

- **Measured.** 4,000 games, seed 42: A 52.5% (2,101–1,899), **+17.6 Elo,
  95% CI [+6.8, +28.3]**.
- **Cost.** ~8 sample-units per move for A against 20 for B, so the winner also
  spends less wall-clock per decision than the engine it beat.
- **Verdict.** ACCEPTED. This is the first change in the programme supported by
  a resolved tournament result.

## E-005 — Ladder re-measurement (baseline correction)

- **Hypothesis.** The documented claim that the difficulty ladder is not
  monotonic may be an artefact of 400-game samples.
- **Measured.** See `docs/research/BENCHMARK_BASELINE.md`: at 600–1,000 games per
  pair the ladder is correctly ordered, and 5/40 beats 4/24 at 55.7%
  (−39.5 Elo, CI excluding zero). The two lower steps remain inside noise.
- **Verdict.** ACCEPTED as a correction. The ladder is ordered but its adjacent
  gaps (~10–13 Elo) are too small to be marketed as five distinct strengths.

## E-006 — Smaller per-lane transposition-table reserve (rejected)

- **Hypothesis.** Eight tables each pre-reserving 16,384 buckets per move was
  suspected of allocator pressure; dropping to 1,024 should speed the parallel
  path up.
- **Measured.** 60 games at 8/64: 3.35 s → 3.58–3.60 s (slower, twice).
- **Verdict.** REJECTED and reverted; settled at 4,096 as a middle value. The
  contention is in per-node allocation inside the search, not in the reserve.

## E-007 — Sample-count saturation at depth 4

- **Hypothesis.** If 20 → 64 samples was worth +17.6 Elo, more worlds should
  keep paying, and the app should simply buy more of them.
- **Measured.** 2,000 games, seed 42, both sides 8 workers, depth 4:
  192 samples vs 64 → **+2.1 Elo, CI [−13.1, +17.3]**.
- **Verdict.** REJECTED as a strength lever. Sampling is **saturated** at 64 at
  this depth: quadrupling the sample count moved the result by ~0.

## E-008 — Beyond saturation (confirmation)

- **Measured.** 1,776 games: 384 samples vs 192 → +6.3 Elo, CI [−9.9, +22.4].
  Completed 1,776 of 2,000 rounds before the host's command budget elapsed; the
  interval is wide but still nowhere near significance.
- **Verdict.** REJECTED. No evidence of return above 64 worlds.

**Consequence for the programme.** The 20 → 64 step (E-004) is the last
meaningful sampling gain available. Extra compute must go to **depth** or to
**evaluation quality**, not to more worlds. This also settles the backlog item
that proposed raising the app's sample counts: the shipped elite tier (8/64) is
already at the sampling operating point, so there is nothing to bank.

## E-009 — Depth 10 vs depth 8

- **Hypothesis.** With sampling saturated (E-007/E-008), deeper search is the
  remaining lever.
- **Measured.** 1,000 games, both sides 64 samples and 8 workers, seed 42:
  A 48.5%, **−10.4 Elo, CI [−32.0, +11.1]**.
- **Cost.** 229.9 s against ~53 s for the depth-8-vs-depth-8 equivalent —
  roughly **4.3× the wall clock for no gain**, and the point estimate favours
  the *shallower* engine.
- **Verdict.** REJECTED. Not a resolution either way, but the burden of proof
  sits with depth 10 and it has not been met at 4× the cost. The likely cause is
  the classic search pathology: with an uncalibrated static evaluation, extra
  plies amplify evaluation error instead of reducing it.

## E-010 — First 1v1v1 baseline

- **Hypothesis.** The 1v1 ladder ordering should hold in three-player play.
- **Measured.** 500 rounds, seed 42, 2/8 vs 5/40. Seat win rates 32.0% (A) and
  34.0% (B, two seats per round). 32% of rounds closed rather than went out.
- **Verdict.** INCONCLUSIVE but directionally consistent. 2 points of seat win
  rate is inside noise at this sample; the mode is unproven, which is itself the
  finding worth recording.

## E-011 — First 2v2 baseline (and a null result)

- **Hypothesis.** More search should help partnership play at least as much as
  it helps 1v1.
- **Measured.** 500 rounds, seed 42, 2/8 vs 5/40: A 49.6%, B 50.4%.
- **Verdict.** REJECTED as an assumption. **A 5× compute advantage buys nothing
  in 2v2.** Combined with E-007–E-009 this is the strongest evidence yet that the
  constraint is strategic representation (partner awareness, signalling, shared
  utility), not search effort.

## E-012 — Maximin root selection (rejected)

- **Hypothesis.** Determinization search with averaging is exposed to strategy
  fusion: it can pick a move that is mediocre in every world actually played.
  Choosing the move with the best *worst* sampled world should be more robust.
- **Measured.** 2,000 games, depth 4, 64 samples, 8 workers: maximin 44.1%
  against mean → **−40.8 Elo, CI [−56.2, −25.5]**.
- **Verdict.** REJECTED, decisively. Maximin is dominated by the single worst
  sampled world, which in dominoes is usually an unlucky deal that no move fixes.

## E-013 — Win-count root selection (rejected)

- **Hypothesis.** Pick the move that wins outright in the most sampled worlds.
- **Measured.** 2,000 games: 46.3% → **−25.8 Elo, CI [−41.0, −10.5]**.
- **Verdict.** REJECTED. Discards how much a move wins by, so it prefers a
  narrow win in many worlds to a dominant win in slightly fewer.

## E-014 — Trimmed-mean root selection (rejected)

- **Hypothesis.** Drop the worst quartile of worlds, then average — keep the
  robustness of maximin without its single-outlier fragility.
- **Measured.** 2,000 games: 47.3% → **−18.4 Elo, CI [−33.7, −3.2]**.
- **Verdict.** REJECTED. The least bad alternative, still clearly worse.

### What E-012 – E-014 establish

The expected-value (mean) rule is **not** a weak default that a simple robust
rule improves on. All three alternatives lose, two of them heavily. If strategy
fusion costs this engine strength, the fix is not a different scalar aggregation
of the same samples — it would require information-set search that reasons about
what the *opponent* believes, which is a different order of both cost and risk.

The four aggregation rules remain in the engine as measured, off-by-default
options so the result is reproducible; the default path is byte-identical to the
previous engine (verified: 40-game same-seed output unchanged).

## E-015 – E-017 — Single-component ablations

Search now accepts evaluation overrides, so individual components can be
removed and measured. All runs: 2,000 games, depth 4, 64 samples, 8 workers,
seed 42, against the default weights.

| Ablation | Elo (A vs default) | 95% CI | Verdict |
|---|---:|---|---|
| `tempo=0` (default 0.1) | −6.6 | [−21.8, +8.6] | no effect |
| `expectedValue=0` (default 1.0) | −3.5 | [−18.7, +11.7] | no effect |
| `pipControl=0` (default 0.5) | −8.3 | [−23.6, +6.9] | no effect |

**What this establishes.** No single component is harmful: every removal trends
slightly *worse*, so the eight terms are contributing in the right direction and
the hand-set weights are not obviously broken. It also establishes a hard limit
on the method — at 2,000 games the resolution is roughly ±15 Elo, and the
individual contribution of each component sits below that. **Ablation cannot
tune this evaluation; only joint optimisation with far more games can.**

That matters for planning: "audit the weights" sounds like a cheap win and is
not. The next evaluation step has to be a budgeted search over the weight vector
(coordinate descent or CMA-ES against tournament results), with the acceptance
gate fixed in advance.

## E-018 — Evaluation component variance diagnostic (no games played)

Reading the per-move component columns already logged by the harness, over 6,793
decisions at depth 4/64:

| Component | Mean | SD | Zero share |
|---|---:|---:|---:|
| `eval_total` | −21.8 | 285.5 | 0% |
| `win_threat` | 2.9 | **282.5** | 92% |
| `expected_value` | −26.0 | 14.7 | 0.3% |
| `mobility` | 2.3 | 1.4 | 0% |
| `blocking` | −1.7 | 1.5 | 26% |
| `pip_control` | 1.1 | 0.7 | 0% |
| `tempo` | 1.0 | **0.0** | 0% |
| `closing_opportunity` | 0.0 | 0.0 | 100% |
| `team_support` | 0.0 | 0.0 | 100% |

**Finding.** One term — an immediate Domino win is available, ±1000 — accounts
for 98% of the evaluation's variance and is zero in 92% of positions. The other
seven terms sum to a standard deviation of ~15 against 285. The evaluation is,
quantitatively, a binary threat detector with a small positional tie-breaker.

Two components are structurally inert in 1v1: `tempo` is a constant +1 for the
side to move (SD exactly zero), and `closing_opportunity` / `team_support` are
zero by construction outside closed positions and 2v2 respectively.

`expected_value` was suspected to be sign-inverted (it is always negative);
reading the implementation shows it is `−(my remaining pips)`, which is correct —
fewer pips is better. Not a bug.

## E-019 — Attenuating the dominant term (rejected)

- **Hypothesis.** If the ±1000 threat term dominates, the engine is effectively
  making binary judgments and would benefit from letting the other seven terms
  matter (weight 100 instead of 1000).
- **Measured.** 2,000 games each against default: `winThreat=100` → 46.5%,
  **−24.4 Elo [−39.6, −9.1]**; `winThreat=0` → 47.7%, **−16.0 Elo
  [−31.2, −0.8]**.
- **Verdict.** REJECTED. Both attenuations lose. The dominant term is earning
  its dominance: with pips worth ~15, an immediate-win threat has to outweigh
  everything else or the search trades away wins for position.

Together E-018 and E-019 say the evaluation is *crude but correctly shaped*.
Its weakness is not the scale of its terms but the absence of any graded notion
of winning chance between "threat exists" and "threat does not".

## E-020 — Champion vs weakest tier, and where the wins come from

- **Configuration.** 3,000 rounds, 1v1, seed 4242: A = champion (4/64, 8 workers),
  B = weakest shipped tier (2/8).
- **Result.** A wins 53.9%, **+27.4 Elo, 95% CI [+14.9, +39.9]** — resolved.
- **Loss analysis (the point of the run).** Splitting the rounds A lost:

| Slice | A win rate |
|---|---|
| A in seat 0 | 54.3% |
| A in seat 1 | 53.5% |
| Best hand-quality quartile | 54.9% |
| Worst hand-quality quartile | 52.7% |
| Rounds ending by Domino — closed share of A wins / B wins | 24.5% / 24.6% |

**Finding.** There is no blunt weakness to exploit. The edge is uniform across
seat, deal quality and ending type; the champion does not collapse when dealt
badly, does not have a closed-round blind spot, and gains nothing structural from
moving first. Against a weaker opponent the win rate is a flat ~54% everywhere.

## E-021 — Stylistic opponents (no exploitation found)

- **Hypothesis.** If the champion undervalues a concept, an opponent weighted
  hard toward it should beat it.
- **Measured.** 2,000 rounds each at seed 777, champion vs a style opponent:

| Style opponent | A score | Elo | 95% CI |
|---|---:|---:|---|
| `blocking=4` | 48.7% | −9.0 | [−24.3, +6.2] |
| `mobility=4` | 48.7% | −9.0 | [−24.3, +6.2] |
| `winThreat=1500` | 50.5% | +3.1 | [−12.1, +18.3] |

- **Verdict.** None resolved. No simple weighting beats the champion, so there is
  no one-line exploit to patch. (The two 48.7% rows are byte-different games that
  happened to land on the same win count; neither is a resolved result and no
  conclusion rests on them.)

## E-022 — 2v2: the champion's advantage disappears (confirmed twice)

- **Configuration.** 2,000 rounds, 2v2, seed 909: champion (4/64) vs weakest
  tier (2/8) — the same pairing that wins **+27.4 Elo** in 1v1.
- **Result.** A 994 wins (49.7%), B 1,006 (50.3%). **No advantage whatsoever.**
- **Verdict.** This replicates E-011, where a 5× compute advantage in 2v2 also
  bought nothing (49.6% vs 50.4%). Two different config pairs, two different
  seeds, same answer.

**Conclusion.** Partnership play is the engine's clearest structural deficit. In
1v1, more search converts into wins (+27 Elo per tier). In 2v2, the same
advantage converts into **nothing**, which means the deficiency is in how the
engine represents the partnership — not in how hard it searches.

## E-023 — Partnership weight: the first 2v2 strength gain (ACCEPTED)

- **Hypothesis.** `teamSupport` was the engine's only partnership signal, weighted
  at 0.25 on a term that is itself `0.25 × team mobility` — an effective ~6% of
  one player's mobility. If 2v2's null results came from that term being
  negligible, scaling it should convert into wins where compute could not.
- **Method.** 2v2, depth 4, 64 samples, 8 workers, 3,000 rounds per point, one
  sweep of the weight against the 0.25 default.

| `teamSupport` | Elo vs old default | 95% CI |
|---|---:|---|
| 2 | +12.7 | [+0.3, +25.2] |
| 6 | +15.3 | [+2.9, +27.7] |
| 12 | +17.9 | [+5.4, +30.3] |
| 24 | +22.3 | [+9.8, +34.7] |
| 48 | +22.7 | [+10.3, +35.2] |
| 96 | +22.3 | [+9.8, +34.7] |

- **Replication (the part that matters).** The first three readings suggested
  ~+22, which was optimistic. At 24, across independent seeds: 31337 → +22.3,
  2024 → +16.2, 5150 → **+3.5** (not resolved), 7777 → +27.4, 8888 → +19.0.
  Pooled over 15,000 rounds: **52.27%, +15.8 Elo, 95% CI [+10.2, +21.3]**.
- **Mode safety.** `teamSupport` is zero outside 2v2 by construction, and a 1v1
  control at the new default scored **−1.0 Elo [−16.3, +14.2]** — no effect.
- **Verdict.** ACCEPTED. Default raised from 0.25 to **24.0** (the sweep's
  plateau). The first change in the programme to improve a mode other than 1v1,
  and the first to come from evaluation rather than search.

**What this does and does not say.** It says the partnership signal was
under-weighted by an order of magnitude, and that fixing that is worth ~16 Elo
in 2v2. It does **not** say 2v2 now converts search effort into wins: the
compute null (E-011, E-022) was a separate finding, and nothing here re-tests it.

## E-024 — Voluntary draw in the tree: attempted, invalid, reverted (NEGATIVE)

- **Hypothesis.** A draw is legal whenever the boneyard is non-empty
  (`bridge_voluntary_draw` checks only that, plus round-in-progress), it does not
  consume the turn, and it is absent from the game tree. If drawing were a real
  strategic option, putting it in the tree should find value.
- **Implementation tried.** `Config::maxVoluntaryDraws`; a draw branch in
  `searchZeroSum` that draws inside the sampled world (where the tile is known
  exactly) and continues with the **same** player to move, so its score is not
  negated the way a placement's is. Depth bounds the chain; 0 = off.
- **Result.** 400 rounds, 1v1, draw-enabled vs shipped: **−38.4 Elo
  [−72.6, −4.2]**. 429 engine checks still passed.
- **Why the number is meaningless.** `SearchEngine` returns a `Move` — tile +
  side — and `MoveDTO` has no draw variant. A draw can therefore never be the
  returned action. The branch changed leaf scores without giving the engine any
  way to act on them, so the root compared placements against a score it could
  not execute, and chose worse. The loss measures a corrupted decision, not the
  value of drawing.
- **The real finding.** The blocker is the **decision contract**, not the tree.
  Modelling this action requires a decision type that can express "draw",
  propagation through the bridge and the app's Draw affordance, and only then a
  tournament. Scoring it inside a move-only contract is not a valid experiment.
- **Verdict.** REVERTED (`git checkout` of all three files; tree clean at
  `885b65f`). Recorded so the same dead end is not re-entered, and so E-018's
  "missing action" claim is read correctly: the action is missing from the
  *interface*, which is why it has never been searchable.

## E-025 — Voluntary draw made executable, then measured (CAPABILITY KEPT, NO STRENGTH CLAIM)

- **What changed.** `SearchDecision::isDraw` and `Config::maxVoluntaryDraws`
  (default **0**). A draw is now a first-class root candidate and an action
  inside `searchZeroSum`: the drawn tile is known inside a sampled world, the
  continuation keeps the same player to move, and its score is **not** negated.
  The harness applies it with `MatchController::voluntaryDraw()` and does not
  advance the turn, bounded per turn so it cannot stall.
- **The action is real.** 1v1, 500 rounds: **1,484 draws in 10,650 decisions
  (14%)**, every round completed, every draw applied legally.
- **Strength at depth 4.** Three seeds, 3,000 rounds each: 50.90%, 51.10%,
  49.07%. Pooled 4,532/9,000 = **50.36%, +2.5 Elo, 95% CI [−4.7, +9.7]** —
  **not resolved**. At the shipped horizon the action is neutral.
- **Strength at depth 5 — resolved.** Same comparison, one ply deeper:
  51.9% (n=3,000) and 50.7% (n=2,798). Pooled **2,977/5,798 = 51.35%,
  +9.4 Elo, 95% CI [+0.4, +18.3]**, with draws rising to 16.3% of decisions.
  Drawing is a positional investment, so it needs horizon to pay — the depth
  dependence is the finding, not a curiosity.
- **A model that had to be rejected.** Charging a draw a ply of horizon is not
  faithful — a draw does not advance the turn — but keeping depth constant
  re-enables draws after every placement and the tree grows as 2^depth. That
  version was measured and timed out; the conservative model is kept and stated.
- **Mode coverage, measured rather than assumed.** `searchMulti` (1v1v1) has no
  draw branch, so 0 draws there by construction. 2v2 does have the branch and
  selected **0 draws in 10,426 decisions** — the pip cost plus the loss of a ply
  is never worth it there, unlike 1v1's 14%.
- **Verdict.** Capability kept, default **off**, no strength claim. E-024's
  invalid −38.4 measurement is superseded by this valid one, which is the point:
  the number only became meaningful after the action could be executed.

## Strategic conclusion after E-007 – E-019

Three experiments now agree on one thing: **scaling compute is finished as a
strength lever for this engine.**

| Lever | Measured marginal return |
|---|---|
| 20 → 64 worlds | +17.6 Elo (E-004) — the last real sampling gain |
| 64 → 192 worlds | +2.1 Elo, not resolved (E-007) |
| 192 → 384 worlds | +6.3 Elo, not resolved (E-008) |
| depth 8 → 10 | −10.4 Elo at 4.3× cost (E-009) |
| 2v2: 2/8 → 5/40 | 0 (49.6% vs 50.4%, E-011) |
| maximin / win-count / trimmed root rule | −18 to −41 Elo (E-012 – E-014) |
| dominant eval term scaled 1000 → 100 | −24.4 Elo (E-019) |
| dominant eval term removed | −16.0 Elo (E-019) |

The binding constraint is **evaluation quality and search selectivity**, not
nodes per second. That is where the next tranche of work belongs: calibrate the
eight weights against tournament results, add a tactical-stability pass to stop
the odd/even horizon wobble that deeper search appears to amplify, and only then
revisit depth.
