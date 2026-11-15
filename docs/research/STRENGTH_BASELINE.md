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
