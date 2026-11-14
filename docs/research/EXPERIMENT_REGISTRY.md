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

## Strategic conclusion after E-007 – E-011

Three experiments now agree on one thing: **scaling compute is finished as a
strength lever for this engine.**

| Lever | Measured marginal return |
|---|---|
| 20 → 64 worlds | +17.6 Elo (E-004) — the last real sampling gain |
| 64 → 192 worlds | +2.1 Elo, not resolved (E-007) |
| 192 → 384 worlds | +6.3 Elo, not resolved (E-008) |
| depth 8 → 10 | −10.4 Elo at 4.3× cost (E-009) |
| 2v2: 2/8 → 5/40 | 0 (49.6% vs 50.4%, E-011) |

The binding constraint is **evaluation quality and search selectivity**, not
nodes per second. That is where the next tranche of work belongs: calibrate the
eight weights against tournament results, add a tactical-stability pass to stop
the odd/even horizon wobble that deeper search appears to amplify, and only then
revisit depth.
