# Search Performance: Compact Transposition Table

**Status:** current, measured 2026-11-15. This is a performance result, not a
strength claim.

## What changed

The search used one `std::unordered_map<uint64_t, TTEntry>` per search lane,
growing to 250,000 entries and cleared wholesale on overflow. Every
`chooseBestMove` call constructed new contexts, reserved 4,096 buckets and then
paid for node allocations and a full table clear as the map grew.

The replacement is a compact, four-way set-associative table:

- 56 bytes per entry, keyed by the position hash;
- a generation stamp invalidates the previous search without walking the table;
- the table is owned by the persistent sample pool and reused across moves;
- one lane gets a table only when that lane is used;
- capacity follows the configured depth: 8,192 entries at 2/8, 16,384 at 3/16,
  32,768 at 4/24, and 65,536 for 5/40 and 8/64;
- a full bucket replaces its shallowest entry instead of clearing the table.

All rules, evaluation, sampling, move ordering, and root aggregation are
unchanged. The table is a cache, so the output check below verifies that its
replacement policy did not change decisions in this sample.

## Method

| Field | Value |
|---|---|
| Machine | Apple M3, 8 cores, 8 GB RAM |
| OS / compiler | macOS 27.2, Apple clang, C++20, `-O2` |
| Harness | `tools/selfplay`, 1v1, both sides at the same tier |
| Workload | 10,000 games per tier, seed 4100, 8 independent shards |
| Workers | one per shard; `--opponent-workers 1` |
| Memory | `/usr/bin/time -l`, maximum resident set size per shard |

The two arms are the baseline binary and the compact-table binary, run
sequentially with the same seeds and commands. Each tier covers 10,000 games,
so the sweep covers **50,000 games per arm** (884,216 decisions per arm).

Reproduction:

```bash
# Build the candidate.
./tools/selfplay/build.sh

# Run one arm (repeat with the baseline binary for the before arm).
python3 tools/bench/tiers.py \
  --binary tools/selfplay/build/selfplay \
  --games 10000 --shards 8 --seed 4100 --label compact \
  --output-dir lab/data/bench/2026-11-15-tt-compact

# Compare the two summary CSVs.
python3 tools/bench/compare.py \
  --before lab/data/bench/2026-11-15-tt-baseline \
  --after  lab/data/bench/2026-11-15-tt-compact
```

## Results

| Tier | Depth/worlds | Before games/s | After games/s | Speedup | Before wall | After wall | Before mean RSS | After mean RSS | Mean Δ | Before peak RSS | After peak RSS | Peak Δ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Casual | 2/8 | 1,101.04 | 4,338.08 | 3.94× | 9.1 s | 2.3 s | 8.4 MiB | 7.0 MiB | −16.6% | 13.6 MiB | 7.0 MiB | −48.0% |
| Club | 3/16 | 350.00 | 1,300.49 | 3.72× | 28.6 s | 7.7 s | 11.5 MiB | 7.5 MiB | −34.7% | 15.0 MiB | 7.5 MiB | −49.7% |
| Elite | 4/24 | 203.91 | 513.58 | 2.52× | 49.0 s | 19.5 s | 20.9 MiB | 8.4 MiB | −59.8% | 30.6 MiB | 8.5 MiB | −72.2% |
| Expert | 5/40 | 87.30 | 182.32 | 2.09× | 114.6 s | 54.8 s | 32.3 MiB | 10.3 MiB | −68.1% | 34.3 MiB | 10.4 MiB | −69.8% |
| Master | 8/64 | 15.06 | 20.16 | 1.34× | 664.1 s | 496.0 s | 37.0 MiB | 10.4 MiB | −71.8% | 37.2 MiB | 10.5 MiB | −71.7% |

- **Sum of tier wall times:** 14.4 min before, 9.7 min after.
- **Aggregate throughput:** 57.78 → 86.15 games/s (1.49×).
- **Nodes:** 23.26B → 21.55B (−7.3%). The Master tier alone fell from 20.65B to
  18.95B (−8.2%).
- **Peak RSS** is the largest per-shard maximum across the eight shards in a
  tier. Mean RSS is the arithmetic mean of those eight independent processes.

## Output parity check

Across all 50,000 games, every CSV field other than the diagnostic `nodes` and
`tt_hits` columns is identical between the two arms: move, side, player,
depth reached, exact-endgame flag, every evaluation component, and every game
outcome. A separate 12-game Master check at eight workers per side produced the
same non-diagnostic rows and outcomes as the one-worker run, exercising the
pool-owned tables on the parallel path. This is a regression check on the seeded
sample, not a strength claim.

## Limits

- One machine, one 1v1 self-play workload, one seed set.
- RSS is per shard process, not whole-system memory. In the app, table memory
  scales with the number of active search lanes, not with game count.
- The output parity check covers the seeded 50,000-game sample; it cannot prove
  parity on every position.
- No 1v1v1, 2v2, external-engine, or human-strength claim is made here.

Raw per-shard CSVs, logs and `/usr/bin/time` records remain under
`lab/data/bench/2026-11-15-tt-baseline` and
`lab/data/bench/2026-11-15-tt-compact` (gitignored lab data, retained locally).
