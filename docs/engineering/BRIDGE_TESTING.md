# Bridge Testing

**Current status:** verified on macOS arm64 (Apple M3) on 2026-11-15.
This document describes the bridge and the checks that exercised it in the
current worktree. Historical 2026-08 results are labelled as historical; do not
copy them as current numbers.

## Environment

- macOS arm64 (Apple M3), Apple clang, Swift Package Manager available.
- The native engine and bridge are compiled by the repository's own scripts.
- The Swift package is compiled and tested by `swift test`; the bridge header is
  therefore compiler-checked on the current machine.
- The Metal accelerator is verified separately with `./Accelerator/build.sh`.

## Current verification matrix

| Check | Command | Result |
|---|---|---|
| Engine suite | `./scripts/ci/test_engine.sh` | 20 executables, **524 checks passed**, 0 failed (2026-11-15) |
| Bridge suite | `./scripts/ci/test_bridge.sh` | 2 executables, **141 checks passed**, 0 failed (2026-11-15) |
| Swift package | `swift test` | **125 tests, 0 skipped, 0 failures** (2026-11-15) |
| Offline lab + cloud verifier | `PYTHONPATH=lab/src python3 -m unittest discover -s lab/tests` | **55 tests, 0 failures** (2026-11-15) |
| AddressSanitizer + UBSan | `./scripts/ci/sanitize.sh address` | 21 executables, **623 checks passed**, 0 findings |
| ThreadSanitizer | `./scripts/ci/sanitize.sh thread` | 2 executables, **147 checks passed**, 0 findings |
| Standalone fuzz fallback | `./scripts/ci/fuzz_bridge.sh 30` | 75,000 executions, zero crashes/hangs/sanitizer findings |
| Accelerator harness | `./Accelerator/build.sh` | **94 pass / 6 fail**; compact GPU parity is red (2026-11-14) |

The engine, bridge and Swift rows were re-run on 2026-11-15 after the R-06/R-15
rulebook work and the Lab test suites; their counts grew accordingly. The
sanitizer, fuzz and Accelerator rows below are the last recorded figures and were
not re-run in that sweep — re-measure before quoting them.

The fuzz runner reports that libFuzzer is unavailable on this toolchain and uses
the repository's standalone driver. That is a real fallback, not full
coverage-guided fuzzing; the scope is the documented bridge attack surface.

## What the bridge suite covers

`Tests/IsolynEngineBridgeTests/SmokeTest.cpp` exercises:

- session lifecycle, idempotent close, and invalid handles;
- per-player snapshot isolation (only the requester's hand is revealed);
- legality rejection with no partial mutation;
- state-version rejection of duplicate/stale commands;
- terminal-round guards on all four mutating commands;
- analysis creation, cancellation, and bounded completion;
- match recording: duplicate rejection, team scoring, next-starter propagation,
  and idempotent close;
- a cross-thread snapshot hammer while an analysis is running.

`SoakTest.cpp` exercises repeated session lifecycles and reports its own RSS
threshold. Its current result is part of the 141-check bridge total, not a silent
zero-check pass.

## Whole-game conformance soak

`tools/conformance/rules_soak.cpp` is the high-volume complement to the unit
suites. It plays complete games through `MatchController`, `MoveGenerator` and
`GameState` in all three modes, asserting after every action that the canonical
tile set is partitioned exactly once, that every generated move is legal, that
forced draws stop only at a playable tile or an exhausted boneyard, and that
every Domino/Close verdict matches the board. It counts assertions rather than
printing passing ones.

Run `./scripts/ci/rules_soak.sh 1000000` locally (about 8 seconds on the
development Mac; **≈172.8 million assertions, 0 failures** on 2026-11-15). The
nightly workflow runs 100,000,000 games, labelled as a 100-million-game soak;
the assertion count is correspondingly larger. This is randomized evidence over
the real turn flow, not a replacement for the rulebook gate's enforced anchors.

## Historical findings

The bridge's original hardening pass found and fixed:

- a missing blocked-player precondition in analysis creation;
- a real cross-thread analysis/snapshot race surface;
- two bridge draft compile defects before they could ship;
- a terminal-round mutation hole (`RoundAlreadyOver`);
- a soak-test measurement gap on macOS.

Per-fix anchors and exact historical outputs remain in `docs/history/fix-log.md` and
`docs/history/legacy-handoff.md`; those entries are historical receipts, not re-runs.

## Not covered

- **The match/session mode-mismatch path** is covered by the AUD-01 regression
  in `SmokeTest.cpp`; `bridge_match_record_round` returns `ModeMismatch` before
  touching any hand. The bridge suite now runs that regression on every pass.
- Sandbox Mode's caller-constructed positions. The engine has no
  `PositionConstructor`/bridge entry point yet.
- Native UI visual behavior and on-device interaction. The Swift tests are
  headless; they do not replace opening the app.
- A full multi-hour soak on the current build. The 2026-11-11 suite exercises
  the current code, but long-duration stability is not a fresh claim.
- Search strength. Engine/bridge tests prove behavior, not playing strength;
  the measured ladder lives in `docs/subsystems/LAB.md`.
