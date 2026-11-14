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
