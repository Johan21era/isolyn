# Bridge Testing

What has actually been run, with actual results, and what has not. Every number below came from a real command run in this exact repo state — see the command next to each result if you want to reproduce it. Nothing here is a projection or an estimate dressed up as a result.

## Environment

Built and tested from a Linux (Ubuntu 24.04) sandbox with `g++` 13.3.0 and `clang++` 18.1.3 — no Xcode, no Swift toolchain, ever, in any session that has worked on this codebase (see `HANDOFF.md`). Every result below is for the **C++ engine and bridge specifically**. The Swift consumer code (`Sources/IsolynApp/Engine/*.swift`) has never been compiled — see its own header comments for the two specific Cxx-interop uncertainties that are the first thing to check once this is opened in Xcode.

## Engine baseline (unchanged scope, reverified after every bridge-related engine change)

```
./run_tests.sh
```
18 executables, **356/356 checks passed**, zero compile failures, zero runtime failures. This includes the pre-existing engine suite plus new regression tests added this pass (`SearchEngineCancellationTests.cpp`, plus additions to `GameStateTests.cpp`, `BeliefStateTests.cpp`, `DealerTests.cpp` — see "Engine bugs found and fixed" below).

## Bridge test suite

```
./run_bridge_tests.sh
```
Compiles `Sources/IsolynEngine` + `Sources/IsolynEngineBridge` once into reusable object files, then links `Tests/IsolynEngineBridgeTests/SmokeTest.cpp` against them (deliberately not recompiling the engine per test file, unlike the original `run_tests.sh` pattern). **33/33 checks passed.** Covers:

- Lifecycle: session creation, close, double-close, close(0) — all genuinely safe (not just documented as such — see `BRIDGE_ARCHITECTURE.md`'s handle-table rationale).
- Hidden information: a snapshot requested by one player shows only their own hand; the other player's snapshot of the same session shows the reverse.
- The legality gate: submitting a move outside the current player's real legal-move set is rejected with `InvalidMove`, and the session's state version is confirmed unchanged afterward (no partial mutation).
- State versioning: a legal move is accepted and bumps the version by exactly 1; replaying the same command with the now-stale version is rejected as `StaleRequest`, not double-applied.
- Analysis correctness and cancellation, including a pre-cancelled run (`samplesCompleted == 0`, `completed == false`) and an uncancelled run completing all configured samples.
- **The blocked-current-player regression** (see below) — plays real random rounds looking for a point where the current player has no legal move, and confirms analysis creation now fails closed there instead of crashing.
- **Real cross-thread concurrency**: a background thread hammers `bridge_get_snapshot` on a live session while the foreground thread runs a full analysis (depth 4, 3000 determinizations) on that same session. Every run so far has completed several million concurrent queries during the single analysis call, confirming analysis genuinely does not block queries — not just "didn't crash."

## Sanitizers

Every engine test binary and the bridge smoke test have been run under AddressSanitizer + UndefinedBehaviorSanitizer (`clang++ -fsanitize=address,undefined -fno-sanitize-recover=all`) and separately under ThreadSanitizer (`-fsanitize=thread`) for anything touching real threads. **Zero findings across all of it** — no use-after-free, no leak, no undefined behavior, no data race, in any run.

```
./build/run_asan.sh                     # all 19 engine test binaries
clang++ -fsanitize=address,undefined ... Tests/IsolynEngineBridgeTests/SmokeTest.cpp ...
clang++ -fsanitize=thread ...            Tests/IsolynEngineBridgeTests/SmokeTest.cpp ...
```

## Fuzzing

```
./run_bridge_fuzz.sh 120
```
`Tests/IsolynEngineBridgeTests/FuzzBridge.cpp` drives the bridge's full public API (session lifecycle, moves, analysis) through libFuzzer with deliberately adversarial arguments at every call: out-of-range `GameModeDTO`/`ChainSideDTO` raw values, tile pips outside `[0,6]` (including near `int8_t` extremes), negative and huge player indices, stale/future/garbage state versions, and handle values that were never returned by this bridge at all (including reusing a real handle after it's been closed). Built with `-fsanitize=fuzzer,address,undefined`.

**A 5-second smoke run found a real, reproducible crash within the first ~18,000 executions** — see "Bridge bugs found and fixed" below. After the fix, **a 120-second run completed 75,451 executions with zero crashes, zero sanitizer findings, zero hangs**, growing an 838-input corpus. This is not exhaustive coverage — it's real evidence for the specific input space this harness explores, over the specific duration it ran, nothing more and nothing less.

## Soak test

```
g++ -O2 ... Tests/IsolynEngineBridgeTests/SoakTest.cpp ... && ./soaktest 12000
```
12,000 full session lifecycles (create → play through, including periodic analysis creation/run/destroy and forced-draw resolution → close), cycling through all three game modes. Measures `VmRSS` before, after a 200-cycle allocator warmup, and at the end, specifically to separate real growth from ordinary allocator-arena warmup noise.

**Result: 8 KB total growth over 11,800 post-warmup cycles (0.7 bytes/cycle)** — flat, consistent with allocator noise, not a leak. This is the harness's own reported threshold check (500 bytes/cycle) passing by a wide margin, not a subjective read of a graph.

## Bridge bugs found and fixed this pass

**1. Missing precondition check before analysis (found by fuzzing).** `bridge_analysis_snapshot_create` never verified the session's current player actually had a legal move before handing a snapshot to `SearchEngine::chooseBestMove`, which documents that exact precondition and doesn't check it itself (real play always resolves a forced draw first; the function trusts that). Reachable through the bridge's own ordinary command surface — any session sitting in "current player is blocked, hasn't called `resolveForcedDraw` yet" and then asked for analysis would hit it. Under a debug build this asserted (`SearchEngine.cpp:102`); under Release/NDEBUG it would have been silent undefined behavior (`candidates[0]` on an empty vector). Fixed by checking `currentPlayerHasLegalMove()` inside the existing locked section of `bridge_analysis_snapshot_create`, before ever constructing a `BeliefState`. Regression-tested directly in `SmokeTest.cpp` and covered going forward by `FuzzBridge.cpp`.

**2. Two compile errors in an independently-written draft of this bridge**, found during review before any of the above testing was possible: a `GameState` local variable relying on a default constructor the type doesn't have (fixed with `std::optional`), and a missing closing brace that — if simply silenced rather than actually fixed — would have given every public `bridge_*` function internal linkage instead of external, breaking the link the moment anything else tried to call them. See `HANDOFF.md` for the full review writeup.

## Engine bugs found and fixed this pass

Both predate this pass and are unrelated to the bridge's own code — found because bridge-level testing was the first thing to exercise these specific code paths against realistic (not hand-crafted) game states. Both regression-tested and the full 356-check baseline reconfirmed clean after each fix.

**1. `GameState::undoDrawTile` order-dependency.** Relied on the most recently drawn tile always being at `hand.back()`, but `playTile`/`undoPlayTile`'s find-then-erase/push_back pattern doesn't preserve hand vector order — any search recursion that draws a forced tile and then evaluates a candidate move that isn't that exact tile would silently invalidate the assumption. Fixed by making `undoDrawTile` locate-and-remove by identity instead, matching how `playTile` already worked.

**2. `OneVsOneVsOne` analysis crashed on every real 3-player game.** `Dealer` correctly removes the 0-0 tile from play entirely for this mode (a real rule, `Dealer::excludedTilesForMode`), but `ProbabilityEngine`/`BeliefState` didn't know about that exclusion and assumed all 28 canonical tiles were always accounted for somewhere. Reproduced with zero bridge code involved — a bare `MatchController::dealFirstRound(OneVsOneVsOne, ...)` followed by `ProbabilityEngine::constructFromGameState` crashed every single time. Fixed by adding an `excludedTiles` parameter to `BeliefState`'s constructor, sourced from the same `Dealer::excludedTilesForMode` that `deal()` itself now also uses, so the two can never disagree about which tiles that is.

## What has not been done

Said plainly:

- **No Swift-side testing of any kind**, because no Swift toolchain has ever been available. `EngineTypes.swift`/`EngineSession.swift` are hand-reviewed against the real bridge signatures, not compiler-checked.
- **No adversarial testing across an actual round-to-round match** (multiple rounds, score accumulation) — out of scope per `BRIDGE_ARCHITECTURE.md`'s "explicitly out of scope" section; there's no match-orchestration layer yet to test.
- **No formal red-team pass structured as a fixed checklist of attack categories.** Fuzzing (adversarial-input-focused) and the soak test (resource-exhaustion-focused) cover a meaningful, real slice of that spirit, but this wasn't run as a separate, explicitly-enumerated pass on top of them.
- **No performance/latency characterization on real hardware** (this sandbox's single CPU core and its numbers aren't representative of the eventual Xcode/macOS target).
