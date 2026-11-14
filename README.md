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

Prototype, 52.6% complete by the independent 2026-11-14 audit, measured before
that day's Phase 1–2 corrections (the earlier 57.5% self-assessment is
superseded). Rules, bridge, search, self-play and AI match play are green and
tested (480 engine, 116 bridge checks, 112 Swift tests with 0 skipped). **No current strength claim exists:** the 2026-11-14 rulebook
change voided the old ladder, and the five difficulty bands have not been
re-measured under the current rules (see `docs/research/STRENGTH_BASELINE.md`).
The Metal accelerator is not wired into search, and its compact parity suite
currently fails 6 checks. Sets are now best-of-5 or best-of-7, with scores reset
and the double-six ritual restarted each set; the 1v1 One Domino Rule is enforced
in live play and in search. Sandbox, Training, 1v1v1 elimination, match
persistence and packaging are not implemented. The 101 option, unlimited analysis
draws and 1v1v1 elimination remain rule gaps. The private locked-pair look is now
implemented without a public reveal. No external-engine Elo or "strongest
engine" claim is made.

Current defects, evidence and priorities: [`docs/audits/2026-11-14-audit.md`](docs/audits/2026-11-14-audit.md).
