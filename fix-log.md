# ISOLYN FIX LOG

> Format follows `aggressive-bug-fix-protocol.md` (12 fields per entry,
> compressed). Every entry below was executed and VERIFIED during the
> 2026‑08 session that produced commits `b79a3f4 → 0d63200`.
>
> **How to verify any entry:** see "Check My Work" in `legacy handoff.md` —
> every fix cites a grep-able anchor string; search the named file for it.

---

## LEGEND
Severity: CRITICAL / HIGH / MEDIUM / LOW / OPS (non-code infrastructure)
Status: FIXED+VERIFIED means: change applied AND proven by an actual command
run whose output is quoted in the Verification field or reproducible via
legacy handoff.md §CHECK-MY-WORK.

---

## FIX‑01 — Swift test target could not build at all
- **Severity:** CRITICAL (blocked 100% of Swift-side verification project-wide)
- **Confidence:** High (reproduced, fixed, re-run)
- **Files:** `Package.swift` (anchor: `interoperabilityMode(.Cxx)` inside IsolynAppTests target)
- **Root cause:** `IsolynAppTests` imports `IsolynApp`; IsolynApp's public surface references `isolyn.bridge.*` types from `IsolynEngineBridge`; any target importing across that boundary must itself enable C++ interop. The test target didn't.
- **Failure scenario:** every `swift test` died pre-run: `'cstdint' file not found` / `could not build Objective-C module 'IsolynEngineBridge'`. The entire XCTest suite had NEVER executed anywhere.
- **Repro:** checkout commit before this fix → `swift test`
- **Why it fails:** SPM compiles each Swift target's module interface separately; without interop mode the Clang module of the bridge header is built in ObjC mode where `<cstdint>` doesn't resolve.
- **Worst-case impact:** all 25 environment tests permanently unverifiable; HANDOFF's flagged uncertainty never answerable.
- **Finality:** *"Adding `.interoperabilityMode(.Cxx)` to IsolynAppTests makes swift test build."* → proven true by run.
- **Fix:** one-line `swiftSettings:` addition on the testTarget.
- **Verification:** `swift test` → `Executed 28 tests … 0 failures` (was: fatalError).

## FIX‑02 — Engine/bridge scripts failed to link on macOS
- **Severity:** HIGH (headline "356/356" claim unreproducible on shipping OS)
- **Confidence:** High
- **Files:** `run_tests.sh`, `run_bridge_tests.sh`, `run_bridge_fuzz.sh` (anchors: `framework Security`, `PLATFORM_FLAGS`)
- **Root cause:** EntropySource calls `SecRandomCopyBytes` (Security.framework) on Apple platforms; Package.swift declared the linker setting for SPM consumers only — raw clang/g++ script invocations never linked it.
- **Failure scenario:** all 18 engine executables + bridge suite die at link: undefined `_SecRandomCopyBytes`/`_kSecRandomDefault`.
- **Fix:** Darwin-conditional `-framework Security` injected into compile/link lines (`uname` guard keeps the original Linux workflow intact).
- **Verification:** scripts now report **356/356** and **33/33→57/57** end-to-end on macOS.

## FIX‑03 — Bridge test harness assumed GNU coreutils
- **Severity:** MEDIUM (script false-negatives on macOS)
- **Files:** `run_bridge_tests.sh` (anchor: `run_with_timeout`)
- **Root cause:** macOS lacks `timeout(1)`. `if ! out=$(timeout 60 …)` returned command-not-found failure for tests that actually PASS.
- **Fix:** `run_with_timeout()` helper — uses timeout when present, direct exec otherwise (CI images can install coreutils to restore hang protection).
- **Verification:** SoakTest flipped Runtime-failure → pass.

## FIX‑04 — SmokeTest deal-randomness flake, part A (blocked-player assumption)
- **Severity:** HIGH (suite lied ~1-in-7 runs)
- **Confidence:** High (root-caused from failing output `[FAIL] analysis snapshot created…`)
- **File:** `Tests/IsolynEngineBridgeTests/SmokeTest.cpp` (anchor: `ensureCurrentPlayerCanMove`)
- **Root cause:** sections 2/3/5 assumed the player due after the mandated opener always holds a legal move. Real probability of blocked deal ≈13%. The post-fuzz guard in `bridge_analysis_snapshot_create` then *correctly* refused analysis creation → CHECK failed.
- **Failure scenario:** random deals make the suite fail intermittently; CI would show phantom regressions.
- **Fix:** `ensureCurrentPlayerCanMove(s)` — resolves forced draws exactly as real play does before any analysis request.
- **Verification:** stability probe (see FIX‑05 final count).

## FIX‑05 — SmokeTest flake part B (helper spun forever in boneyard-less modes)
- **Severity:** MEDIUM (my first cut of FIX‑04 was itself buggy — logged per protocol honesty rules)
- **File:** same helper, v3 (anchor: `Nothing to draw (1v1v1 / 2v2`)
- **Root cause:** in 1v1v1/2v2 `drawableCount()==0` structurally, so `resolve_forced_draw` returns **Ok while drawing nothing**; naive "draw then re-check" loop never advanced the turn.
- **Fix:** branch on `boneyardDrawableCount > 0`: draw-loop only when tiles exist; otherwise call `end_turn_with_no_play` to advance.
- **Verification:** **20/20 consecutive clean SmokeTest runs** (was failing 2-in-6 mid-fix).

## FIX‑06 — libFuzzer runtime absent from Xcode 26 toolchain (infrastructure)
- **Severity:** MEDIUM (fuzzing impossible on macOS as-shipped)
- **Files:** new `Tests/IsolynEngineBridgeTests/StandaloneFuzzDriver.cpp`; `run_bridge_fuzz.sh` (anchor: `StandaloneFuzzDriver`)
- **Root cause:** Apple ships `libclang_rt.fuzzer_osx.a` selectively; Xcode 26.6 link fails: library not found.
- **Fix:** script auto-probes (`echo 'int main(){return 0;}' | clang++ -fsanitize=fuzzer`); on failure builds StandaloneFuzzDriver — SAME `LLVMFuzzerTestOneInput` harness under ASan+UBSan with pseudo-random inputs + previous-input mutation. Honest scope note printed: less coverage-guided than real libFuzzer.
- **Verification:** 50,000 executions post-FIX‑07, zero findings.

## FIX‑07 — Terminal-round guard (audit F‑03): play could continue past a finished round
- **Severity:** HIGH
- **Confidence:** High (code-read + regression test)
- **Files:** `Sources/IsolynEngineBridge/include/IsolynBridge.hpp:138` (anchor `RoundAlreadyOver = 10`); `IsolynBridge.cpp` ×4 guards; `Sources/IsolynApp/Engine/EngineTypes.swift` (anchor `roundAlreadyOver`); `SmokeTest.cpp` terminal section
- **Root cause:** mutating commands checked stale-version but never round-state. A **Closed** position self-rejects via legality, but a **DominoVictory** leaves opponents holding legal moves — fresh-version commands kept mutating a finished round.
- **Failure scenario:** racing/buggy UI extends a completed round; future score/orchestration consumers compute from corrupted semantics.
- **Finality:** *"If each mutator returns RoundAlreadyOver when cachedRoundOutcome != InProgress (checked AFTER the stale gate), no post-terminal mutation can occur."*
- **Fix:** enum value 10 added (additive ABI-safe); guard inserted immediately after stale check in submit_move / voluntary_draw / resolve_forced_draw / end_turn_with_no_play. Ordering rationale: duplicate taps still report StaleRequest (idempotent), genuinely fresh commands report the round gate.
- **Verification:** new SmokeTest section drives random legal play to a REAL outcome then asserts all four mutators return `RoundAlreadyOver` with **stateVersion unchanged**. Suite 33→40 checks, all green.

## FIX‑08 — ScoreSystem lacked participant-count accessor (additive)
- **Severity:** LOW (compile blocker for Phase 1c caller, not a defect)
- **File:** `Sources/IsolynEngine/include/ScoreSystem.hpp:20`
- **Fix:** `int participantCount() const` returning `m_scores.size()`.
- **Verification:** engine suite re-run 356/356 unchanged.

## FIX‑09 — Match orchestration surface (Phase 1c feature w/ logged invariants)
- **Severity:** feature (invariants below are the audit-relevant part)
- **Files:** `IsolynBridge.hpp:225,309` region; `IsolynBridge.cpp` MatchStateImpl; `EngineSession.swift:152`; `MatchCoordinator.swift`
- **Invariants enforced & tested:**
  1. Reveal-on-end only — `finalHandValues[]` zeroed while round live (no hidden-info leak).
  2. Duplicate record rejection — `recordedSessions` unordered_set + bridge-side check; double-apply impossible.
  3. Lock ordering SESSION→MATCH everywhere single global order ⇒ deadlock-free.
  4. Next starter derived from cachedDecidingPlayer via RulesEngine (single truth).
- **Verification:** SmokeTest match section (10 checks incl. reveal-sum consistency vs computeRoundScores semantics, starter propagation, cross-round accumulation). Suite 40→57. ASan+UBSan over new paths clean.

## FIX‑10 — `Move` missing Hashable (Phase 2 prerequisite)
- **File:** `Sources/IsolynApp/Engine/EngineTypes.swift` (anchor `struct Move: Sendable, Equatable, Hashable`)
- **Why:** GameViewModel legality lookups use `Set<Move>`; O(1) membership requires Hashable.
- **Verification:** swift build clean.

## FIX‑11 — Phase 1c wiring gap: `GameSnapshot.finalHandValues` never parsed Swift-side
- **Severity:** MEDIUM (bridge sent data; Swift DTO silently lacked it — caught during Phase 2 overlay build)
- **File:** `Sources/IsolynApp/Engine/EngineTypes.swift` (anchors: `finalHandValues` ×2)
- **Root cause:** Phase 1c added the C++ field + C++ population but I never updated the Swift DTO mapping in the same pass. Audit lesson applied to myself: claimed-vs-real divergence is exactly what this project's audits hunt.
- **Fix:** property + tuple-reinterpretation parse (same `withTupleAsArray` pattern as siblings).
- **Verification:** overlay renders real reveal values; swift build/test green.

## FIX‑12 — False turn invariant in GameViewModel.refresh
- **Severity:** MEDIUM (SIGTRAP crash in first headless test run)
- **File:** `Sources/IsolynApp/Game/GameViewModel.swift` (anchor: `Fresh-round pivot`)
- **Root cause:** asserted `currentPlayerIndex == requestingPlayerIndex` unconditionally; false on FIRST fetch of any round because `dealFirstRound` already advanced past the opener (seed fetch starts at player 0).
- **Fix:** one documented pivot — if fetched requester ≠ current seat, update index and re-fetch once. Assert retained POST-pivot where it genuinely holds.
- **Verification:** previously-crashing suite now passes.

## FIX‑13 — @Observable macro forbade nonisolated stored handle (Swift 6)
- **File:** `Sources/IsolynApp/Engine/MatchCoordinator.swift` (anchor: `deliberately NOT @Observable`)
- **Root cause:** Observation macro synthesizes accessors incompatible with `nonisolated var`. Inspection showed ZERO views observed the coordinator directly (all reads via VM passthroughs).
- **Fix:** stripped `@Observable` (+Observation import) — dead machinery removed rather than fought.
- **Verification:** build clean; behavior identical.

## FIX‑14 — Cxx interop poisons SwiftUI ForEach inference
- **File:** `RoundEndOverlay.swift` (anchor: `struct RevealRow`)
- **Symptom:** `ForEach(rows, id:\.self)` inside `return AnyView(VStack{…})` resolved to the Binding-collection overload → type errors, even with Array data.
- **Fix:** extracted typed row view `RevealRow` so closure bodies are trivially typed. Documented here because ANY future SwiftUI list in this package will hit the same wall.
- **Verification:** build clean.

## OPS‑01 — Repository initialization (audit F‑06)
`git init -b main`, .gitignore (.build/, build/, *.o, *.dSYM, .DS_Store, graphify-out/cache/). Six-commit history now on GitHub private repo `Johan21era/isolyn`.

## OPS‑02 — GitHub auth journey
Keychain PAT lacked repo-create + push scopes (403s documented). Resolution: local ed25519 keypair generated (`~/.ssh/id_ed25519`), public half added to account, remote flipped to SSH, host keys seeded from api.github.com/meta (not blind TOFU).

## OPS‑03 — Weight remediation
Build residue peaked 597 MB (SwiftPM .build 482 MB + sanitizer binaries 108 MB). Nuked twice per owner directive; steady-state folder = ~7 MB. Remote repo unaffected (gitignore held from commit #1).
