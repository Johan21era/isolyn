# IsolynV2.0

A macOS hot-seat dominoes game with a C++20 rules/search engine, a POD-only
Swift/C++ bridge, and a SwiftUI client.

## Run

```bash
./run.sh
```

Or, if the shell aliases are installed, `iso` / `ISO` / `Iso` / `isolyn`.

## Project identity

`IsolynV2.0` is the package, product, window, and app-bundle display name.
The Swift targets (`IsolynEngine`, `IsolynEngineBridge`, `IsolynApp`) and the
C++ `isolyn` namespace remain unchanged: dots are not legal in those
identifiers, and keeping them stable preserves the bridge ABI and test imports.

## Architecture

- `Sources/IsolynEngine/` — rules, belief state, determinization, search, scoring.
- `Sources/IsolynEngineBridge/` — the guarded C++/Swift boundary.
- `Sources/IsolynApp/` — SwiftUI app and game screen.
- `lab/` — offline lab (Python; calibration reports real, trainer still scaffold).
- `tools/selfplay/` — real C++ engine-vs-engine data generator.
- `Accelerator/` — Metal batch evaluator (standalone; search integration pending).
- `docs/history/legacy-handoff.md` — deep onboarding, history, and house rules.

## Documentation

The full index of every project document is [`docs/README.md`](docs/README.md). Key documents:

- `docs/engineering/OPEN_DECISIONS.md` — ADR-001..004: C++/Swift product, Python offline,
  Metal as a first-class backend, one source of game truth.
- `docs/subsystems/LAB.md` — offline lab architecture and milestones.
- `docs/subsystems/ACCELERATOR.md` — Metal architecture, parity gates, and throughput evidence.
- `docs/architecture/PROJECT_INVENTORY.md` — project identity, caller map, and current LOC inventory.

## Status

Prototype, 57.5% complete against its own feature specification. Rules, bridge,
search, self-play and AI match play are green and tested (429 engine, 73 bridge
checks, 75 Swift tests with 1 skipped). The internal 1v1 ladder is real, but
only the widest gap is statistically resolved, so the five difficulty bands are
labels rather than measured strengths. The Metal accelerator is a
parity-tested standalone evaluator and is not wired into search. Sandbox,
Training, the One Domino Rule, match persistence and packaging are not
implemented. No external-engine Elo or "strongest engine" claim is made.

Current defects, evidence and priorities: [`docs/audits/2026-11-13-audit.md`](docs/audits/2026-11-13-audit.md).
