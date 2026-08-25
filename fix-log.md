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
- **Worst-case impact:** all 25 environment tests permanently unverifiable; the project's long-flagged interop uncertainty was never answerable until this fix.
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

---

# SESSION: CORE HARDENING (2026-08, post-audit roadmap execution)

> Executed from `core hardening roadmap.md` with owner authorization.
> Baseline at session start: engine 356/356 · bridge 57/57 · swift 28/0 ·
> build clean-with-one-SPM-warning. Every entry below verified by actual
> command output shown in-session.

## FIX‑15 — EnvironmentManager weather race (audit F‑04)
- **Severity:** MEDIUM · **Confidence:** High (repro'd warning, fix applied, suite green)
- **Files:** `EnvironmentManager.swift`, `LiveWeatherService.swift`, `EnvironmentTests.swift` (@MainActor test class), `EnvironmentView.swift` (@MainActor preview helper)
- **Root cause:** `weatherSource`/`weatherMode`/`currentSkyCondition` mixed MainActor writes (UI) with arbitrary-executor reads/writes (Tasks, foreground observer); `LiveWeatherService.lastKnownGood` mutated on any caller's executor under a bare `@unchecked Sendable`.
- **Failure scenario:** `.live` mode-switch or foreground event landing mid-fetch corrupts cached condition (narrow-window race).
- **Finality:** *"Confining the manager to @MainActor and capturing the source before any await removes every unsynchronized cross-thread access."* → compiler-enforced after conversion; sole prior concurrency warning (`EnvironmentManager.swift:146`) gone.
- **Fix:** whole-class `@MainActor`; unstructured Tasks inherit isolation; `refreshWeather` captures source into a local pre-await; `lastKnownGood` behind NSLock so Sendable is earned not asserted.
- **Verification:** zero-warning build; swift test green; manual toggle path unchanged behaviorally.

## FIX‑16 — Cancel-on-abandon for analyses (audit F‑10)
- **Severity:** LOW→MEDIUM (CPU/handle waste) · **Confidence:** High
- **Files:** `InteractiveGameBoardView.swift`, `EngineSession.swift`, `GameViewModel.swift`
- **Fix:** `.onDisappear { viewModel.shutdown() }`; lifecycle contract documented on `AnalysisTask` (await OR cancel before dropping); `invalidateAnalysis()` documented as the single funnel every discard routes through.
- **Verification:** build+test green; teardown path now cancels within one determinization sample.

## FIX‑17 — BeliefState.applyOpponentDraw totality (audit F‑11)
- **Severity:** LOW (latent) · **Confidence:** High · **ENGINE CHANGE — test-first per house rule #5**
- **Files:** `BeliefState.cpp/.hpp`, `BeliefStateTests.cpp`
- **Root cause:** debug-only assert guarded boneyard-mass precondition; under NDEBUG division by zero mass (and worse: FP-drift NEGATIVE mass silently corrupts every distribution).
- **Honesty note:** the new test cannot be red-first for exact-zero (old code no-op'd safely there); its value is pinning the contract + the guard's protection is the negative-drift case. Stated in-test.
- **Fix:** early-return guard replaces assert; header documents totality ("no-op is safety netting, not license").
- **Verification:** `run_tests.sh` **356 → 362**, zero warnings.

## FIX‑18 — Unknown analysis handle reports truthfully (audit F‑07)
- **Severity:** LOW · **Confidence:** High
- **Files:** `IsolynBridge.cpp`, `IsolynBridge.hpp`, `SmokeTest.cpp`
- **Root cause:** table-miss returned `SessionClosed` — a SESSION word — violating AnalysisResultDTO's own declared status set (BridgeFailure/EngineFailure only).
- **Fix:** returns `BridgeFailure`; header comment names the mapping explicitly.
- **Verification:** new SmokeTest check asserts BridgeFailure for `kInvalidAnalysisHandle`. Bridge suite **57 → 58**, all green.

## FIX‑19 — Observable enum divergence + HandleTable truthing (audits F‑08/F‑12)
- **Severity:** LOW · **Confidence:** High
- **Files:** `EngineTypes.swift`, `IsolynBridge.cpp`
- **Fix:** all three `@unknown default` DTO fallbacks now emit `os_log` faults (subsystem `com.isolyn.app`, category `bridge-dto`) instead of silently presenting finished rounds as `.inProgress`; deleted the no-op `if (m_nextId == 0) m_nextId = 0;` "clamp" and replaced with a truthful comment (the entry guard IS the exhaustion story).
- **Verification:** build clean; bridge suite green (no behavior change intended or observed).

## FIX‑20 — CI pipeline (roadmap P3a / audit remediation-plan item 10)
- **OPS severity** · **Files:** new `.github/workflows/ci.yml`
- Push/PR: swift build + swift test + run_tests.sh + run_bridge_tests.sh. Weekly scheduled fuzz job keeps adversarial coverage fresh. Makes F-02-class drift structurally impossible to reintroduce unnoticed.

## OPS‑05 — Sanitizer baseline harness + recorded results (roadmap P3b)
- **Files:** new `run_sanitize.sh` (address|thread modes; compile-once/link-many; `-fno-sanitize-recover=all`; bash-3.2-safe array expansion)
- **Results this session, verbatim:** address mode = 20 executables, **420 checks, ZERO findings**; thread mode = SmokeTest + SearchEngineCancellationTests, **73 checks, ZERO findings**.
- One script bug found-and-fixed during its own shakedown (empty-array expansion under `set -u`).

## FIX‑21 — Hue slider black-tile bug (NEW finding N-1)
- **Severity:** HIGH (visible correctness failure in shipped UI) · **Confidence:** High (regression test written)
- **Files:** `DominoAppearance.swift`, `AppearanceManager.swift`, `SettingsDrawer.swift`, new `ColorMathTests.swift`
- **Root cause:** hue math routed through a static `_hexCache` keyed on SwiftUI Color that `Color.init(hex:)` never populated → S/B read as (0,0) → every hue drag snapped tile body to BLACK; slider thumb pinned at hue 0; unsynchronized global mutable state besides.
- **Fix:** cache deleted entirely; conversions are pure functions over hex strings (`hsb(fromHex:)` / `hexString(fromHue:saturation:brightness:)`); both consumers read via them.
- **Verification:** 7 new tests incl. ivory hex round-trip stability and the exact regression (hue drag never collapses to black). swift test **28 → 35**.

## FIX‑22..25 — Appearance honesty + mechanical sweep (roadmap P4)
- **FIX‑22 (N-2):** settings drawer's Edge Highlight section was decorative; now renders (mode gates on/off, intensity drives opacity+width). Analytical `semanticEdge` always wins precedence. File: `IsolynDominoTile.swift`.
- **FIX‑23 (F-09):** DateFormatter cached per timezone (was allocated every tick). File: `EnvironmentTimeLabel.swift`.
- **FIX‑24 (N-4):** PipGlyph counts ≥7 render a truthful monospaced digit (a full 1v1/2v2 rack used to show BLANK); opponent counts pass through unclamped. Never fabricate pip arrangements real dominoes don't have. Files: `PipGlyph.swift`, `InteractiveGameBoardView.swift`.
- **FIX‑25 (N-6):** Package.swift excludes Info.plist → swift build is now ZERO-warning.
- **Verification:** swift test 35/0; zero warnings.

## FIX‑26 — Hover-chain exit logic + wire-or-remove executed (roadmap P5 / N-3 + audit limbo item)
- **Severity:** MEDIUM UX-integrity · **Confidence:** High
- **Files:** `HoverChainController.swift`, `ChainAndZonesView.swift`, `HoverChainOverlay.swift`, `RoundEndOverlay.swift`, `IsolynApp.swift`
- **Root cause:** comments promised overlay "exit logic" that was never built — once hovered, the panel stuck forever.
- **Fix:** grace-period dismissal (250ms) scheduled on hover-out of zone AND overlay, cancelled on re-entry; explicit ✕ close button; auto-dismiss when a tile plays (stale analysis worse than none); camera-drag suspend preserved; deleted no-op `handleHover` stub, unused `displayLeft/displayRight`, unused `RulesOfDisplay`.
- **Limbo ended:** `EnvironmentSettingsView` (compiled-but-unreachable since batch 5) is now hosted in the platform Settings scene (⌘,) — the audit's recommended resolution, chosen over removal.
- **Verification:** zero-warning build; swift test 35/0; bridge 58/58.

## OPS‑06 — Session closeout
- All proof gates re-run at end-of-session (see legacy handoff.md §6 for expected outputs, updated this session). Tagged `core-hardened-1`.

## OPS‑07 — Build-residue recurrence + guardrail (OPS-03 lesson re-learned)
- **What happened:** the core-hardening session's builds (SwiftPM cache + 18
  engine binaries + ASan/TSan instrumented objects) regrew the folder to
  **500 MB** (.build 362 MB, build/ 128 MB). Owner flagged it; OPS-03 already
  documented this exact failure mode and should have been applied proactively
  after the sanitizer sweep.
- **Resolution:** deleted both dirs on the spot — folder back to **9.7 MB**
  steady-state in under a minute. Git unaffected (both paths gitignored from
  day one; .git = 2.6 MB). Nothing tracked was touched.
- **Guardrail:** new `clean.sh` — one command restores steady state; deletes
  only `.build/`, `build/`, `.DS_Store`; sources/tests/docs/git untouchable by
  construction. Standing rule for every future session: run it before handing
  the machine back.

## OPS‑08 — Two new standing house rules (owner directive)
1. **Unlimited testing, zero residue.** Builds/tests/sanitizers/scripts are
   unrestricted DURING work; every generated artifact must be erased when the
   session or phase ends (`./clean.sh`). Codified as handoff §7 rule 7.
2. **Docs must match reality at every session/phase boundary:** fix-log.md
   (protocol entries), tree.md (fresh `tree` regeneration), and graphify-out
   (`graphify update . --force`) refreshed to the exact project state.
   Codified as handoff §7 rule 8.

**Executed immediately for this session:** graphify rebuilt → **1,383 nodes /
2,684 edges / 112 communities** (was 1,077/2,172/80 — reflects the hardening
code + docs); tree.md regenerated (36 dirs / 163 files excl. regenerable
cache); handoff folder map + rules updated; folder size verified at ~10 MB
steady state per rule 7.

---

# UI REBUILD — dominoes_ui_fix_non_negotiable.md EXECUTED

> Owner mandate rejected the previous presentation layer outright and
> specified structure/geometry/hierarchy as law. Executed in the doc's
> mandated order (§29 steps 1→8). Two commits: renderer+board+hand,
> then screen chrome; plus this QA-fix commit.

## UI‑01 — Canonical single-rectangle renderer (§2/§3 — THE core law)
- `IsolynDominoTile` rewritten: EXACT 2:1 ratio in both orientations;
  1pt divider centered at 50% inset from edges; halves reduced to pure
  chrome-less pip regions (no bg/border/radius/shadow); native vertical
  construction replacing rotationEffect; radius clamped 4–6px; canonical
  pip grid 0–6 shared by every tile instance. Appearance edge wiring and
  semanticEdge precedence preserved from FIX-22.
- Anchor: `IsolynDominoTile.swift` → `NON-NEGOTIABLE GEOMETRY LAW`.

## UI‑02 — Snake-chain board (§4–§8)
- `ChainAndZonesView` rebuilt around `SnakeChainBoard`: serpentine runs,
  doubles perpendicular, corner tiles as perpendicular row-end caps with
  mathematically guaranteed clearance (pitch 56 vs axis 52). Deterministic
  `.position` layout — nothing but dominoes and end markers ever renders.
- Playable ends marked ON BOARD (`EndMarker` brass rings) ONLY where ≥1
  legal move exists for that side; pulse reserved for selected-tile fits;
  invalid ends never appear. Camera pan restored around the plane.
- QA catch fixed: initial corner straddle design overlapped next-row tiles
  by 11pt → replaced with end-cap scheme before any runtime exposure.

## UI‑03 — Real hand + screen chrome (§9–§14, §28)
- Hand: prominent identical canonical tiles, lift-on-select via render-only
  offset (zero reflow), tap-tap quick-play retained.
- Screen recomposed to §28 exactly: compact header (mode · turn ·
  [P1]SCORE[P2] chips w/ acting highlight) / board owns main region /
  action bar of coherent capsule controls (Draw · Analyze · Reset View ·
  conditional Pass) / hand / status strip (opponents · centered muted
  instruction). All spacing on the 4px scale; type per §22.

**Verification:** swift build ZERO warnings · swift test 35/0 · bridge 58/58
· interaction trace §29-step-7 performed code-level (select/deselect/marker/
place/invalid/draw/analyze/pass paths all resolve through hardened VM+bridge
paths unchanged) · visual QA vs reference composition pending owner's eyes
(headless session cannot screenshot a running GUI — flagged honestly).

## UI‑QA — OWNER VISUAL SIGN-OFF
The one acceptance checkbox a headless session could not tick (§30 visual QA
against the reference composition) is now closed: **owner reviewed the running
app and confirmed the rebuild** ("looks amazing"). All §30 acceptance sections
— domino construction, board, hand, layout, quality — are green with live
verification. The mandate is fully satisfied, not partially.

Post-sign-off directive executed: push all commits (verified none pending),
refresh fix-log/tree.md/graphify to exact state (this entry), erase build
residue per house rule 7.


---

# SESSION: AUDIT REMEDIATION (2026-08-25, owner-approved Phases 0-2 of `audit remediation roadmap.md`)

> Baseline pinned verbatim at Step 0 before any edit: engine 362/362 - bridge
> 58/58 (soak contributing ZERO -- the defect below) - swift build zero-warning -
> swift test 35/0-failures/1-skip. First session in project history where all four
> gates ran green ON TARGET HARDWARE with the repo's own tooling.

## FIX-27 - SoakTest measures RSS on macOS; sanitizer sweep de-confounded (audit OA-1)
- **Severity:** MEDIUM (a headline verification claim was silently unmeasured on the shipping platform) . **Confidence:** High (reproduced both directions, fixed, re-run)
- **Files:** `Tests/IsolynEngineBridgeTests/SoakTest.cpp` (anchor: `Platform RSS reader`, `WARNING: RSS MEASUREMENT UNAVAILABLE`), `run_sanitize.sh` (anchor: `FIX-27 companion`)
- **Root cause:** `currentRssKb()` read only `/proc/self/status` -- Linux-only. On macOS (the shipping platform AND the only CI platform) it returned -1, the run printed one quiet "[inconclusive]" line, exited 0, and `run_bridge_tests.sh` counted it as a passing executable contributing zero checks. The "12,000 cycles, flat memory" claim was unreproducible on the machine everyone actually uses.
- **Failure scenario:** a genuine slow leak on macOS would have been invisible to this suite forever; every scoreboard citation of soak coverage was Linux-scoped without saying so.
- **Finality:** *"A soak test whose measurement is unavailable must be LOUD about measuring nothing; on supported platforms it must produce numbers."* -> proven by run.
- **Fix:** (1) Mach task introspection branch (`task_info(MACH_TASK_BASIC_INFO)` -> resident_size), /proc path preserved for Linux, loud WARNING banner + exit 0 on truly exotic platforms. (2) During verification, the instrumented sweep exposed a SECOND real finding: clang ASan's default ~256MB freed-memory quarantine fills PAST the soak's 200-cycle warmup, so the post-warmup growth check measured the QUARANTINE (~27KB/cycle false FAIL) instead of the program. `run_sanitize.sh` address-mode now pins `quarantine_size_mb=16` so saturation completes inside warmup -- the exact phase that exists to absorb it. LeakSanitizer itself is unsupported on this platform ("detect_leaks is not supported" -- recorded verbatim); the independent detectors are the native-allocator run and the de-confounded instrumented run.
- **Verification (verbatim, macOS, Apple silicon):**
  - Native allocator, 10,000 lifecycles: `VmRSS after warmup: 6352 KB` -> `after all 10000 cycles: 6432 KB` = **80 KB over 9800 cycles (8.4 bytes/cycle)** vs 500 B/cycle threshold; checkpoints flat (6416 KB at cycles 2000/4000/6000). `[pass]`.
  - Quarantine A/B on the same instrumented binary: default -> 32,610 B/cycle plateau artifact [FAIL]; `quarantine_size_mb=16` -> **136 B/cycle, checkpoints 52,240/52,256/52,400 KB [pass]**.
  - Full sweep post-fix: `./run_sanitize.sh address` -> **20 executables, 421 checks passed, 0 failed, Runtime failures: none** (was 420 + silent-no-op).
  - Bridge suite post-fix: **59/58->59 checks** -- SoakTest now contributes a REAL verdict (`./run_bridge_tests.sh`: `Executables run: 2, TOTAL CHECKS PASSED: 59`). SmokeTest cross-thread hammer: 30.4M concurrent queries during one analysis run.


## FIX-28 - Board layout truth + auto-fit resilience + snapshot test seam; FOUND+FIXED latent off-board snake bug (audit OA-4)
- **Severity:** MEDIUM (OA-4 proper) / the discovered snake bug is HIGH-visibility-but-low-probability (any chain >1 row once rendered off-board) . **Confidence:** High (bug reproduced by test BEFORE fix; fix verified by same suite)
- **Files:** `Sources/IsolynApp/Game/ChainAndZonesView.swift` (anchors: `SnakeChainLayout`, `FIX-28 discovery`, `P2b/P2c application`), `Sources/IsolynApp/Game/Camera/BoardCamera.swift` (anchor: `defaultMaxOffsetX`), `Sources/IsolynApp/Engine/EngineTypes.swift` (anchor: `Test construction seam`), NEW `Tests/IsolynAppTests/BoardLayoutTests.swift`
- **Root cause (OA-4):** serpentine rows stacked downward without limit while BoardCamera capped pan at fixed +/-300/+200 -- a near-full-board chain could lay its tail out of reachable view. Also the last unclosed clause of `dominoes_ui_fix_non_negotiable.md` §17 ("scale intelligently ... prevent overflow").
- **FOUND EN ROUTE (pre-existing, not introduced here -- confirmed verbatim in HEAD):** `advance()` incremented the column UNSIGNED (`col += n`) while x moved signed. After the FIRST row-break corner, no second corner could ever fire ((dir<0 && col==0) unreachable going left; col had already passed cols-1 going right), so any chain longer than one row continued LEFT FOREVER off the board's edge instead of snaking. Latent since the snake board shipped; invisible with real mid-game chains (<13 tiles on an 800pt plane); exposed immediately by BoardLayoutTests' synthetic 40-tile chains (diagnostic trace showed y stuck at two values, x running to -720). Fixed with signed advance (`col += n * Int(dir)`), anchor-commented in place.
- **Fix:** (1) ALL placement/extent/fit math hoisted VERBATIM into internal pure `SnakeChainLayout` (orient/compute/fitScale + named constants) -- rendering consumes its data unchanged. (2) Auto-fit: ONE UNIFORM `scaleEffect(suggestedScale)`, engaged only past 94% axis occupancy, clamped 0.62...1.0 -- uniform scaling multiplies both axes equally, so the mandate's exact-2:1 law holds BY CONSTRUCTION; below the floor scaling STOPS and pan takes over (§17 priority order encoded). (3) Content-aware camera bounds: post-scale residual overflow (halved -- offset moves the plane's center) raises maxOffsetX/Y from new named defaults; bounds only ever GROW; mutated in onAppear/onChange closures, never during body evaluation. (4) Test seam: internal test-only `GameSnapshot` init -- tuple DTOs are unfillable element-wise from Swift and `init?(dto:)` suppresses the memberwise initializer, so without this NO headless test can fabricate controlled snapshots (real sessions deal CSPRNG hands). Production paths untouched: snapshots still come ONLY from EngineSession.snapshot(for:) so hidden-info enforcement stays bridge-side.
- **Verification:** `swift build` zero warnings; `swift test` -> **Executed 45 tests, with 1 test skipped and 0 failures** (was 35; +10 BoardLayoutTests covering orient-flip correctness, corner-cap placement, marker-clearance vs double-protrusion extents (hand-derived 34 vs 52pt), fit-scale exactness/threshold/tighter-axis/floor/monotonicity, degenerate guards, and multi-row serpentine integrity with in-bounds x assertions that FAIL against the pre-fix bug). Engine suite untouched (362/362 via earlier gate this session). Long-chain visual behavior flagged for owner eyeball at next app launch (headless session cannot screenshot GUI) -- risk-register item anticipated this.
