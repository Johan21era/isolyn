# Strength Baseline — the only home for playing-strength claims

> **Status: living measurement record (tier 2). Started 2026-11-14, empty on
> purpose.** The rulebook changed on 2026-11-14 and every earlier strength figure
> became a measurement of a different game. Those live on as superseded history
> in `PROJECT_OVERDRIVE.md`, `EXPERIMENT_REGISTRY.md` and
> `BENCHMARK_BASELINE.md`; none of them may be quoted as current.

**Rules version:** `9ce8aee81a8a8d24f3b4a91638ebc62e70350ce44843611c975c6c8a30dd9d74`

**Current strength claim: none.** No engine configuration has been measured under
these rules. The champion label (depth 8, 64 samples, 8 workers) is a label from
the previous rule set and has not been re-earned.

## What changed, and why the old numbers do not transfer

The rulebook now says:

- the winner of a hand is credited with the loser's total (R-03, R-05), where the
  old implementation let the losing hand accumulate its own points;
- the double blank is worth ten alone and zero when paired (R-19);
- 1v1v1 plays to 151, not 101 (R-06), and a player who reaches it is eliminated
  into a carried-points 1v1 (R-22);
- drawing is unlimited once the first draw of a hand has happened (R-15, still a
  gap in code).

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
