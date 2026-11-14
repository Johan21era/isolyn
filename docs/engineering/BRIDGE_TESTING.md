# Bridge Testing

**Current status:** verified on macOS arm64 (Apple M3) on 2026-11-11.
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
| Engine suite | `./scripts/ci/test_engine.sh` | 19 executables, **490 checks passed**, 0 failed (2026-11-14) |
| Bridge suite | `./scripts/ci/test_bridge.sh` | 2 executables, **133 checks passed**, 0 failed (2026-11-14) |
| Swift package | `swift test` | **120 tests, 0 skipped, 0 failures** (2026-11-14) |
| AddressSanitizer + UBSan | `./scripts/ci/sanitize.sh address` | 21 executables, **623 checks passed**, 0 findings |
| ThreadSanitizer | `./scripts/ci/sanitize.sh thread` | 2 executables, **147 checks passed**, 0 findings |
| Standalone fuzz fallback | `./scripts/ci/fuzz_bridge.sh 30` | 75,000 executions, zero crashes/hangs/sanitizer findings |
| Accelerator harness | `./Accelerator/build.sh` | **94 pass / 6 fail**; compact GPU parity is red (2026-11-14) |

The engine, bridge and Swift rows were re-run on 2026-11-14 (OPS-34) after the
rulebook rewrite and the Lab test suites; their counts grew accordingly. The
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
threshold. Its current result is part of the 73-check bridge total, not a silent
zero-check pass.

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

- **The match/session mode-mismatch path.** `bridge_match_record_round` does
  not reject a session whose player count differs from the match mode; a 1v1
  session recorded into a 2v2 match reads `state.hand(3)` on a two-player
  state. The use of `hand()` is `assert`-only, so this is an out-of-bounds read
  in Release (SIGSEGV) and an abort in Debug. Neither the bridge suite nor the
  sanitizer sweep exercises it. See `docs/audits/2026-11-13-audit.md` §7.2.
- Sandbox Mode's caller-constructed positions. The engine has no
  `PositionConstructor`/bridge entry point yet.
- Native UI visual behavior and on-device interaction. The Swift tests are
  headless; they do not replace opening the app.
- A full multi-hour soak on the current build. The 2026-11-11 suite exercises
  the current code, but long-duration stability is not a fresh claim.
- Search strength. Engine/bridge tests prove behavior, not playing strength;
  the measured ladder lives in `docs/subsystems/LAB.md`.
