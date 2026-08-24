# ISOLYN CURRENT AUDIT

**Project:** Isolyn-current_4 — tournament-grade Albanian Dominoes analysis engine + macOS SwiftUI app
**Auditor:** ox-alpha
**Date:** Session of 2026‑08‑24
**Scope:** Every file in `Isolyn-current_4/` read line-by-line (114 files), followed by **live verification on the actual target platform** (Apple Silicon Mac, Xcode 26.6 / Swift 6.3 / Apple clang) — something no prior session on this codebase has ever had.
**Method:** Per `iOS_Architecture_Review_Prompt_v2.md` output format; findings gated by the Finality doctrine from `aggressive-bug-fix-protocol.md` (only High-confidence, evidence-backed items are marked fixable; two were fixed and verified live during this audit).

---

## 1. EXECUTIVE SUMMARY

Isolyn is a Double-Six dominoes game for macOS built as three strictly separated layers: a C++20 rules/search engine (`isolyn`, ~2,840 LOC), a POD-only C bridge (~806 LOC), and an @Observable SwiftUI shell (~2,575 LOC) that currently covers entry/mode-select navigation plus a fully-tested time/weather environment system. The real architecture matches its documentation with unusual fidelity — every "verified vs. unverified" claim I checked against code was accurate. The three most critical problems found: **(1)** the project's own verification scripts fail to link on macOS (`run_tests.sh` omits `-framework Security`), meaning the headline "356/356" claim was unreproducible on the shipping platform until this audit; **(2)** `swift test` did not build at all — the test target was missing `.interoperabilityMode(.Cxx)` — so the entire Swift-side test suite had never executed anywhere until this session fixed and ran it (25/25 pass); **(3)** the project has no version control at all, leaving its only copies as loose desktop folders despite its own HANDOFF documenting catastrophic data loss from exactly that practice. One genuine strength worth naming: the bridge's handle-table/state-versioning/fails-closed design is genuinely hardened, and survived re-verification today including a 10.7-million-query cross-thread hammer.

---

## 2. ARCHITECTURE MAP

```
┌──────────────────────────────────────────────────────────────┐
│ IsolynApp (SwiftUI, @Observable, macOS 14+)                  │
│   IsolynApp.swift → RootView (screen switch, env persists)    │
│   AppState (nav SSOT) │ Views (Entry/ModeSelect/ComingSoon)  │
│   Environment/* (@Observable manager + pure-function core,   │
│   injectable clock, WeatherKit|Random|Off sources)           │
│   Engine/EngineSession.swift (actor) ── EngineTypes.swift    │
└───────────────┬──────────────────────────────────────────────┘
                │ import IsolynEngineBridge (.interoperabilityMode(.Cxx))
┌───────────────▼──────────────────────────────────────────────┐
│ IsolynEngineBridge (POD-only contract, uint64 handle tables, │
│ per-session mutex, state-version staleness rejection,        │
│ typed BridgeStatus errors, 2-phase analysis w/ cancel atom)  │
└───────────────┬──────────────────────────────────────────────┘
┌───────────────▼──────────────────────────────────────────────┐
│ IsolynEngine (C++20, namespace isolyn, zero internal locks)  │
│   Rules/Dealer/Chain/Boneyard/GameState (value types, LIFO   │
│   undo) · MoveGen/Validator/Executor · MatchController       │
│   BeliefState→ProbabilityEngine→Determinizer→Simulation      │
│   Engine→SearchEngine (determinized MaxN, cooperative cancel)│
│   EvaluationEngine (4 heuristics, placeholder weights)       │
│   ScoreSystem (unwired — reserved for match orchestration)   │
└──────────────────────────────────────────────────────────────┘
```

**SSOTs:** navigation = `AppState.screen`; environment = `EnvironmentManager.state` (+ `currentSkyCondition`); game truth = `MatchController::state()` inside each `EngineSessionImpl`, versioned by `stateVersion`. No redundant truths found between layers — the bridge deliberately exposes sizes-not-contents for hidden hands, and the Swift layer mirrors that shape exactly.

---

## 3. DEAD CODE REPORT

| File | Symbol | Status | Reason |
|---|---|---|---|
| Components/EnvironmentSettingsView.swift | whole type | compiled, unreachable | No screen references it (HANDOFF batch 5 documents "no clear placement decision" — deliberate but still dead weight in the binary) |
| Components/EnvironmentTimeLabel.swift | whole type | compiled, unreachable | Same |
| Components/StarFieldView.swift | `init(starCount:seed:)` | zero call sites | Test/preview convenience never exercised outside previews |
| Environment/WeatherSource.swift | `FixedWeatherSource` | preview-only | Used solely by #Preview blocks |
| ProbabilityEngine.hpp/.cpp | `observePlay`, `observeDraw`, `probabilityHoldsTile`, `probabilityHoldsAtLeast`, `expectedRemainingValue` | test-only | Documented extension point; production path builds BeliefState directly, never streams observations |
| RulesEngine | `determineNextRoundStarter` | zero call sites | Reserved pass-through for future match orchestration |
| ScoreSystem.cpp/.hpp | entire class | unwired | Explicitly out of scope pending round-to-round design (documented) |

Dead/unwired total ≈ 350–400 effective LOC (<5% of product code), and — notably — **every item above is self-declared in HANDOFF/docs rather than silently abandoned.** That is the opposite of the usual dead-code smell; these are reserved seams. Flagged for inventory purposes only.

---

## 4. FINDINGS TABLE

Severity: CRITICAL = blocks verification/crash/rejection risk · HIGH = likely failure in realistic use · MEDIUM = wrong results in edge cases or clear remediation debt · LOW = hygiene.

| ID | Sev | Category | Finding | Evidence | Impact | Fix |
|---|---|---|---|---|---|---|
| F‑01 | **CRITICAL → FIXED+VERIFIED** | Build/Test | `swift test` failed to build: `IsolynAppTests` imports `IsolynApp`, whose surface requires `IsolynEngineBridge`, but the test target lacked `.interoperabilityMode(.Cxx)` → `'cstdint' file not found`, `could not build Objective-C module 'IsolynEngineBridge'`. The entire Swift suite had never run in any environment. | Reproduced live this session; `Package.swift` testTarget block; the Package.swift comment itself flagged this exact reasoning as unverified ("should not by itself change how this test target builds… not been compiler-checked") | All Swift-side verification impossible; HANDOFF's "first thing to confirm when next opened" now answered | **Fixed during audit:** added `swiftSettings: [.interoperabilityMode(.Cxx)]` to `IsolynAppTests`. Re-ran: build clean, **25/25 XCTest cases pass** (incl. DST spring-forward/fall-back, timezone reclassification, midnight wrap). Backup of original at `build/audit/Package.swift.bak` |
| F‑02 | **HIGH** | Verification harness | `run_tests.sh` fails to link on macOS: undefined `_SecRandomCopyBytes`/`_kSecRandomDefault` across all 18 executables. Scripts predate the EntropySource rewrite's Security-framework dependency; `Package.swift`'s `linkerSettings` only applies to SPM consumers, not these raw clang/g++ invocations. | Live reproduction this session (linker errors); `run_tests.sh` lines ~20‑24 contain no `-framework Security`; contrast Package.swift IsolynEngine target comment | The project's headline "356/356 checks passing" was unreproducible on the shipping OS using the project's own tooling; every new contributor hits an immediate wall | Add `-framework Security` to both `run_tests.sh` and `run_bridge_tests.sh` compile/link lines. **Verified manually this session:** with the flag, all 18 binaries compile warning-free under Apple clang `-Wall -Wextra -Wpedantic` and **356/356 checks pass**, exercising `SecRandomCopyBytes` for the first time ever |
| F‑03 | **HIGH** | Game-flow correctness | No terminal-state guard in bridge mutating commands. After `roundOutcome` becomes `DominoVictory`/`Closed`, `bridge_submit_move`, `bridge_voluntary_draw`, `bridge_resolve_forced_draw`, `bridge_end_turn_with_no_play` still mutate session state if given a fresh `expectedStateVersion`. A Closed position naturally rejects further moves (legality gate), but a **DominoVictory leaves other players holding legal moves** — play can continue past the round's end. | `IsolynBridge.cpp` command bodies check stale-version/tile-validity/legality but never `impl->cachedRoundOutcome != InProgress`; `MatchController::playTurn` returns the outcome but keeps mutable state | A racing or buggy UI layer can extend a finished round; any future score/orchestration consumer would then compute from corrupted round semantics | In each mutating command, after the stale-version check: `if (impl->cachedRoundOutcome != RoundOutcomeDTO::InProgress) return failedCommand(BridgeStatus::InvalidRequest, "round already ended");` + regression test in SmokeTest.cpp |
| F‑04 | **MEDIUM** | Concurrency | `EnvironmentManager.weatherMode`/`weatherSource` and `LiveWeatherService.lastKnownGood` are unsynchronized shared mutable state touched from MainActor (UI writes) and non-isolated Tasks (weather loop, foreground observer); `LiveWeatherService` is `@unchecked Sendable` so the compiler stays silent. Corroborated by the Swift‑6-mode warning at `EnvironmentManager.swift:146`. | `EnvironmentManager.setWeatherMode` writes; `scheduleWeatherLoop`'s detached-style Task reads; `LiveWeatherService.currentCondition()` mutates `lastKnownGood` on arbitrary executors. **Self-flagged in HANDOFF batch 6 with three remediation options — still open** | Narrow-window data race in `.live` weather mode (mode-switch or foreground event landing mid-fetch); benign-looking corruption of cached condition | Adopt option (a) from HANDOFF: make the weather-refresh path MainActor-confined and capture `weatherSource` into a local before any `await`; also fixes the line‑146 captured-var warning. (Judgment: cheapest correct option; actor conversion is overkill for one cached value.) |
| F‑05 | **MEDIUM** | Release readiness | No App packaging substrate: SPM executable only. No PrivacyInfo.xcprivacy, no NSLocationUsageDescription despite `CLLocationManager().location` access, WeatherKit entitlement documented-but-absent, no bundle/App icon pipeline. | `Package.swift` platforms `[.macOS(.v14)]`, executable target; `LiveWeatherService` default `locationProvider`; docs note capability requirement | Not shippable/distributable as-is; location access will be silently denied (or rejected) once sandboxed | When creating the eventual Xcode app target: add privacy manifest, location usage strings, WeatherKit capability; keep SPM target as the dev loop |
| F‑06 | **MEDIUM** | Process/data safety | **No git repository.** The project exists only as a loose desktop folder (+ sibling zip), with .DS_Store cruft, no history, no remote — despite HANDOFF opening with a horror story about losing unexported work to a reset sandbox. | Directory listing: no `.git`; `Desktop/Isolyn-current_4.zip` is the only snapshot mechanism | One mis-keyed delete/rm loses everything; no diffability for future audits; contradicts the project's own hard-won lesson | `git init` + `.gitignore` (`build/`, `.DS_Store`, `.swiftpm/`, `*.o`, xcuserdata) + initial commit immediately after F‑02's script fix lands |
| F‑07 | **LOW** | API semantics | `bridge_analysis_run` returns `failedAnalysis(BridgeStatus::SessionClosed)` for an unknown analysis handle, but the header declares AnalysisResultDTO carries only BridgeFailure/EngineFailure-class statuses, and "SessionClosed" describes *sessions*, not snapshots. Swift maps it to `.sessionClosed`, misleading at the call site. | Header comment block above `AnalysisResultDTO`; `IsolynBridge.cpp` first guard in `bridge_analysis_run` | Confusing diagnostics; no functional harm (fails closed either way) | Return `BridgeFailure("unknown analysis handle")`; update Swift mapping comment |
| F‑08 | **LOW** | Defensive defaults | `RoundOutcome.init(dto:)` maps `@unknown default` to `.inProgress` — a hypothetical future enum value would silently present a finished round as ongoing. | `EngineTypes.swift` RoundOutcome init | Latent misreporting after DTO evolution; low likelihood | Default to `.closed(decidingPlayerIndex:)`? No — better: keep mapping but log via os_log so divergence is observable |
| F‑09 | **LOW** | Performance | `EnvironmentTimeLabel.formattedTime` allocates a fresh `DateFormatter` on every body evaluation (each 30s tick × any state change). DateFormatter construction is notoriously expensive. | `EnvironmentTimeLabel.swift` formattedTime | Wasted work per refresh; trivial today, bad habit at scale | Cache formatter in a static let keyed by timeZoneIdentifier |
| F‑10 | **LOW** | Resource lifecycle | An `AnalysisTask` that is dropped without awaiting or cancelling runs its full search to completion on a detached task (potentially seconds of CPU) before self-destroying its snapshot. | `EngineSession.requestAnalysis` phase‑2 closure destroys handle only inside the task; no deinit hook on AnalysisTask | Wasted CPU on abandoned analyses (e.g., user closes window mid-analysis) | On abandonment paths, call `cancel()`; optionally add explicit `dispose()` combining cancel+destroy semantics |
| F‑11 | **LOW** | Latent hazard | `BeliefState.applyOpponentDraw` asserts boneyard mass > 0; under NDEBUG a caller invoking it when the locked pair is revealed would divide by zero (NaN propagation). Unreachable through the bridge today (it never calls observe*), but it's public API. | `BeliefState.cpp` applyOpponentDraw assert; bridge creates belief once per analysis and never streams draws | NaN beliefs if a future caller wires observeDraw without guarding drawableCount>0 | Guard: early-return when mass ≤ 0, or document precondition at ProbabilityEngine.observeDraw too |
| F‑12 | **LOW** | Hygiene | `HandleTable::insert`'s post-increment clamp `if (m_nextId == 0) m_nextId = 0;` is a no-op (the top-of-function guard does the real work). Correct behavior, misleading comment. | `IsolynBridge.cpp` insert | Reader confusion only | Simplify to rely solely on the entry guard, drop the fake clamp |

**Force-unwrap density:** zero `try!`/`as!`/force-chain sites across the entire Swift app (grep-verified). Engine uses `assert` deliberately at documented boundaries with the bridge as the Release-config enforcement point — an explicitly designed arrangement, verified working (FuzzBridge history + today's reruns).

**Claimed vs. real architecture:** audited line-by-line; **no divergences found** beyond the two build-level gaps above (F‑01/F‑02), which are themselves precisely the gaps the docs predicted might exist. Every behavioral claim spot-checked (double-preserves-end chain property, undoDrawTile identity removal, excluded-tile accounting, blocked-player analysis refusal, cancellation honesty semantics) matched its documentation and passed live.

---

## 5. SCALABILITY VERDICT

This is a **compute-bound, not data-bound** application — the state space is hard-capped at 28 tiles, so "10x/100x data" translates to search configuration:

- **What breaks at aggressive difficulty settings:** `SearchEngine::chooseBestMove` costs ≈ `determinizations × branching^depth × cloneCost`. Defaults (20×4-ply) complete comfortably; scaling toward DifficultyModel's top end (e.g., depth 7–8, thousands of determinizations) goes exponential — depth 8 at branching ~4–8 is minutes-per-move territory. Mitigation path already half-built: `DominoTile::index()` exists explicitly for future Zobrist/transposition tables, and `GameState` cloning is cheap by design. Iterative deepening + TT should precede any depth > 6 offering.
- **BeliefState memory:** O(28 locations-maps) per belief — negligible even at hundreds of concurrent analyses.
- **UI rendering:** Canvas particle systems (160 stars + ≤160 weather particles) redraw per frame — trivial for Core Animation; TimelineView pauses correctly under Reduce Motion/daytime.
- **Persistence:** none exists yet (no save/load/match history). At 100x "data" (years of match archives), the absence becomes the bottleneck — but that's unbuilt scope, not broken scale.
- **Concurrency ceiling:** per-session mutex + independent analysis worlds scale horizontally across sessions; the single global handle-table mutex is uncontended by design.

Verdict: nothing structurally breaks at 10x current usage; the exponential search knob is the only genuine wall, and its mitigation hooks are already in place.

---

## 6. PRIORITIZED REMEDIATION PLAN

### DO NOW
1. **Keep the F‑01 fix** (already applied & verified). Blocking dependency: none. Unknown resolved: the Cxx-interop question every HANDOFF entry carried is now settled — `isolyn.bridge.*` spelling and tuple-import layout both confirmed correct on Xcode 26.6.
2. **Apply F‑02**: add `-framework Security` to both shell scripts (exact flag placement verified manually this session; 356/356 green).
3. **Execute F‑06**: `git init` + ignore list + initial commit. Do this *immediately after* item 2 so the first commit contains a fully-green, reproducible-on-macOS tree.
4. **Implement F‑03** terminal-round guard + SmokeTest regression case. Design decision needed: reuse `InvalidRequest` vs. add `RoundAlreadyOver` status (recommend the latter — UI needs to distinguish "your tap was nonsense" from "the round you're looking at is finished"; one enum case, additive).

### DO NEXT
5. Resolve **F‑04** using HANDOFF batch‑6 option (a); simultaneously clears the Swift‑6 warning at `EnvironmentManager.swift:146`.
6. Wire `EnvironmentSettingsView` into a Settings scene (⌘,) or remove it and `EnvironmentTimeLabel` until placed — pick one; limbo is the worst of the three states.
7. Write the **match-orchestration design doc** (who owns ScoreSystem across rounds, when sessions are created, how `decidingPlayerIndex` feeds `createSubsequentRound`) — prerequisite for the actual game board and for Training/Sandbox modes alike.
8. F‑07/F‑09/F‑10 micro-fixes in one sweep (status rename, formatter cache, cancel-on-abandon convention).

### NICE TO HAVE
9. F‑05 packaging substrate when distribution becomes real (privacy manifest, location strings, entitlements, icons).
10. CI job (macOS runner) executing the three scripts so F‑02-class drift gets caught automatically.
11. DifficultyModel calibration harness (HANDOFF gates this behind your confirmation — still awaiting that go-ahead).
12. F‑08/F‑11/F‑12 polish items.

---

## 7. WHAT'S GOOD

1. **The bridge is genuinely hardened, not performatively hardened.** Handle tables with monotonic IDs (idempotent close, no ABA), typed failure statuses, state-version replay rejection, fails-closed ordering (stale-check → validity → legality → mutate), shared_ptr-backed table entries closing the destroy-under-run gap. Verified again today under a 10.7M-query cross-thread hammer on Apple Silicon. This is production-grade boundary engineering.
2. **Documentation honesty at a level I rarely encounter.** HANDOFF and BRIDGE_* docs distinguish "compiled and fuzzed" from "hand-reviewed, never compiled" with precision — and every distinction proved *accurate* under live testing. The two failures found were exactly the ones the docs predicted might exist. That epistemic discipline is why this audit could trust its own map.
3. **A correctness culture with receipts in the engine**: PlacementKind-based LIFO undo; the order-independent `undoDrawTile` fix (found by testing, commented with its war story); `excludedTilesForMode` as single source of truth shared by Dealer and ProbabilityEngine; the fuzz-discovered blocked-player precondition now enforced at the right layer. Each fix carries its regression test.
4. **Hidden information enforced structurally**: snapshots expose own-hand identities and opponent sizes only, computed C++-side, tested bidirectionally — privacy of game state is an architectural property, not a UI convention.
5. **Zero-warning compiles everywhere**: clang++ `-Wall -Wextra -Wpedantic` clean across 18 binaries; post-fix Swift build emits a single (known, F‑04-related) concurrency warning. Force-unwrap count: zero.
6. **The environment system is textbook-testable pure-function core**: injectable clock, DST/timezone/midnight edge cases enumerated and passing, continuous appearance curve with smoothstep easing verified for midnight continuity.

---

## 8. SINGLE HIGHEST-LEVERAGE NEXT ACTION

**Put this tree under git today** — with F‑01's fix and F‑02's script patch included — because the project's own history proves its biggest existential risk isn't any bug in the code; it's that all of this excellence currently lives in exactly one fragile, un-versioned desktop folder.

---

## APPENDIX A — VERIFICATION LOG (this session, real commands, real results)

| Check | Command | Result |
|---|---|---|
| Engine suite, as shipped | `./run_tests.sh` | ❌ Link failure, 18/18 executables (missing `-framework Security`) |
| Engine suite, patched link flags | clang++, `-framework Security` added manually | ✅ 18 executables, **356/356 checks**, zero warnings |
| Bridge smoke + cross-thread | linked against full engine+bridge objects | ✅ **33/33 checks**; 10,716,606 concurrent queries during one analysis run |
| Full package build | `swift build` (Xcode 26.6 / Swift 6.3.3) | ✅ Complete; resolves both documented Cxx-interop uncertainties; 1 concurrency warning (F‑04) |
| Swift test suite, as shipped | `swift test` | ❌ Module-build failure (F‑01) |
| Swift test suite, patched | after one-line Package.swift fix | ✅ **25/25 tests pass** (TimePhase boundaries, DST, timezone change, appearance curve) |

**Not re-run this session** (previously documented in BRIDGE_TESTING.md; unchanged code): libFuzzer campaign, soak test, ASan/UBSan/TSan sweeps. Recommend one sanitizer pass post-F‑03 fix.

## APPENDIX B — CHANGES MADE DURING THIS AUDIT

| File | Change | Authorization |
|---|---|---|
| `Package.swift` | Added `swiftSettings: [.interoperabilityMode(.Cxx)]` to `IsolynAppTests` | Finality reached and *empirically proven*: identical failure reproduced, fix applied, 25/25 green. Original preserved at `build/audit/Package.swift.bak` |
| `build/audit/*` | Audit scratch artifacts (patched binaries, logs, backup) | Disposable; safe to delete |


---

## APPENDIX C — KNOWLEDGE-GRAPH TRACE FINDINGS (post-audit verification pass)

*Added after generating the project knowledge graph (`graphify-out/`). Purpose: independently verify, via graph traversal, whether the documentation layer's claims about the architecture are structurally supported by the code graph — specifically around the highest-betweenness node, `Two-Phase Analysis Design`.*

### C.1 Trace results

| Trace | Path found | Hops | Edge confidence |
|---|---|---|---|
| Design → Fuzz-Found Bug | `Two-Phase Analysis Design` --references→ `SearchEngine.cpp` ←--references-- `Blocked Current Player UB Found By Fuzzing` | 2 | EXTRACTED / EXTRACTED |
| Design → Future Feature | `Two-Phase Analysis Design` --references→ `SearchEngine.cpp` ←--conceptually_related_to-- `DifficultyModel Awaiting User Confirmation` | 2 | EXTRACTED / INFERRED |
| Design → Future Feature | `Two-Phase Analysis Design` --references→ `SearchEngine.cpp` ←--references-- `Training Mode Puzzle Loop` | 2 | EXTRACTED / EXTRACTED |
| Cancellation loop | `AnalysisTask` ←contains-- `EngineSession.swift` ←implements-- `Two-Phase Analysis Design` --references→ `SearchEngine.cpp` --contains→ `chooseBestMove()` --references→ `BeliefState` ←--references-- `AnalysisSnapshotImpl` | 6 | ALL EXTRACTED |
| Run entry chain | `bridge_analysis_run()` --references→ `SearchEngine` --defines→ `decisionCriterion` ←--calls-- `chooseBestMove()` | 3 | EXTRACTED ×3 + INFERRED ×1 |

### C.2 Findings

**F‑T1 — The worst historical bug lived at the seam of the best architectural idea (VERIFIED).**
The shortest path between the two-phase analysis design and the fuzz-discovered blocked-player UB is exactly two hops through `SearchEngine.cpp`, and both edges are EXTRACTED (explicit in source text). This confirms causally, not just narratively: phase 1 exists because `chooseBestMove` is expensive and trusts its precondition ("current player has a legal move"); the UB was precisely a violated instance of that trust at the snapshot handoff. The fix (added inside `bridge_analysis_snapshot_create`) sits at the correct single choke point.

**F‑T2 — `SearchEngine.cpp` is the graph's true articulation point.**
Every trace above routes through it: the architecture rationale, the historical bug, the cancellation contract, and both unbuilt features (Training Mode, DifficultyModel). Formal consequence: any change to SearchEngine's public contract carries documented blast radius into shipped code *and* planned features simultaneously. Change management priority belongs here first — above even the bridge surface, which is wider but shallower.

**F‑T3 — The cancellation contract is a closed loop of fully-explicit relationships.**
The six-hop ring linking the Swift actor wrapper (`AnalysisTask`/`EngineSession.swift`), the C++ snapshot holder (`AnalysisSnapshotImpl.cancelRequested`), the search function, and `BeliefState` contains **zero inferred edges** — every hop is documented in source at confidence 1.0. Two independently written layers (user-drafted bridge draft + session Swift code) interlock without a single speculative connection. Rare result; worth preserving as the standard for future boundary work.

**F‑T4 — Documentation-to-code fidelity holds under traversal.**
Across every traced path, only one edge is INFERRED — the DifficultyModel link, which *should* be inferable-only since that module deliberately does not exist yet. No fabricated connections were found bridging docs to code, matching the audit's Section 4 conclusion that claimed-vs-real architecture divergence in this repo is nil.

**F‑T5 — Forward-risk concentration quantified.**
Because Training Mode and DifficultyModel both terminate at `SearchEngine.cpp` within two hops, the graph formally identifies this one file as the stability anchor for all future feature work. Practical rule derived from it: changes to `chooseBestMove`'s signature/precondition/config semantics require updating BRIDGE_ARCHITECTURE.md, FEATURE_SPECS.md, and HANDOFF expectations in the same commit — the graph shows those documents are structurally downstream of the file, not merely adjacent to it.

### C.3 Method note

Traces executed against `graphify-out/graph.json` (1,077 nodes / 2,172 edges / 80 labeled communities) via BFS depth-2 neighborhood confirmation plus targeted shortest-path queries. BFS context pool: 223 nodes spanning Bridge Analysis Pipeline, Move Legality Gate, Snapshot DTO Contract, and Future Work communities — consistent with the community structure reported in GRAPH_REPORT.md.
