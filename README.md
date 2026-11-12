# Isolyn

A macOS hot-seat dominoes game with a C++20 rules/search engine, a POD-only
Swift/C++ bridge, and a SwiftUI client.

## Run

```bash
./run.sh
```

Or, if the shell aliases are installed, `iso` / `ISO` / `Iso` / `isolyn`.

## Architecture

- `Sources/IsolynEngine/` — rules, belief state, determinization, search, scoring.
- `Sources/IsolynEngineBridge/` — the guarded C++/Swift boundary.
- `Sources/IsolynApp/` — SwiftUI app and game screen.
- `lab/` — offline lab (Python; calibration reports real, trainer still scaffold).
- `tools/selfplay/` — real C++ engine-vs-engine data generator.
- `Accelerator/` — Metal batch evaluator (standalone; search integration pending).
- `legacy handoff.md` — deep onboarding, history, and house rules.

## Decisions

- `docs/OPEN_DECISIONS.md` — ADR-001..004: C++/Swift product, Python offline,
  Metal as a first-class backend, one source of game truth.
- `docs/LAB.md` — offline lab architecture and milestones.
- `docs/ACCELERATOR.md` — Metal architecture, parity gates, and throughput evidence.

## Status

Late alpha. Rules, bridge, search, self-play, AI match play, and calibration
reports are green and tested, and a measured internal 1v1 calibration ladder
exists. The Metal accelerator has a parity-tested batch evaluator but is not yet
wired into search. Sandbox, Training, and packaging remain incomplete. No
external-engine Elo or "strongest engine" claim is made.
