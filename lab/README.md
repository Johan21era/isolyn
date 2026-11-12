# IsolynV2.0 Offline Lab

**Status:** the C++ self-play generator is real, supports head-to-head search configurations, and emits per-move calibration data. `isolyn-lab evaluate` produces a real calibration report. The Python trainer, weight export, and Elo ladder are still scaffolds.

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

- `docs/OPEN_DECISIONS.md` — ADR-001 (languages) and ADR-002 (lab/trainer).
- `docs/LAB.md` — full lab architecture and acceptance criteria.
- `docs/ACCELERATOR.md` — the Metal compute track that will consume stronger evaluation.
