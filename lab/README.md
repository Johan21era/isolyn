# IsolynV2.0 Offline Lab

**Status:** the C++ self-play generator is real, supports head-to-head search configurations, and emits per-move calibration data. `isolyn-lab evaluate` streams a CSV once and produces a real calibration report with Wilson intervals and Spearman correlations. `./scripts/lab run` drives resumable sharded multi-million-game runs. The Python trainer and weight export are still scaffolds; the Elo report itself is implemented.

This directory is the home for offline self-play, calibration, and (later) learned-evaluation experiments. It is deliberately **outside the shipped app**: Python is a tooling language here, never a runtime dependency of IsolynV2.0.

## Boundary

- The C++ engine remains the single source of truth for rules, legality, and scoring.
- Python may read engine output and produce datasets, reports, and weights.
- Python must never reimplement a game rule to “help” the engine.
- The C++ self-play harness in `tools/selfplay/` is the bridge between the engine and this lab.
- Trained artifacts must be exported as data (for example JSON or ONNX) and consumed by C++ inference.

This is the same split Monarcha uses: a deterministic C++ engine, with Python confined to the research/training side.

## Layout

```text
lab/
├── configs/
│   └── selfplay.example.toml   # planned experiment shape
├── data/                       # generated datasets/weights (gitignored)
├── src/isolyn_lab/
│   ├── __init__.py
│   ├── dataset.py              # streaming per-move CSV -> per-game records
│   ├── calibration.py          # win rates, score deltas, Spearman report
│   └── cli.py                  # selfplay guidance + evaluate command
├── pyproject.toml              # no runtime deps; optional training extras
└── README.md
```

The engine-side harness lives separately at `tools/selfplay/`; it is C++ so it can link the real engine without a second rules implementation.

## Quick start

```bash
# Build the real C++ self-play generator.
./tools/selfplay/build.sh
./tools/selfplay/build/selfplay --check
./tools/selfplay/build/selfplay --games 1 --depth 2 --determinizations 2 \
  --time-ms 50 --seed 7 --output lab/data/selfplay.csv

# Head-to-head: A is depth 3/16, B is depth 4/24, sides alternate per game.
./tools/selfplay/build/selfplay --games 200 --mode 1v1 \
  --depth 3 --determinizations 16 \
  --opponent-depth 4 --opponent-determinizations 24 \
  --seed 7 --output lab/data/h2h.csv

PYTHONPATH=lab/src python3 -m isolyn_lab.cli evaluate --input lab/data/h2h.csv

# Lab unit tests (no third-party runner required).
PYTHONPATH=lab/src python3 -m unittest discover -s lab/tests

# Optional Python environment for future training work.
python3 -m venv lab/.venv
source lab/.venv/bin/activate
pip install -e 'lab[train]'
isolyn-lab selfplay --dry-run
```

`isolyn-lab selfplay` without `--dry-run` exits with code 2 and prints the intended next step. That is intentional: the scaffold must not pretend a trainer exists.

## Large runs (resumable)

A multi-million-game run is one command. It is split into shards, run with
bounded parallelism, verified shard by shard, and replayed where it did not
finish.

```bash
./scripts/lab run --games 5000000 --mode 1v1 --depth 8 --determinizations 64
./scripts/lab run --games 5000000 --mode 1v1 --depth 8 --determinizations 64 --dry-run
./scripts/lab status 1v1-d8x64-n5000000-s1
./scripts/lab list
./scripts/lab stop 1v1-d8x64-n5000000-s1
./scripts/lab doctor
./scripts/lab clean --probes --yes
./scripts/lab merge 1v1-d8x64-n5000000-s1

# Calibration reports: one or several CSVs in a single run.
./scripts/lab evaluate --json \
  --input lab/data/runs/a/merged.csv \
  --input lab/data/runs/b/merged.csv
```

`evaluate --json` is what the app's **Analyses** tab reads: an array with one
report per input (games, decisions, outcomes, per-player win rates with Wilson
intervals, Elo with a confidence interval when both sides are present, and the
starting-hand correlations). Without `--json` the same report prints as text.

`run --dry-run` validates the configuration and prints the shard/seed plan
without creating a directory. `doctor` checks the harness, free disk, active
and dead locks, probe storage and manifest readability. `stop` signals only a
pid whose command line is this lab's runner. `clean --probes` removes only
regenerable warm-up runs; `--stale-locks` removes dead lock files; neither
touches a real run.

The read path is now linear. `dataset.iter_games` keeps one game in memory, and
`calibration.analyze` accepts that iterator instead of requiring a list. The
correlations are exact weighted-rank results over `(starting pips, result)`
counts, so memory scales with the distinct value pairs, not with the number of
games. Measured on the development M3, reading and analyzing a synthetic
200,000-game / 1,000,000-row CSV (55 MB) took **3.27 s** with **12.6 MB** peak
RSS. The old read-and-analyze path took **2.64 s** for a 1,000-game / 17,038-row
CSV; the new path takes **0.08 s** on the same file. These are pipeline timings,
not self-play throughput and not a strength claim.

Shard merge copies each CSV line and rewrites only `game,seed` instead of
re-serializing every column, then replaces `merged.csv` atomically. On a
synthetic 1.6-million-row / 84 MB merge: **2.46 s → 1.17 s**, line-identical
output. `evaluate` streams the merged file, so the old 2 GiB in-memory warning
no longer applies.

Self-play throughput is unchanged and remains the dominant cost. Measured on
the development M3 with **both sides** at depth 8 / 64 determinizations: ~23
games/s with eight single-worker shards. Five million games is therefore roughly
61 hours and about 9.5 GB of CSV (~1.95 KB per game).

**Side B defaults to side A.** The C++ harness on its own defaults the opponent
to depth 4 / 20 samples, which silently makes a "depth 8 / 64 self-play" run a
comparison of two configurations — half its moves weaker. The runner passes B's
configuration explicitly, resolving it to A unless `--opponent-depth` or
`--opponent-determinizations` says otherwise. Earlier throughput numbers taken
before this was fixed were measured against the weaker default and were too fast.

- Run ids default to `<mode>-d<depth>x<det>-n<games>-s<seed>`, so re-issuing the
  same command **resumes** the same run instead of starting a second one.
- Manifest progress is refreshed every two seconds from the harness's flushed
  `finished N/M rounds` lines. The app and `status` therefore move within a
  shard, not only when a 5,000-game shard completes. A resume records
  `resumed_at`, so the rate and ETA describe the current session rather than a
  pause that may have lasted overnight.
- A merge is a tracked child process in the app: it blocks Start/Delete while it
  runs, reports its own failure, and writes `merged.csv` atomically.
- A shard is marked `done` only when the harness exited 0, its log reports zero
  incomplete rounds, and its CSV ends on a complete line. Anything else is
  replayed from its seed.
- Ctrl-C stops the children and leaves unfinished shards `pending`. A SIGKILL is
  survivable too: the recorded child pids are checked and reaped on resume, so
  an orphaned harness can never write a shard file the new run is using.
- Shards keep their own CSV and log under `lab/data/runs/<run-id>/shards/`;
  `merge` rewrites game ids into one continuous sequence.

## Quality-of-life checks

The app can stop an analysis, open its captured log, copy a report, and reload
the last saved reports after relaunch. The Runs screen opens a run's runner log
and any failed shard's log, shows failed-shard reasons, and deletes a run only
after confirmation and only when no lock is active. Unmerged runs with more than
eight shards say that the Analyses tab is previewing a subset; combining the run
removes that limit.

## Planned milestones

1. **C++ self-play:** done — legal games, deterministic seeds, per-move CSV output.
2. **Calibration:** implemented — side-alternated head-to-head, win-rate, score-delta, and starting-hand correlation reports.
3. **Dataset generation:** positions, beliefs, chosen moves, evaluation breakdowns.
4. **Learned evaluation (optional):** train offline, export weights, run inference in C++.
5. **Strength evaluation:** candidate vs baseline ladder, not just loss curves.

## Non-goals

- Shipping Python in the `.app`.
- A second game engine.
- Letting a model decide legality or scoring.
- Training before a measured self-play baseline exists.

## Related decisions

- `docs/engineering/OPEN_DECISIONS.md` — ADR-001 (languages) and ADR-002 (lab/trainer).
- `docs/subsystems/LAB.md` — full lab architecture and acceptance criteria.
- `docs/subsystems/ACCELERATOR.md` — the Metal compute track that will consume stronger evaluation.
