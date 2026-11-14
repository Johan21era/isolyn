# IsolynV2.0 Offline Lab

**Status:** the C++ self-play generator is real, supports head-to-head search configurations, and emits per-move calibration data. `isolyn-lab evaluate` produces a real calibration report with Wilson intervals and Spearman correlations. `./scripts/lab run` drives resumable sharded multi-million-game runs. The Python trainer and weight export are still scaffolds; the Elo report itself is implemented.

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
│   ├── dataset.py              # per-move CSV -> per-game records
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
./scripts/lab status 1v1-d8x64-n5000000-s1
./scripts/lab list
./scripts/lab merge 1v1-d8x64-n5000000-s1
```

Measured on the development M3 at depth 8 / 64 determinizations: ~33 games/s
with four parallel shards and ~43 games/s with eight single-worker shards. Five
million games is therefore roughly 32 hours and about 9.5 GB of CSV (~1.95 KB per
game).

- Run ids default to `<mode>-d<depth>x<det>-n<games>-s<seed>`, so re-issuing the
  same command **resumes** the same run instead of starting a second one.
- A shard is marked `done` only when the harness exited 0, its log reports zero
  incomplete rounds, and its CSV ends on a complete line. Anything else is
  replayed from its seed.
- Ctrl-C stops the children and leaves unfinished shards `pending`. A SIGKILL is
  survivable too: the recorded child pids are checked and reaped on resume, so
  an orphaned harness can never write a shard file the new run is using.
- Shards keep their own CSV and log under `lab/data/runs/<run-id>/shards/`;
  `merge` rewrites game ids into one continuous sequence.

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
