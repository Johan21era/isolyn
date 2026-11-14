# ISOLYN FIX LOG

> **Status: append-only historical log.** Entries record the state of the tree on
> the date they were written; their counts are receipts, not current figures.
> Current state lives in `docs/audits/2026-11-13-audit.md`. Never rewrite an
> entry — append a new one.

> Format follows `aggressive-bug-fix-protocol.md` (12 fields per entry,
> compressed). Every entry below was executed and VERIFIED during the
> 2026‑08 session that produced commits `b79a3f4 → 0d63200`.
>
> **How to verify any entry:** see "Check My Work" in `docs/history/legacy-handoff.md` —
> every fix cites a grep-able anchor string; search the named file for it.

---

## LEGEND
Severity: CRITICAL / HIGH / MEDIUM / LOW / OPS (non-code infrastructure)
Status: FIXED+VERIFIED means: change applied AND proven by an actual command
run whose output is quoted in the Verification field or reproducible via
docs/history/legacy-handoff.md §CHECK-MY-WORK.

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
- **Files:** `scripts/ci/test_engine.sh`, `scripts/ci/test_bridge.sh`, `scripts/ci/fuzz_bridge.sh` (anchors: `framework Security`, `PLATFORM_FLAGS`)
- **Root cause:** EntropySource calls `SecRandomCopyBytes` (Security.framework) on Apple platforms; Package.swift declared the linker setting for SPM consumers only — raw clang/g++ script invocations never linked it.
- **Failure scenario:** all 18 engine executables + bridge suite die at link: undefined `_SecRandomCopyBytes`/`_kSecRandomDefault`.
- **Fix:** Darwin-conditional `-framework Security` injected into compile/link lines (`uname` guard keeps the original Linux workflow intact).
- **Verification:** scripts now report **356/356** and **33/33→57/57** end-to-end on macOS.

## FIX‑03 — Bridge test harness assumed GNU coreutils
- **Severity:** MEDIUM (script false-negatives on macOS)
- **Files:** `scripts/ci/test_bridge.sh` (anchor: `run_with_timeout`)
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
- **Files:** new `Tests/IsolynEngineBridgeTests/StandaloneFuzzDriver.cpp`; `scripts/ci/fuzz_bridge.sh` (anchor: `StandaloneFuzzDriver`)
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

> Executed from `docs/history/roadmaps/core-hardening-roadmap.md` with owner authorization.
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
- **Verification:** `scripts/ci/test_engine.sh` **356 → 362**, zero warnings.

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
- Push/PR: swift build + swift test + scripts/ci/test_engine.sh + scripts/ci/test_bridge.sh. Weekly scheduled fuzz job keeps adversarial coverage fresh. Makes F-02-class drift structurally impossible to reintroduce unnoticed.

## OPS‑05 — Sanitizer baseline harness + recorded results (roadmap P3b)
- **Files:** new `scripts/ci/sanitize.sh` (address|thread modes; compile-once/link-many; `-fno-sanitize-recover=all`; bash-3.2-safe array expansion)
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
- All proof gates re-run at end-of-session (see docs/history/legacy-handoff.md §6 for expected outputs, updated this session). Tagged `core-hardened-1`.

## OPS‑07 — Build-residue recurrence + guardrail (OPS-03 lesson re-learned)
- **What happened:** the core-hardening session's builds (SwiftPM cache + 18
  engine binaries + ASan/TSan instrumented objects) regrew the folder to
  **500 MB** (.build 362 MB, build/ 128 MB). Owner flagged it; OPS-03 already
  documented this exact failure mode and should have been applied proactively
  after the sanitizer sweep.
- **Resolution:** deleted both dirs on the spot — folder back to **9.7 MB**
  steady-state in under a minute. Git unaffected (both paths gitignored from
  day one; .git = 2.6 MB). Nothing tracked was touched.
- **Guardrail:** new `scripts/dev/clean.sh` — one command restores steady state; deletes
  only `.build/`, `build/`, `.DS_Store`; sources/tests/docs/git untouchable by
  construction. Standing rule for every future session: run it before handing
  the machine back.

## OPS‑08 — Two new standing house rules (owner directive)
1. **Unlimited testing, zero residue.** Builds/tests/sanitizers/scripts are
   unrestricted DURING work; every generated artifact must be erased when the
   session or phase ends (`./scripts/dev/scripts/dev/clean.sh`). Codified as handoff §7 rule 7.
2. **Docs must match reality at every session/phase boundary:** docs/history/fix-log.md
   (protocol entries), docs/history/repo-tree-2026-08.md (fresh `tree` regeneration), and graphify-out
   (`graphify update . --force`) refreshed to the exact project state.
   Codified as handoff §7 rule 8.

**Executed immediately for this session:** graphify rebuilt → **1,383 nodes /
2,684 edges / 112 communities** (was 1,077/2,172/80 — reflects the hardening
code + docs); docs/history/repo-tree-2026-08.md regenerated (36 dirs / 163 files excl. regenerable
cache); handoff folder map + rules updated; folder size verified at ~10 MB
steady state per rule 7.

---

# UI REBUILD — docs/history/2026-08-ui-rebuild-mandate.md EXECUTED

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
refresh fix-log/docs/history/repo-tree-2026-08.md/graphify to exact state (this entry), erase build
residue per house rule 7.


---

# SESSION: AUDIT REMEDIATION (2026-08-25, owner-approved Phases 0-2 of `docs/history/roadmaps/audit-remediation-roadmap.md`)

> Baseline pinned verbatim at Step 0 before any edit: engine 362/362 - bridge
> 58/58 (soak contributing ZERO -- the defect below) - swift build zero-warning -
> swift test 35/0-failures/1-skip. First session in project history where all four
> gates ran green ON TARGET HARDWARE with the repo's own tooling.

## FIX-27 - SoakTest measures RSS on macOS; sanitizer sweep de-confounded (audit OA-1)
- **Severity:** MEDIUM (a headline verification claim was silently unmeasured on the shipping platform) . **Confidence:** High (reproduced both directions, fixed, re-run)
- **Files:** `Tests/IsolynEngineBridgeTests/SoakTest.cpp` (anchor: `Platform RSS reader`, `WARNING: RSS MEASUREMENT UNAVAILABLE`), `scripts/ci/sanitize.sh` (anchor: `FIX-27 companion`)
- **Root cause:** `currentRssKb()` read only `/proc/self/status` -- Linux-only. On macOS (the shipping platform AND the only CI platform) it returned -1, the run printed one quiet "[inconclusive]" line, exited 0, and `scripts/ci/test_bridge.sh` counted it as a passing executable contributing zero checks. The "12,000 cycles, flat memory" claim was unreproducible on the machine everyone actually uses.
- **Failure scenario:** a genuine slow leak on macOS would have been invisible to this suite forever; every scoreboard citation of soak coverage was Linux-scoped without saying so.
- **Finality:** *"A soak test whose measurement is unavailable must be LOUD about measuring nothing; on supported platforms it must produce numbers."* -> proven by run.
- **Fix:** (1) Mach task introspection branch (`task_info(MACH_TASK_BASIC_INFO)` -> resident_size), /proc path preserved for Linux, loud WARNING banner + exit 0 on truly exotic platforms. (2) During verification, the instrumented sweep exposed a SECOND real finding: clang ASan's default ~256MB freed-memory quarantine fills PAST the soak's 200-cycle warmup, so the post-warmup growth check measured the QUARANTINE (~27KB/cycle false FAIL) instead of the program. `scripts/ci/sanitize.sh` address-mode now pins `quarantine_size_mb=16` so saturation completes inside warmup -- the exact phase that exists to absorb it. LeakSanitizer itself is unsupported on this platform ("detect_leaks is not supported" -- recorded verbatim); the independent detectors are the native-allocator run and the de-confounded instrumented run.
- **Verification (verbatim, macOS, Apple silicon):**
  - Native allocator, 10,000 lifecycles: `VmRSS after warmup: 6352 KB` -> `after all 10000 cycles: 6432 KB` = **80 KB over 9800 cycles (8.4 bytes/cycle)** vs 500 B/cycle threshold; checkpoints flat (6416 KB at cycles 2000/4000/6000). `[pass]`.
  - Quarantine A/B on the same instrumented binary: default -> 32,610 B/cycle plateau artifact [FAIL]; `quarantine_size_mb=16` -> **136 B/cycle, checkpoints 52,240/52,256/52,400 KB [pass]**.
  - Full sweep post-fix: `./scripts/ci/sanitize.sh address` -> **20 executables, 421 checks passed, 0 failed, Runtime failures: none** (was 420 + silent-no-op).
  - Bridge suite post-fix: **59/58->59 checks** -- SoakTest now contributes a REAL verdict (`./scripts/ci/test_bridge.sh`: `Executables run: 2, TOTAL CHECKS PASSED: 59`). SmokeTest cross-thread hammer: 30.4M concurrent queries during one analysis run.


## FIX-28 - Board layout truth + auto-fit resilience + snapshot test seam; FOUND+FIXED latent off-board snake bug (audit OA-4)
- **Severity:** MEDIUM (OA-4 proper) / the discovered snake bug is HIGH-visibility-but-low-probability (any chain >1 row once rendered off-board) . **Confidence:** High (bug reproduced by test BEFORE fix; fix verified by same suite)
- **Files:** `Sources/IsolynApp/Game/Board/ChainAndZonesView.swift` (anchors: `SnakeChainLayout`, `FIX-28 discovery`, `P2b/P2c application`), `Sources/IsolynApp/Game/Camera/BoardCamera.swift` (anchor: `defaultMaxOffsetX`), `Sources/IsolynApp/Engine/EngineTypes.swift` (anchor: `Test construction seam`), NEW `Tests/IsolynAppTests/BoardLayoutTests.swift`
- **Root cause (OA-4):** serpentine rows stacked downward without limit while BoardCamera capped pan at fixed +/-300/+200 -- a near-full-board chain could lay its tail out of reachable view. Also the last unclosed clause of `docs/history/2026-08-ui-rebuild-mandate.md` §17 ("scale intelligently ... prevent overflow").
- **FOUND EN ROUTE (pre-existing, not introduced here -- confirmed verbatim in HEAD):** `advance()` incremented the column UNSIGNED (`col += n`) while x moved signed. After the FIRST row-break corner, no second corner could ever fire ((dir<0 && col==0) unreachable going left; col had already passed cols-1 going right), so any chain longer than one row continued LEFT FOREVER off the board's edge instead of snaking. Latent since the snake board shipped; invisible with real mid-game chains (<13 tiles on an 800pt plane); exposed immediately by BoardLayoutTests' synthetic 40-tile chains (diagnostic trace showed y stuck at two values, x running to -720). Fixed with signed advance (`col += n * Int(dir)`), anchor-commented in place.
- **Fix:** (1) ALL placement/extent/fit math hoisted VERBATIM into internal pure `SnakeChainLayout` (orient/compute/fitScale + named constants) -- rendering consumes its data unchanged. (2) Auto-fit: ONE UNIFORM `scaleEffect(suggestedScale)`, engaged only past 94% axis occupancy, clamped 0.62...1.0 -- uniform scaling multiplies both axes equally, so the mandate's exact-2:1 law holds BY CONSTRUCTION; below the floor scaling STOPS and pan takes over (§17 priority order encoded). (3) Content-aware camera bounds: post-scale residual overflow (halved -- offset moves the plane's center) raises maxOffsetX/Y from new named defaults; bounds only ever GROW; mutated in onAppear/onChange closures, never during body evaluation. (4) Test seam: internal test-only `GameSnapshot` init -- tuple DTOs are unfillable element-wise from Swift and `init?(dto:)` suppresses the memberwise initializer, so without this NO headless test can fabricate controlled snapshots (real sessions deal CSPRNG hands). Production paths untouched: snapshots still come ONLY from EngineSession.snapshot(for:) so hidden-info enforcement stays bridge-side.
- **Verification:** `swift build` zero warnings; `swift test` -> **Executed 45 tests, with 1 test skipped and 0 failures** (was 35; +10 BoardLayoutTests covering orient-flip correctness, corner-cap placement, marker-clearance vs double-protrusion extents (hand-derived 34 vs 52pt), fit-scale exactness/threshold/tighter-axis/floor/monotonicity, degenerate guards, and multi-row serpentine integrity with in-bounds x assertions that FAIL against the pre-fix bug). Engine suite untouched (362/362 via earlier gate this session). Long-chain visual behavior flagged for owner eyeball at next app launch (headless session cannot screenshot GUI) -- risk-register item anticipated this.

---

# SESSION: ENGINE/SEARCH/EVALUATION OVERHAUL + METAL BATCH EVALUATOR (2026-11-11)

> Current worktree, intentionally uncommitted. This is the closeout receipt for
the session; all earlier entries retain their original historical numbers.

## ENGINE-01 — Search, terminal scoring, evaluation, difficulty, and AI mode
- **Files:** `Sources/IsolynEngine/SearchEngine.cpp`, `EvaluationEngine.cpp`,
  `GameState.cpp`, the matching headers, `Sources/IsolynEngineBridge/*`,
  `Sources/IsolynApp/Game/Opponent.swift`, difficulty/AI tests, and the lab.
- **Why:** finish the engine/search/evaluation overhaul without changing the
  bridge's POD contract or silently changing the public evaluation contract.
- **What landed:** iterative deepening, alpha-beta/team negamax for 1v1 and
  2v2, full-width maxn for 1v1v1, transposition table with exact bounds,
  killer/history ordering, exact endgame solving, the eight-component
  evaluation, root-score selection fixes, terminal-utility ordering, measured
  difficulty tiers, AI turn flow, and self-play/calibration tooling.
- **Verification (2026-11-11):** engine 19 executables / **386 checks**; bridge
  2 executables / **68 checks**; Swift **49 tests, 1 skipped, 0 failures**;
  lab **4 tests**; ASan+UBSan **21 executables / 454 checks**; TSan
  **2 executables / 82 checks**; standalone fuzz **37,500 executions** with zero
  crashes, hangs, or sanitizer findings.
- **Limitations:** difficulty labels remain provisional; no external-engine
  Elo claim. The measured ladder is internal and recorded in `docs/subsystems/LAB.md`.

## METAL-01 — Standalone Metal batch evaluator
- **Files:** `Accelerator/` — runtime-compiled MSL, generic and compact kernels,
  CPU reference, position/feature encoders, parity/failure tests, benchmark.
- **Verification:** `./Accelerator/build.sh` passed: generic and compact
  CPU/GPU parity, 1v1/1v1v1/2v2/closed/terminal coverage, malformed-batch
  rejection, and compact throughput. Development M3, 16,384-position batch:
  CPU ~10.4M positions/sec; Metal ~24-28M positions/sec (~2.3-2.7x across runs).
- **Limitation:** evaluator microbenchmark only. The accelerator is **not wired
  into `SearchEngine`**, so this is not a search-speed or strength claim.

## OPS-10 — Closeout Initiative
- **Documentation sweep:** `README.md`, `Accelerator/README.md`,
  `docs/subsystems/ACCELERATOR.md`, `docs/architecture/BRIDGE_ARCHITECTURE.md`,
  `docs/engineering/BRIDGE_TESTING.md`, `docs/engineering/OPEN_DECISIONS.md`, `docs/roadmaps/strategy-roadmap.md`,
  `docs/history/legacy-handoff.md`, `tools/selfplay/README.md`, `tree.md` (retired 2026-11-13), and this file.
  `docs/subsystems/LAB.md` and `lab/README.md` were reviewed and needed no numeric change.
- **Documentation gate:** the Monarcha/Asterisma `documentation_audit.py` gate
  does not exist in this repository. Manual path/count/claim review was run;
  the gate itself is **SKIPPED** with that reason, not presented as a pass.
- **Verification sweep:** commands and results above are current; no skipped
  test stage is counted as a pass. The accelerator harness is separate from the
  SPM suite, and that separation is intentional.

## PERF-01 — CPU evaluator/hash and Metal kernel throughput round (2026-11-11)
- **Files:** `Sources/IsolynEngine/{MoveGenerator,MobilityHeuristic,BlockingHeuristic,GameState,SearchEngine}.cpp`, their headers, `Tests/IsolynEngineTests/MoveSystemTests.cpp`, `Accelerator/src/MetalAccelerator.mm`, `Accelerator/shaders/evaluation.metal`, `Accelerator/src/EvaluationShaderSource.hpp`, `Accelerator/tests/AcceleratorTests.mm`, and the benchmark/self-play tools.
- **CPU measured (short-run, pre-hardening):** evaluation 1v1/1v1v1/2v2 **30.9M/24.8M/17.0M** player-evals/s versus the recorded **10.9M/8.8M/5.0M** baseline; hash **50.9M/37.8M/29.3M**/s versus **10.9-20.6M**/s; movegen **43.5-43.9M**/s versus **~28-38M**/s. The sustained median figures below are the ones to use for capacity planning. Mobility/blocking now use allocation-free legal-move counts, and `GameState::hash` sorts hand indices in a stack array.
- **Self-play:** fixed seed 21, depth 4, 20 determinizations. 1v1: 100 games, 3,360,695 nodes / 0.82s = **4.10M nodes/s** (baseline normalized 3.09M/s). 1v1v1: 20 games, 2,482,394 / 0.57s = **4.35M/s** (baseline 2.19M/s). 2v2: 20 games, 1,045,161 / 0.38s = **2.75M/s** (baseline 1.44M/s).
- **Metal measured:** warmed medians of 32 dispatches: 1K **3.5-4.4M/s**, 4K **16.6-18.1M/s**, 16K **45-58M/s**, 65K **129-136M/s**; host encode **35-46M positions/s**. Persistent shared buffers, table-driven tile geometry, and a 65,536-position cap. Controlled A/B at 65K: arithmetic **68-69M/s** versus LUT **129-136M/s** (~1.9x). The max-size kernel is ~7.6-7.9x the CPU evaluator; encode+dispatch is ~33M/s, so host encoding is now the bottleneck.
- **Rejected/neutral:** the first fixed-buffer generation attempt temporarily regressed the public movegen benchmark to ~29-32M/s; restoring the vector `generate()` path recovered ~43-44M/s. The search-only allocation-free path remained end-to-end neutral, so no search-speed claim is made for that experiment; the public vector API remains.
- **Verification:** engine 19 executables / **386 checks**; bridge **68 checks**; ASan+UBSan **21 executables / 454 checks**; accelerator **71 checks**; `git diff --check` clean. No commit or push.
- **Junk-artifact audit:** `469M -> 48M`. Removed only regenerable
  `.build/`, root `build/`, `Accelerator/build/`, and `.DS_Store` files. Kept
  `lab/data/` measurements, `graphify-out/` reports/graphs, source, tests, docs,
  `.git/`, and every unknown artifact.
- **Graph refresh:** `graphify update . --force` -> **1,936 nodes / 3,581
  edges**; `graph-3d-full.html` regenerated and `--check` passed; `graph.json`
  SHA-256 `9834bbd7780fd88dc82da1ee96ae5c58e8dcd5dafe25dd4a6eeeb83563f3c26c`.
  Interactive WebGL opening was not independently verified; the generated page
  is 2.56 MiB and its byte-level check passed.
- **Owner gate:** no commit and no push. Commit approval and push approval are
  separate explicit gates; this entry does not claim either.

## STRESS-01 — sustained CPU/Metal stress campaign (2026-11-11)
- **Harness hardening:** `tools/bench/main.cpp` now warms caches/frequency and reports three-sample medians. The earlier un-warmed 0.22s harness varied by nearly 2x under scheduler noise; the hardened three-run ranges below are stable enough for capacity work.
- **Sustained CPU medians:** 1v1/1v1v1/2v2 evaluation **27.5-28.2M / 23.3M / 16.4-16.6M** player-evals/s; movegen **41.5-43.8M**/s; hash **47.4M / 36.0M / 27.4M**/s. The short-run pre-hardening numbers above are not sustained results.
- **Self-play throughput and memory:** 1v1 1,000 games: 32,341,886 nodes / 7.68s = **4.21M nodes/s**, 7.8MB peak. 1v1v1 100 games: 12,205,946 / 2.82s = **4.33M/s**, 7.2MB. 2v2 100 games: 5,369,331 / 1.95s = **2.75M/s**, 7.2MB. 5,000-game 1v1 soak: 165,881,215 nodes / 38.80s = **4.28M/s**, 85,389 decisions, **19.4MB peak**, zero incomplete rounds.
- **Repeatability:** five 200-game 1v1 runs were 1.52-1.55s with identical 6,510,491-node workloads; three 50-game 1v1v1 runs were 1.41-1.42s; three 50-game 2v2 runs were 0.95-0.96s.
- **Depth, samples, deadline:** depth 5 and depth 6, 100 determinizations, and a 5ms per-move budget all completed with zero incomplete rounds; peak RSS stayed at or below 8.7MB. The 5ms run made 826 decisions in 2.12s (about 2.6ms per decision), so the cooperative deadline did not overrun materially.
- **Concurrency:** aggregate 1v1 self-play throughput was 8.10M nodes/s with 2 processes, 13.58M/s with 4, and 19.95M/s with 8; the 8-way run used 7.9MB peak per process and had no failed rounds. This is process-level scaling, not a shared-memory thread benchmark; TSan covers the existing threaded bridge/search paths.
- **Metal soak (pre-face-mask):** five repeated full harness runs at 65K positions measured **132-136M positions/s**; 16K measured **57-63M/s**; host encoding ranged **23-49M positions/s**. The 65K-state fixture peaked at **315MB RSS**; that is fixture/state storage, not a persistent kernel allocation. Every parity, malformed-input, and oversized-batch check passed.
- **Findings:** no crashes, hangs, failed rounds, or time-budget blowups were observed. The remaining measured bottlenecks are host-side encoding for max-size Metal batches and the finite 4P+4E core budget under 8-way process load. No new engine defect was found in this campaign.

## METAL-02 — face-mask kernel optimization (2026-11-11)
- **Files:** `Accelerator/shaders/evaluation.metal`, `Accelerator/src/EvaluationShaderSource.hpp`, `Accelerator/src/MetalAccelerator.mm`, and the accelerator harness. The embedded MSL is now byte-for-byte identical to the `.metal` reference.
- **Kernel change:** seven precomputed face masks replace the 28-tile scans in mobility, pip control, and immediate-threat checks. Mobility and threat use bitwise intersections plus `popcount`; pip control reuses the mobility already computed for each player.
- **Measured:** 1K **4.3-5.2M**, 4K **17.3-18.6M**, 16K **62-66M**, and 65K **162-170M positions/s** typical. The 10-run 65K median was **168.7M/s**, full range 148-172M/s; host encoding was 43-45M positions/s. The harness peaked at 315MB because it stores 65,536 `GameState` fixtures plus encoded rows.
- **Pipeline analysis:** batch-size scaling shows a roughly **200us** dispatch/completion floor (1K and 4K are both ~0.2ms per call). At 65K, about 4.4MB of input/output moves in ~0.4ms (~11GB/s), so the kernel is compute/dispatch-bound, not bandwidth-bound. Host encoding (~1.5ms for 65K) is the end-to-end bottleneck; the synchronous `waitUntilCompleted` API prevents overlap.
- **Rejected variants:** 7-bit hand-value tables were neutral (~160-175M/s); 64-byte row padding lost the direct A/B (10-run median 163.6M vs 168.7M unpadded); 64-thread groups were slower (median ~162M). All were removed, and the kernel source was revalidated after each restore.
- **Verification:** accelerator harness **83 checks**, three final full sweeps, exact shader/source match, and all 1v1/1v1v1/2v2/closed/terminal/empty-chain/equal-end/threat parity cases passed. No commit or push.

## REGRESSION-01 — post-Metal regression matrix (2026-11-11)
- **Coverage added:** compact Metal parity for an empty chain (`leftEnd < 0`), equal chain ends (double-counted mobility), and a one-tile immediate threat; accelerator harness rose from 71 to **83 checks**.
- **Correctness/stability:** engine **19 executables / 386 checks**; bridge **2 / 68**; ASan+UBSan **21 / 454**; TSan **2 / 82**; Swift **49 tests, 1 skipped, 0 failures**; standalone fuzz **37,500 executions** with zero crashes, hangs, or sanitizer findings. Shader and embedded MSL are byte-for-byte identical; `git diff --check` is clean.
- **Performance regression check:** hardened CPU benchmark 1v1/1v1v1/2v2 evaluation **30.8-31.3M / 24.5-24.7M / 17.4-17.5M** player-evals/s, movegen **42.9-46.2M/s**, hash **50.0-50.8M / 37.7-37.9M / 29.2-29.5M**/s. Self-play: 1v1 1,000 games **7.34s / 4.41M nodes/s**, 1v1v1 100 games **2.67s / 4.57M/s**, 2v2 100 games **1.86s / 2.89M/s**; zero incomplete rounds; peak RSS 7.1-7.9MB. 8-way aggregate: **21.95M nodes/s**, zero incomplete rounds.
- **Metal regression check:** five post-edge-test runs at 65K: **164.2-170.2M positions/s** (median **169.1M/s**); 4K **18.4-18.7M/s**; 1K **4.57-4.80M/s**; 16K normal cluster **63.5-64.3M/s** with two scheduler outliers. Host encoding **22.6-44.9M positions/s**. All 83 checks passed on every run.

## PERF-02 — batch leaf evaluation + inline raw totals (2026-11-11)
- **Files:** `Sources/IsolynEngine/include/EvaluationEngine.hpp`, `Sources/IsolynEngine/EvaluationEngine.cpp`, `Sources/IsolynEngine/SearchEngine.cpp`, `Tests/IsolynEngineTests/EvaluationEngineTests.cpp`.
- **Problem:** each search leaf evaluated once per player. That repeated hand value, mobility, immediate-threat, closed-state scoring, and (in 2v2) team-mobility work for every player, then allocated a `std::vector` for each result. Transposition-table hits also copied that vector.
- **Batch evaluator:** added `EvaluationTotals` (fixed `std::array<double,4>` plus player count) and `EvaluationEngine::evaluateAll`. It computes hand values, mobility, threats, pip control, team support, and blocking contributions once, and computes the closer/round scores once when closed. The existing per-player `evaluate` API and its breakdown remain unchanged.
- **Search integration:** leaves and terminal nodes call `evaluateAll` once; search now carries an inline `RawEvaluation` instead of a heap vector, so TT hits/copies and `bestRaw` updates no longer allocate. Root accumulation remains vector-based because it runs once per candidate/determinization, not per node.
- **Parity coverage:** batch totals are compared with per-player totals for 1v1, 1v1v1, 2v2, terminal, empty-chain, immediate-threat, 2v2-closed, and 2v2-terminal fixtures. Search node and decision counts were identical before and after the change in all three modes.
- **End-to-end self-play (seed 21, depth 4, 20 determinizations):**

  | Workload | Pre-batch | Final | Change |
  |---|---|---:|---:|
  | 1v1, 1,000 games | 7.34s / 4.41M nodes/s | **6.31s / 5.13M nodes/s** | **+16%** |
  | 1v1v1, 100 games | 2.67s / 4.57M nodes/s | **1.64s / 7.44M nodes/s** | **+63%** |
  | 2v2, 100 games | 1.86s / 2.89M nodes/s | **1.14s / 4.71M nodes/s** | **+63%** |

  Node counts were unchanged: 1v1 32,341,886 / 16,822 decisions; 1v1v1
  12,205,946 / 2,186; 2v2 5,369,331 / 2,105. Peak RSS for 1,000 1v1 games
  remained 7.8MB. Repeats were stable: five 200-game 1v1 runs **1.25-1.31s**
  (pre-batch 1.52-1.55s); three 50-game 1v1v1 runs **0.81-0.83s**; three
  50-game 2v2 runs **0.56s**. A depth-5 / 100-determinization 1v1 run completed
  10 games in **0.48s** (3,112,046 nodes, 6.48M nodes/s). Eight concurrent 1v1
  processes completed with zero failed rounds at **19.45-22.15M nodes/s**
  aggregate; that is within the previous 21.95M/s run's process-scheduler
  noise, so no separate concurrency claim is made.
- **Subsystem comparison:** movegen **42.7-45.3M/s** (prior 42.9-46.2M) and hash
  **50.5-51.0M / 37.7-38.0M / 29.4-29.5M**/s (prior 50.0-50.8M / 37.7-37.9M /
  29.2-29.5M) were unchanged. The standalone per-player evaluation benchmark was
  **27.8-29.0M / 22.9-23.1M / 16.0-16.2M** player-evals/s this round versus
  30.8-31.3M / 24.5-24.7M / 17.4-17.5M previously; reordering `evaluate` made
  no difference. That benchmark does not exercise the batch leaf path, and the
  end-to-end search measurements above are the relevant result.
- **Verification:** engine **19 executables / 426 checks**; bridge **2 / 68**;
  ASan+UBSan **21 / 494**; TSan **2 / 82**; Swift **49 tests, 1 skipped, 0
  failures**; standalone fuzz **37,500 executions**, zero findings; accelerator
  **95 checks**. `git diff --check` clean. No commit or push.
- **Limitation:** the accelerator remains standalone and is not wired into
  `SearchEngine`; no Metal search-speed claim is made here.

## STRESS-02 — adversarial verification campaign (2026-11-11)
- **Files:** `Tests/IsolynEngineTests/EvaluationEngineTests.cpp` and
  `Accelerator/tests/AcceleratorTests.mm` (new stress gates); no production
  source was changed in this campaign.
- **Randomized numerical differential:** 250 legal positions per mode (750
  total), constructed from shuffled tiles and 6-15 random legal plays, compared
  `EvaluationEngine::evaluateAll` against per-player `evaluate` for every player.
  Every fifth position used non-default, mixed-sign weights. Maximum absolute
  delta: **0.0** in 1v1, 1v1v1, and 2v2; player-count mismatches: **0**.
- **Large multi-mode Metal batches:** 4,096 compact positions per mode, with
  current-player variation, encoded and evaluated through Metal. All modes
  matched the CPU evaluator with maximum absolute delta **0.0**.
- **Sustained resource runs:**

  | Workload | Result | Peak RSS | Incomplete |
  |---|---:|---:|---:|
  | 1v1, 5,000 games | 163,080,800 nodes / 85,256 decisions / 32.22s | 9.7MB | 0 |
  | 1v1v1, 1,000 games | 121,666,036 nodes / 21,943 decisions / 16.34s | 7.1MB | 0 |
  | 2v2, 1,000 games | 53,815,988 nodes / 20,915 decisions / 11.52s | 7.1MB | 0 |

- **Oversubscription:** 16 simultaneous 1v1 self-play processes on the 8-core M3
  completed **51,246,101 nodes in 2.06s** aggregate (**24.88M nodes/s**) with zero
  incomplete rounds. This is a stability result under 2x CPU oversubscription,
  not a scaling claim.
- **Deadline pressure:** 200 1v1 games with a **1ms per-move** budget completed
  all 200 rounds in 1.26s (3,362 decisions, 6,236,237 nodes), zero incomplete.
  1v1v1 (100 games) and 2v2 (100 games) at the same 1ms budget completed all
  rounds with zero incomplete; they visited 8,285,542 / 2,199 and 5,037,480 /
  2,106 nodes / decisions respectively. A file-descriptor limit of 64 also
  completed a 5-game smoke run; hard address-space/data-segment limits are not
  usable on this macOS host.
- **Heavy search settings:** 20 games each at depth 5 with 50 determinizations
  completed with zero incomplete rounds: 1v1v1 in **2.30s**, 2v2 in **1.01s**.
- **Metal repetition:** three back-to-back harness runs each passed **95/95**
  checks. 65K throughput was **140.3-171.3M positions/s** (316MB fixture RSS).
  With `MTL_DEBUG_LAYER=1` and `MTL_SHADER_VALIDATION=1`, all 95 checks still
  passed with no validation errors; 65K throughput fell to **79.2M/s**, as
  expected from validation overhead.
- **Metal contention:** four concurrent harness processes each passed **95/95**;
  65K throughput degraded to **108.9-148.7M/s** under shared-GPU contention.
  A mixed run of two Metal harnesses plus eight CPU self-play processes passed
  all **95** checks in both Metal processes and completed **26,342,925 CPU nodes**
  with zero incomplete rounds; Metal 65K throughput was **104.5-112.4M/s**.
- **Outcome:** no crashes, hangs, incorrect values, failed batches, incomplete
  rounds, or unexpected search behavior were found. The only unverified
  constraint is a hard memory cap because `RLIMIT_AS` and `RLIMIT_DATA` are
  rejected by this macOS host; sustained RSS was measured instead.
- **Final verification:** engine **19 executables / 426 checks**; bridge **2 /
  68**; ASan+UBSan **21 / 494**; TSan **2 / 82**; Swift **49 tests, 1 skipped,
  0 failures**; standalone fuzz **75,000 executions**, zero findings;
  accelerator **95 checks**. `git diff --check` clean. No commit or push.

## RENAME-01 — IsolynV2.0 identity regathering (2026-11-11)
- **Product identity:** `IsolynV2.0` is now the SPM package name, executable
  product name, generated app-bundle name, `CFBundleDisplayName`/`CFBundleName`,
  and window title. `run.sh` and `scripts/iso` target the new executable.
- **Stable technical identity:** `IsolynEngine`, `IsolynEngineBridge`,
  `IsolynApp`, the source paths, and the C++ `isolyn` namespace were deliberately
  retained. Dots are not legal in Swift module/C++ identifiers, and changing
  them would be a separate ABI/import migration. The bundle identifier remains
  `com.isolyn.app` so existing local app identity is not silently migrated.
- **Inventory:** `docs/architecture/PROJECT_INVENTORY.md` records the component LOC and the
  caller chain from the SwiftUI entry point through `EngineSession`, the bridge,
  `SearchEngine`, and `EvaluationEngine::evaluateAll`, plus the offline lab,
  self-play, and standalone Metal callers.
- **Verification:** `swift package describe` reports package `IsolynV2.0` and
  products `IsolynEngine` / `IsolynV2.0`; `swift build` succeeds; `swift test`
  passes **49 tests, 1 skipped, 0 failures**; engine **426 checks** and bridge
  **68 checks** pass; `run.sh` syntax, `scripts/iso` syntax, `Info.plist`, and
  the renamed binary path were checked. `git diff --check` clean. This entry is
  committed and pushed separately; no production behavior changed.

## PERF-03 — batch leaf Closed/mobility consolidation (2026-11-12)
- **Files:** `Sources/IsolynEngine/include/EvaluationEngine.hpp`,
  `Sources/IsolynEngine/EvaluationEngine.cpp`,
  `Sources/IsolynEngine/SearchEngine.cpp`,
  `Tests/IsolynEngineTests/EvaluationEngineTests.cpp`,
  `Accelerator/src/PositionBatch.cpp`,
  `Accelerator/tests/AcceleratorTests.mm`, and `docs/subsystems/ACCELERATOR.md`.
- **Problem:** the batch leaf path scanned each hand once for its value and again
  for mobility, then scanned a one-tile hand a third time for an immediate win.
  Search also computed `isPositionClosed` at every horizon leaf, even though the
  evaluator was about to compute the same mobility information.
- **Change:** `handFacts()` now produces hand value and legal-move count in one
  hand scan. Immediate threats are derived from that count (`hand size == 1 &&
  legalMoves > 0`), which is exactly the previous predicate. `evaluateAll`
  derives Closed as `boneyard.drawableCount() == 0 && allPlayersStuck`, matching
  `MoveGenerator::isPositionClosed` without another scan; a new
  `evaluateAllWithClosed` entry point accepts a caller-known Closed fact for
  internal closed nodes. Horizon leaves now skip
  `isPositionClosed` entirely, while depth>0 and closed internal nodes retain the
  early-termination scan.
- **Controlled A/B:** a clean worktree at `c7153f0` (pre-change) and the working
  tree were run alternately in the same thermal window, same seed 21, depth 4,
  20 determinizations. Every workload visited identical nodes and decisions.

  | Workload | Pre-change | New | Change |
  |---|---:|---:|---:|
  | 1v1, 200 games (median of 5) | 1.52s | **1.48s** | **−2.6%** |
  | 1v1v1, 100 games (median of 3) | 1.97s | **1.60s** | **−18.8%** |
  | 2v2, 100 games (median of 3) | 1.41s | **1.24s** | **−12.1%** |
  | 1v1, 1,000 games | 7.56s | **7.23s** | **−4.4%** |

  The 1,000-game runs remained 32,341,886 nodes / 16,822 decisions; 1v1v1
  remained 12,205,946 / 2,186; 2v2 remained 5,369,331 / 2,105. Absolute times in
  this A/B window were higher than the earlier PERF-02 run, so only the paired
  deltas are claimed.
- **Independent endurance (seed 777):** 5,000 1v1 games completed 163,242,746
  nodes / 85,087 decisions in 34.98s at 12.9MB peak; 1,000 1v1v1 completed
  122,267,994 / 21,932 in 15.53s at 7.1MB; 1,000 2v2 completed 53,141,099 /
  20,640 in 12.20s at 7.4MB. All had zero incomplete rounds.
- **Deadline pressure (seed 91, 1ms/move):** all runs completed with zero
  incomplete rounds: 200 1v1 (6,105,954 nodes / 3,321 decisions), 100 1v1v1
  (9,199,289 / 2,162), and 100 2v2 (4,897,506 / 2,041).
- **Oversubscription:** 16 concurrent 1v1 processes (125 games each) completed
  **65,843,572 nodes in 3.30s** aggregate (**19.95M nodes/s**) with zero
  incomplete rounds. This is a stability result, not a scaling claim.
- **Metal host encoding:** `encodePositionBatch` now derives each row's Closed
  flag from the hand masks it already builds instead of calling
  `MoveGenerator::isPositionClosed`, and computes pips only for rows that are
  actually closed. Paired 5-run A/B against `c7153f0`, alternating binaries:
  encoding **46.54M → 55.17M positions/s (+18.5%)**; the new paired range was
  54.29-58.02M, and final post-soak runs measured 51.1-57.0M/s. Direct closed-flag
  parity against `MoveGenerator::isPositionClosed` was added for all three modes,
  the closed fixture, and a stuck-hand/nonempty-boneyard fixture.
- **Metal kernel:** no kernel source changed. The final normal harness passed all
  **100** checks with 65K throughput **196-209M positions/s** (313-334us). With
  `MTL_DEBUG_LAYER=1` and `MTL_SHADER_VALIDATION=1`, all 100 checks still passed;
  65K throughput was **80.4M/s** (815us) with validation enabled. Host encoding
  plus one max-size dispatch is now roughly **41M positions/s**; encoding remains
  the end-to-end bottleneck.
- **Verification:** engine **19 executables / 429 checks**; bridge **2 / 68**;
  ASan+UBSan **21 / 497**; TSan **2 / 82**; Swift **49 tests, 1 skipped, 0
  failures**; standalone fuzz **75,000 executions**, zero findings; accelerator
  **100 checks**. `git diff --check` clean. No commit or push.
- **Limitation:** the Metal evaluator remains standalone and is not wired into
  search, so no Metal search-speed claim is made.

## UI-RESP-01 — centered responsive shell (2026-11-12)
- **Files:** `Sources/IsolynApp/Theme/ResponsiveLayout.swift` (new),
  `Views/EntryView.swift`, `Views/ModeSelectorView.swift`,
  `Components/ModeCard.swift`, `Components/PrimaryCapsuleButtonStyle.swift`,
  `Game/InteractiveGameBoardView.swift`, `Game/ChainAndZonesView.swift`,
  `Game/RoundEndOverlay.swift`, `IsolynApp.swift`, `AppState.swift`, and
  `Tests/IsolynAppTests/{BoardLayoutTests,ResponsiveLayoutTests}.swift`.
- **Problem:** fixed 40/64pt leading gutters, an unconstrained three-card row,
  a full-width game header, and a snake layout that started short chains at
  the left edge of a wide column grid. The result drifted toward whichever
  window width the app happened to launch at, and the floating settings
  control competed with the board.
- **Responsive rules:** `IsolynLayout` now defines a 900×620 minimum, a
  1120pt centered content column, a 1600pt board cap, and 24/40/56pt
  horizontal gutters at compact/medium/wide widths. `CenteredContent` is the
  shared centering primitive.
- **Screens:** Entry is a centered brand/action block with a centered
  watermark. The lobby uses a centered adaptive mode grid, a centered setup
  panel, and an equal-width Start action. The game header switches to a
  two-row compact layout below 1040pt, centers the scoreboard geometrically,
  moves appearance settings into the header, and puts the hand/action/status
  bands inside the same centered column. The round overlay is capped at 680pt
  and scrolls on short windows. The window opens centered.
- **Board:** when the complete chain bounding box fits, `SnakeChainLayout`
  translates it to the table center. Oversized chains retain their existing
  serpentine coordinates and auto-fit/pan behavior; a regression test covers
  the centered single-tile case.
- **Verification:** `swift build` succeeds; `swift test` passes **53 tests, 1
  skipped, 0 failures**; `git diff --check` clean. No commit or push.
- **Limitation:** this was compile/test-verified, not visually inspected in a
  running window. The next visual QA pass should check at least 900×620,
  1280×800, 1440×932, and a full-screen 1440×932 MacBook display.

## UI-MIN-01 — Offsuit-minimal table (2026-11-12)
- **Reference:** the owner supplied the mobile poker game *Offsuit* and asked
  for that level of simplicity: erase the dashboard, keep the dominoes facing
  upright and make them bigger, and never fade unplayable dominoes to black.
- **Play screen:** `InteractiveGameBoardView` is now a black field with a back
  arrow, a quiet player row (monogram, name, score, hand-count badge), the
  board, the hand, one short status chip, and a bottom action lane. Removed
  the mode header, turn banner, score cards, opponent-count telemetry,
  dividers, reset-view control, and floating edge brush. Appearance remains
  available through a small top-right paintbrush.
- **Player row:** 1v1 shows You/Rival; 1v1v1 shows You/Rival A/Rival B; 2v2
  shows You/Rival A/Partner/Rival B with team scores repeated for partners.
  The acting seat is the only one at full brightness.
- **Dominoes:** hand short-axis **44pt** (88×44), table short-axis **38pt**
  (76×38), still exact 2:1 canonical rectangles. Hand tiles are not rotated.
  Unplayable hand tiles retain full ivory and are made non-hit-testable
  instead of disabled, so SwiftUI cannot apply a dimming treatment.
- **Actions:** a single wide Draw/Pass button, a small Analyze control, and a
  short status chip (`Select a domino`, `Choose an end`, `Thinking…`, or the
  engine's suggested tile). No fake probabilities or unsupported controls.
- **Round end:** `RoundEndOverlay` now uses a black overlay, one headline, a
  plain reveal list, simple score deltas, and one wide next-round/new-match
  button instead of the bordered scorecard.
- **Charter:** `docs/design/UI_CHARTER.md` has a new §0 design correction that
  supersedes the older panel/mode-wireframe guidance.
- **Verification:** `swift build` succeeds; `swift test` passes **53 tests, 1
  skipped, 0 failures**; `git diff --check` clean. No commit or push.
- **Limitation:** still not visually inspected in a running window. The next
  pass should compare the actual table against the reference at 1080×720 and
  full screen, especially player-row spacing and hand size.

## UI-MIN-02 — fullscreen match setup (2026-11-12)
- **Problem:** the setup screen was a top-stacked dashboard with atmospheric
  stars, warm brown cards, long mode descriptions, an eyebrow label, a blue
  system segmented control, and a disabled Start button. At fullscreen it left
  roughly the lower half of the window empty.
- **Layout:** the lobby now uses the same black field as the table, equal
  vertical spacers around the content, and exactly three equal mode columns.
  The content stays centered at fullscreen and the 900×620 minimum instead of
  hanging from the top.
- **Simplification:** removed the star field, “MATCH SETUP” eyebrow, subtitle,
  seat diagrams, long descriptions, panel border/background, and blue system
  picker. The screen is now title → three compact mode cards → inline opponent
  control → one wide Start button.
- **Default state:** Duel is selected on entry, so Start Match is immediately
  active. The selected card uses a single white border and checkmark.
- **Verification:** temporary `NSHostingView` snapshots at 1600×1000 and
  900×620 confirmed the centered setup composition visually; the temporary
  harness was removed. `swift build` and the full Swift suite pass. No commit
  or push.

## UI-INSPECT-01 — manual family inspector (2026-11-12)
- **Problem:** the number-family panel opened from incidental pointer hover,
  stretched across the table as a brown dashboard, and had no deliberate
  trigger. The owner asked for auto-hover to be erased (optional only), for a
  configurable non-left mouse button to open it, and for the panel itself to
  stop looking ugly.
- **Trigger:** auto-hover is **off by default** and persisted under
  `isolyn.inspection.v1`; Settings has a `Reveal on hover` switch. The default
  manual trigger is **right-click while the pointer is over a domino**.
  Settings can swap to middle click or an extra mouse button. Left click is
  deliberately excluded because it is the play gesture.
- **Routing:** `InspectionEventMonitor` is a local AppKit event monitor with a
  pass-through background view, so it never participates in hit-testing. A
  lightweight `InspectionHoverTracker` records the tile and half under the
  pointer (left/right for horizontal tiles, top/bottom for vertical tiles)
  without re-rendering the chain. The monitor consumes only the configured
  button while a face is tracked; all other mouse events continue unchanged.
- **Presentation:** `HoverChainOverlay` is now a **360pt black card** at the
  top right: `Family N`, the active classification, one row of seven canonical
  dominoes, and a tiny semantic legend. Removed the full-width panel, brown
  treatment, `TARGET` telemetry header, long description, and ambient trigger.
  Manual inspection stays open until close, play, or a state change; the
  optional hover mode retains the grace-period dismissal.
- **Default view:** the inspector opens on the complete classification instead
  of the empty `Base` view, so the knowledge colors carry useful information.
- **Settings fit:** the drawer body now scrolls at the 620pt minimum window
  height, and the edge-highlight picker is a compact menu instead of a
  four-segment control that forced the form wider than the 260pt drawer and
  shifted every label off the left edge.
- **Files:** `InspectionSettings.swift`, `InspectionHoverTracker.swift`,
  `InspectionEventMonitor.swift`, `SettingsDrawer.swift`,
  `InteractiveGameBoardView.swift`, `ChainAndZonesView.swift`,
  `HoverChainController.swift`, `HoverChainOverlay.swift`, `InspectionTests.swift`.
- **Verification:** `swift build` succeeds; `swift test` passes **60 tests, 1
  skipped, 0 failures**; `git diff --check` clean. A synthetic `NSApp`
  right-click confirmed the monitor consumes the configured button and reads
  the hovered face; offscreen 420×160 and 260×620 renders confirmed the compact
  inspector and the unclipped, scrollable settings drawer. No commit or push.
- **Limitation:** the actual right/middle/extra mouse path was not physically
  exercised in the running window; the event monitor and view are compiled and
  unit-tested, and the app must be re-launched for manual QA.

## UI-BOARD-01 — quiet ends, centered chain (2026-11-12)
- **Problem:** playable ends were brass rings carrying pip numbers; they were
  the loudest objects in an otherwise black table. Layout centering also used
  the rings' clearance, so the actual domino chain sat left of the screen
  center even though the hand and player row were centered.
- **Endpoints:** removed `EndMarker` entirely — no rings, labels, plus sign,
  or pulse. The open end is now a 2.25pt ivory tick just outside the end tile:
  **0.30 opacity when the side is available**, **0.80 when the selected tile
  can legally land there**. The 44pt tap target remains invisible. (The
  hover-chain trigger was changed later, in UI-INSPECT-01.)
- **Centering:** `SnakeChainLayout` now computes `contentWidth`/`contentHeight`
  from visible domino bounds only. Endpoint hit targets are excluded, so the
  visible chain bbox sits on the table centerline. A single 2:1 silhouette
  marks the empty-table opening instead of a circle.
- **Verification:** a controlled `NSHostingView` render of a three-tile chain
  at 1600×700 measured the visible bbox at **x = 798.75 / 1600**, confirming
  center. The endpoint tick was present at the open edge and no rings
  rendered. Temporary harness removed. `swift build` and **54 Swift tests, 1
  skipped** pass; `git diff --check` clean. No commit or push.

## UI-MOTION-01 — paced turns, draw flight, round-end reveal (2026-11-12)
- **Problem:** the table resolved computer turns and forced draws in the same
  frame they were requested, so the engine was correct but the game felt
  like a state dump. There was no draw motion at all, and the round-end card
  showed only numeric pip totals, leaving the owner unable to see what the
  opponents actually still held.
- **Pacing:** computer turns now open with a **450ms think beat**, wait
  **200ms before each forced draw** and **240ms after it**, wait **240ms after
  analysis** before submitting, and wait **360ms after the move** before
  refreshing. Human forced draws get a **240ms** beat per draw. The engine is
  still synchronous; only presentation waits, and cancellation still unwinds
  cleanly.
- **Draw flight:** `GameViewModel` publishes a short-lived `DrawEvent` from the
  boneyard delta. `DrawFlightView` sends one to three face-down dominoes from
  the draw lane to the requesting hand (human) or the acting seat (computer).
  Computer draws are published explicitly from the paced AI loop because a
  draw followed immediately by a play has no net hand-size change in the final
  snapshot. Opponent identities stay hidden; the flight is face-down.
- **Hand and board motion:** hand tiles now use stable tile identity with a
  rising insertion and a shrinking removal transition; new chain tiles scale
  in and existing tiles settle with a restrained spring. No confetti, board
  shake, or changing chrome.
- **Round-end reveal:** the bridge's terminal snapshot now carries
  `finalRevealedTiles` and `finalHandCounts` (all sentinel/zero during live
  play). `GameSnapshot.revealedHands` parses them, and `RoundEndOverlay`
  displays every seat's actual remaining dominoes with a staggered flip-in.
  The overlay now waits **650ms** after the final move, then stages the
  headline, each seat row, the score deltas, and the action. The winner's
  empty hand reads `Went out`; closed rounds show every hand that was counted.
- **Privacy tests:** the bridge suite asserts no reveal mid-round, counts equal
  the racks, revealed tiles sum to `finalHandValues`, and unused slots are
  sentinels. A new Swift integration test plays a real 1v1 round to completion
  and checks that opening snapshots are empty, the end snapshot's revealed
  tiles equal the requesting hand and the opponent's hand size, and every
  revealed row sums to its final value.
- **Files:** `IsolynBridge.hpp`, `IsolynBridge.cpp`, `EngineTypes.swift`,
  `GameViewModel.swift`, `DrawFlightView.swift`, `HandRackView.swift`,
  `ChainAndZonesView.swift`, `RoundEndOverlay.swift`,
  `InteractiveGameBoardView.swift`, `RoundRevealTests.swift`, `run.sh`, plus
  the bridge reveal assertions in `SmokeTest.cpp`.
- **Verification:** bridge suite **73 checks passed, 0 failed**; Swift suite
  **62 tests, 1 skipped, 0 failures**; `swift build` succeeds;
  `git diff --check` clean. Graph refresh: **2,146 nodes / 3,973 edges**;
  `scripts/build-graph-3d.py --check` passes. The app bundle was rebuilt and
  relaunched; `run.sh` now clears bundle xattrs and ad-hoc signs the copied
  executable, because macOS was killing the unsigned launch with
  `Code Signature Invalid` before any game code ran. No commit or push.
- **Limitation:** the flight path, stagger timing, and round-end layout were
  compiled and covered by functional tests, but not yet reviewed in the
  running window with a physical mouse. The owner's test remains the source of
  truth for feel and spacing.

## UI-DRAG-01 — larger hand, direct drag-to-play (2026-11-12)
- **Problem:** the hand tiles were readable but still small, and the documented
  "drag a tile to an end" interaction did not exist in the SwiftUI layer --
  hand tiles were buttons only. The board's release-inertia path also received
  `nil` because its separate `lastMouseLocation` state was never assigned.
- **Size:** hand tiles moved from **44pt to 48pt half-axis** (88×44 → 96×48,
  still exact 2:1). Seven tiles plus spacing still fit the 900pt minimum.
- **Drag:** hand tiles now use a 3pt-threshold drag gesture in the shared
  `gameSurface` coordinate space. The rack hides the source tile and emits
  begin/change/end points; the table draws one floating canonical tile under
  the pointer. A 150ms tap suppression prevents the click gesture from firing
  after a short drag.
- **Drop:** `ChainAndZonesView` reports the live, transformed frames of its
  legal end targets through a preference key. `HandDropResolver` maps the
  release point to the matching legal move; releasing outside an end leaves
  the tile selected so tap-to-place still works. The empty-table opening
  accepts any legal opening move for the dragged tile.
- **Hit areas:** end targets grew from a 44pt circle to a **96pt invisible
  square**, and the resolver adds **32pt of padding** around each one. That
  makes the effective drop zone roughly 160pt across -- dropping on the end
  domino itself counts. Overlapping zones resolve to the nearest end instead
  of failing or picking arbitrarily.
- **Smoothness:** pointer updates live in a small `@Observable HandDragModel`
  read only by `HandDragPreview`, so a mouse move does not re-evaluate the
  board layout or the whole game screen. No implicit animation is applied to
  the drag position; it tracks the pointer directly.
- **Board pan:** the camera release now receives the actual gesture endpoint,
  so inertia has a velocity sample instead of always stopping dead.
- **Tests:** `HandDropResolverTests` covers matching-end, generous padding,
  nearest-of-overlapping-ends, outside, wrong-side, mismatched-tile, and
  empty-chain drops.
- **Files:** `HandRackView.swift`, `InteractiveGameBoardView.swift`,
  `ChainAndZonesView.swift`, `EngineTypes.swift`, `HandDropResolver.swift`,
  `HandDropResolverTests.swift`, `docs/design/UI_CHARTER.md`.
- **Verification:** `swift build` succeeds; `swift test` passes **68 tests,
  1 skipped, 0 failures**; `git diff --check` clean. No commit or push.
- **Graph:** refreshed to **2,191 nodes / 4,098 edges**;
  `scripts/build-graph-3d.py --check` passes.
- **Limitation:** the drag motion and drop targets were not physically
  exercised in the running window; the owner's mouse test remains the source
  of truth for pickup offset, tracking, and drop feel.

## UI-BONEYARD-01 — real 1v1 draw pile, rules-aware locked tail, animated draws (2026-11-12)
- **Problem:** the table had a Draw button and a generic face-down flight, but
  no physical draw pile. Draws appeared from the action-dock lane, and the
  Swift snapshot did not parse the bridge's locked-tail fields, so the rules'
  permanent pair had no visual expression at all.
- **Rules:** the boneyard exists only in 1v1. The deal leaves 14 undrawn tiles;
  the engine's `drawableCount` deliberately excludes the final two, which can
  never be drawn. The bridge exposes their identities only once at most two
  remain. Three-Way and Partners deal the complete set, so they show no pile.
  None of those rules were moved into Swift or inferred by the UI.
- **Data:** `GameSnapshot` now parses `boneyardLockedTiles`/`boneyardLockedCount`
  alongside the existing drawable count. The test construction seam gained a
  defaulted locked-tile argument, so existing controlled snapshots stay valid.
- **Pile:** `BoneyardView` is a quiet table object at the board's top-left:
  a four-layer face-down stack, the exact drawable count, and a visually
  separate two-tile locked tail. The tail stays face down while its identities
  are hidden; when the bridge reveals it, the actual dominoes flip face up and
  the small `LOCKED` label turns brass. The pile is absent outside 1v1.
- **Draw motion:** the pile reports its live center through a preference key;
  every human and computer draw flight now starts there. Flights use a lifted
  arc, a longer eased curve, a subtle rotation, growth into the hand (or
  shrink into the computer's seat), and a soft landing fade. The pile gives a
  small compression pulse as each tile leaves.
- **Every draw:** `GameViewModel` keeps a short window of active draw events
  (while retaining the existing latest `drawEvent` API). Back-to-back forced
  draws therefore animate independently instead of replacing one another. The
  computer loop refreshes the human-facing snapshot after each forced draw
  before publishing its face-down flight, so the shared pile count shrinks on
  the same beat without exposing the computer's hand.
- **Draw control:** unchanged. The existing contextual Draw/Pass button stays
  in `actionDock`; the pile is purely an additional table object. Draw remains
  enabled only when `canVoluntaryDraw`, and Pass only replaces it when the
  engine says the turn is blocked and the drawable yard is dry.
- **Files:** `BoneyardView.swift`, `DrawFlightView.swift`,
  `InteractiveGameBoardView.swift`, `GameViewModel.swift`, `EngineTypes.swift`,
  `BoneyardRulesTests.swift`, `RoundRevealTests.swift`,
  `docs/design/UI_CHARTER.md`.
- **Tests:** `BoneyardRulesTests` proves the mode split through real deals
  (1v1: 12 drawable + hidden locked pair; 1v1v1/2v2: no boneyard at all).
  `RoundRevealTests` additionally asserts the opening 1v1 count and that
  locked identities stay hidden while drawable tiles remain.
- **Verification:** `swift build` succeeds; `swift test` passes **69 tests,
  1 skipped, 0 failures**; `./scripts/ci/test_bridge.sh` passes **73 checks, 0
  failed**; `git diff --check` clean. Graph refresh: **2,209 nodes / 4,142
  edges**; `python3 scripts/build-graph-3d.py --check` passes. The app bundle
  was rebuilt and relaunched through `run.sh`. No commit or push.
- **Limitation:** the pile's final screen position, the takeoff/landing feel,
  and the locked-pair flip were compiled and covered by rules tests, but not
  visually reviewed with a physical mouse. The owner's run remains the source
  of truth for spacing and feel.

## UI-DOUBLE-01 — tight perpendicular doubles + equivalent-end double-click route (2026-11-12)
- **Problem:** a vertical double is only 38pt wide, but `SnakeChainLayout`
  advanced the chain center by the full 80pt horizontal cell after every
  tile. Flat tiles therefore sat 4pt apart, while doubles had ~23pt of dead
  air on both sides. Separately, double-clicking a tile that fit two equal
  open ends did nothing useful: the two-click path only auto-played when
  exactly one side was legal.
- **Layout:** the chain now advances by the actual visual half-width of the
  current tile plus the next tile plus `hGap`. A flat-to-double and
  double-to-flat transition therefore keeps the normal 4pt gap instead of a
  half-cell void. Corner detection and the serpentine row structure are
  unchanged. Head/tail marker insets also use the end tile's real width.
  This preserves the perpendicular-double rule; it only removes the unused
  space around the narrow orientation.
- **Double-click:** `HandRackView` now recognizes a second click inside
  `NSEvent.doubleClickInterval`. It delegates to the pure `HandTapRouter`.
  One legal side plays immediately. Two legal sides are resolved only when
  both open chain ends show the same number; then either side is engine-
  equivalent and a side is chosen at random. Two different open ends return
  nil, so the player still makes the strategic choice.
- **Discoverability:** after selecting an eligible tile, the status chip says
  `Both ends show N — double-click to place`; the tile's accessibility hint
  names the same gesture. Drag, tap-to-select, tap-the-end, and the existing
  tap-tap single-move path remain intact.
- **Files:** `ChainAndZonesView.swift`, `HandRackView.swift`,
  `HandTapRouter.swift`, `InteractiveGameBoardView.swift`,
  `BoardLayoutTests.swift`, `HandTapRouterTests.swift`,
  `docs/design/UI_CHARTER.md`.
- **Tests:** `BoardLayoutTests` now pins the 4pt gap on both sides of a
  vertical double. `HandTapRouterTests` covers one-side, both-equal-ends
  (random selection always one of the legal sides), different-ends refusal,
  no-move, and other-tile cases.
- **Verification:** `swift build` succeeds; `swift test` passes **75 tests,
  1 skipped, 0 failures**; `./scripts/ci/test_bridge.sh` passes **73 checks, 0
  failed**; `git diff --check` clean. Graph refresh: **2,227 nodes / 4,179
  edges**; `python3 scripts/build-graph-3d.py --check` passes. The app bundle
  was rebuilt and relaunched.
- **Limitation:** the actual double-click timing and the visual board gap were
  not exercised in the running window. The owner's physical mouse test remains
  the source of truth for gesture feel and spacing.

## UI-BONEYARD-02 — physical face-down row, open draw end, sealed pair (2026-11-12)
- **Problem:** the first boneyard build rendered a decorative four-layer mini-
  stack plus a detached locked tail. That did not match the table rules: the
  boneyard is a single straight row of face-down tiles, draws remove from one
  open side, and the final two at the opposite side are closed off. The old
  view also turned the reserved pair face up late in the round, which broke
  the "all face down" physical contract.
- **Layout:** `BoneyardView` now draws every remaining tile in one straight
  horizontal row: the two closed tiles sit at the fixed left end behind a thin
  rail, and the open draw end is the right edge. The row is 14 tiles at the
  opening deal (12 drawable + 2 closed), shrinks from the right as tiles are
  drawn, and ends as the same two face-down closed tiles. The closed pair never
  moves; the draw rail stays at the live open edge. End labels read `CLOSED`
  and `DRAW N`; the `DRAW` label is omitted once the yard is exhausted.
- **Data boundary:** the row is driven only by `boneyardDrawableCount` plus the
  rules-constant two closed tiles. It deliberately does not consume
  `boneyardLockedTiles` for display: the bridge may expose those identities
  for strategy once the pair is reached, but physical table tiles stay face
  down. The snapshot field and its tests remain intact.
- **Draw motion:** the flight anchor now comes from the actual open end of the
  row, not a stack center. Draws still use the existing lifted face-down flight
  into the hand or the computer seat.
- **Files:** `BoneyardView.swift`, `DrawFlightView.swift`,
  `InteractiveGameBoardView.swift`, `docs/design/UI_CHARTER.md`.
- **Verification:** offscreen `ImageRenderer` inspection of the real view at
  12, 4, and 0 drawable tiles confirmed the full 14-tile opening row, correct
  shrink direction, and the clean two-tile closed state. The temporary render
  harness was removed afterward. `swift test` passes **75 tests, 1 skipped, 0
  failures**; bridge regression passes **73 checks, 0 failed**; graph refresh:
  **2,227 nodes / 4,175 edges**, and `git diff --check` is clean; the app was
  rebuilt and relaunched.
- **Limitation:** the in-game top-left placement and live draw feel were not
  viewed in the running window; the owner's physical run remains the source of
  truth.

## UI-OPPONENT-HANDS-01 — face-down opponent hand rows (2026-11-12)
- **Problem:** the player strip exposed an opponent only as a numeric count
  badge. The player could not see the opponent's physical hand, and a draw that
  changed six tiles into seven had no visual analogue at the rival's seat.
- **View:** a new `OpponentHandRack` renders one identical face-down back per
  hand tile (28×14pt) in a compact horizontal row. It receives only an `Int`
  count, never tile data, so there is no identity information in the view to
  leak. Insertions and removals animate quietly in place.
- **Placement:** the hand rows live in a centered strip immediately below the
  avatar row, not inside the avatar cells. The 1v1 seats therefore stay
  symmetric as the opponent's hand grows, and the strip remains compact at the
  900pt minimum window. Every non-requesting seat is shown: Rival in 1v1,
  Rival A/B in Three-Way, and Rival A/Partner/Rival B in Partners.
- **Count source:** `SeatItem.handCount` already comes from `ownHand.count` for
  the requesting seat and `otherHandSizes[seat]` for every other seat. The new
  view adds no state inference; a forced AI draw refreshes the human snapshot
  before its flight is published, so 6→7 backs appears on the same beat as the
  draw. A play removes a back.
- **Boundary:** no tile identities or pips are rendered. The end-of-round
  reveal remains the only place hidden faces become visible.
- **Files:** `OpponentHandRack.swift`, `InteractiveGameBoardView.swift`,
  `docs/design/UI_CHARTER.md`.
- **Verification:** an offscreen `ImageRenderer` inspection of the real rack at
  7, 8, 9, and 14 tiles confirmed legibility and width; the temporary harness was
  removed afterward. `swift test` passes **75 tests, 1 skipped, 0 failures**;
  bridge regression passes **73 checks, 0 failed**; graph refresh:
  **2,232 nodes / 4,182 edges**; `git diff --check` is clean; the app was
  rebuilt and relaunched.
- **Limitation:** the live strip's exact vertical placement was not viewed in
  the running window; the owner's physical run remains the source of truth.

## UI-BONEYARD-03 — vertical column, direction fixed only by first draw (2026-11-12)
- **Problem:** the boneyard was a wide horizontal strip across the top of the
  board, and it labelled one end `CLOSED` at the opening deal before any draw
  had fixed a direction. That both dominated the table and asserted a side
  closure the rules do not have yet.
- **Layout:** the pile is now a narrow vertical column descending from the
  board's top-left. At the opening deal it is fourteen equal face-down backs
  with no `CLOSED` marker. The bottom edge is the draw edge. After the first
  draw (`drawableCount < 12`), the two reserved tiles at the top gain an
  upward cap, a `CLOSED` label, and a small separation from the drawable
  remainder. The column then shrinks from the bottom as draws remove tiles,
  leaving the closed pair fixed at the top.
- **Rules boundary:** no engine change. The opening deal still reserves two
  tiles in canonical draw order; the UI simply withholds the closed-side
  presentation until a draw has fixed it. The pair stays face down.
- **Motion:** the bottom tile leaves downward on a draw; the first-draw cap and
  gap animate in quietly. The flight anchor now comes from the bottom edge of
  the column rather than a stack center.
- **Files:** `BoneyardView.swift`, `docs/design/UI_CHARTER.md`.
- **Verification:** offscreen `ImageRenderer` inspection of the real view at
  opening 12, post-first-draw 11, late 4, and closed-pair 0 confirmed no
  opening `CLOSED` marker and an upward closed cap only after the first draw.
  The temporary harness was removed afterward. `swift test` passes **75 tests,
  1 skipped, 0 failures**; bridge regression passes **73 checks, 0 failed**;
  graph and `git diff --check` are clean; the app was rebuilt and relaunched.
- **Limitation:** the live board placement was not viewed in the running
  window; the owner's physical run remains the source of truth.

## UI-BONEYARD-04 — upright closed cap, readable scale, direct draw (2026-11-12)
- **Problem:** the vertical column was right, but the closed pair still lay on
  its side, the pile was too small to read comfortably, and the pile itself
  was deliberately inert (`allowsHitTesting(false)`) while only the distant
  action-dock button could draw. A draw also lacked visible feedback at the
  pile.
- **Closed presentation:** at the opening deal the two reserved pieces still
  lie flat among the fourteen. After the first draw they turn portrait and sit
  side by side as a two-piece cap under the upward rail and `CLOSED` label;
  the drawable column continues beneath them. The pair remains face down.
- **Scale:** pile pieces now scale with the live board height between 14pt and
  20pt half-axis, with larger labels and a heavier brass edge. A large table
  gets the full 20pt pieces; a compact table compresses before clipping.
- **Direct draw:** the whole pile is a Button wired to the same tested
  `GameViewModel.voluntaryDraw()` path as the action-dock Draw control. It is
  disabled whenever a voluntary draw is not legal. The Draw/Pass control is
  unchanged and never replaced.
- **Motion:** the Button has an immediate press response; drawable pieces
  leave from the bottom with an offset/fade and the column settles on a
  spring; the closed pair animates from flat stack to upright cap, with the
  rail and label fading in; the numeric `DRAW N` count transitions; the draw
  flight now starts from a 24pt face-down piece over 0.68s. No state or engine
  timing is changed by presentation.
- **Files:** `BoneyardView.swift`, `InteractiveGameBoardView.swift`,
  `DrawFlightView.swift`, `docs/design/UI_CHARTER.md`.
- **Verification:** offscreen `ImageRenderer` inspection at opening 12,
  post-first-draw 11, late 4, and closed-pair 0 confirmed the larger pile, no
  opening `CLOSED` marker, upright side-by-side closed pieces after the first
  draw, and the bottom draw edge. The temporary harness was removed afterward.
  `swift test` passes **75 tests, 1 skipped, 0 failures**; bridge regression
  passes **73 checks, 0 failed**; graph and `git diff --check` are clean; the
  app was rebuilt and relaunched.
- **Limitation:** macOS denied screen-capture and UI-automation access to this
  session, so the live mouse click was not driven end-to-end. The pile is now
  a real Button calling the same `voluntaryDraw` path already covered by
  `GameViewModelTests`; the owner's physical run remains the source of truth.

## UI-BRAND-01 — Isolyn app icon (2026-11-12)
- **Problem:** the app bundle had no `CFBundleIconFile` and no Resources
  directory, so Dock/Finder showed a generic application icon despite the
  table having a complete visual identity.
- **Mark:** one upright warm-ivory domino on a warm-black rounded-square
  field. The upper half has three canonical black pips; the lower half has
  one pip framed by the boneyard's brass diamond. A brass divider, faint
  ivory rim, top-light gradient, and soft table shadow carry the same
  ebony/ivory/brass material language as the game. The mark is intentionally
  half-open/half-hidden rather than a generic domino sticker.
- **Assets:** `Assets/Isolyn-1024.png` is the 1024 square source render;
  `Assets/Isolyn.icns` contains the complete macOS ladder (16 through
  1024 @2x). The source artwork uses an 824pt rounded square centered on a
  1024 transparent canvas, matching the standard macOS icon grid.
- **Bundle:** `run.sh` creates `Contents/Resources` and copies
  `Assets/Isolyn.icns`; both the generated and source `Info.plist` carry
  `CFBundleIconFile = Isolyn`. The icon is copied before ad-hoc signing.
- **Verification:** `iconutil` round-tripped the `.icns` to all ten expected
  representations with a 1024 @2x image; the final source at 1024/768 and the
  128px icon were inspected. The bundle `Info.plist` and Resources copy
  match, the copied `.icns` is byte-identical to the asset, and the rebuilt
  bundle was cleaned and ad-hoc signed by `run.sh` before launch; a strict
  verification immediately after signing passed. `swift test` remains 75
  tests, 1 skipped, 0 failures. The app was rebuilt and relaunched.
- **Limitation:** macOS screen-capture access is denied to this session, and
  Quick Look thumbnail generation hung, so the live Dock tile was not
  visually captured here. The Desktop is also file-provider-managed, so
  macOS reattaches FinderInfo/provenance xattrs after launch and a later
  strict `codesign --verify` can complain about detritus; the app itself
  launches normally and the icon resource is byte-identical. The in-app
  entry wordmark remains typographic.
- **Files:** `Assets/Isolyn-1024.png`, `Assets/Isolyn.icns`, `run.sh`,
  `Sources/IsolynApp/Resources/Info.plist`, `docs/design/UI_CHARTER.md`.

## OPS-11 — Closeout Initiative (2026-11-13: documentation audit, tree reorganisation, gate execution)

**Scope:** all 29 markdown documents, the `docs/` hierarchy, and the documentation
gate that OPS-10 recorded as missing and therefore **SKIPPED**.

- **Documentation audit:** every one of the 29 files read and judged on
  What/Why/How/Where/Validity. Verdict register (25 rows, A1–A29) and
  contradiction register (C1–C25) at
  `docs/audits/2026-11-13-documentation-audit.md`.
- **Reorganisation:** `docs/` grouped into `architecture/`, `engineering/`,
  `design/`, `subsystems/`, `roadmaps/`, `audits/`, `history/`. 20 tracked files
  moved with `git mv` (history preserved); root now holds exactly one markdown
  file. Renames: `UI_UX_OVERHAUL.md` → `design/UI_CHARTER.md`;
  `ui-fix-directive.md` → `history/2026-08-ui-rebuild-mandate.md`; the two
  completed roadmaps → `history/roadmaps/`. Deleted `tree.md`: stale by
  construction, regenerable in seconds, and rule 8 now points at the register in
  `docs/README.md` instead.
- **False claims retracted:** `docs/subsystems/LAB.md`'s ladder table did not
  reproduce from its own committed CSVs. Recomputed values: 3/16 vs 4/24 =
  202–198 (**+3.5**, shallower wins), 4/24 vs 5/40 = 205–195 (**+8.7**, shallower
  wins); the "directionally monotonic" conclusion is withdrawn. `lab/README.md`
  no longer calls the implemented Elo report a scaffold.
- **Counts corrected by re-measurement:** engine 426→**429**; Swift 68→**75**;
  ASan 494→**502**; accelerator 95→**100**; `ci.yml` 380/68→**429/73**; engine LOC
  3,766→**3,842**; app 47/5,869→**56/7,424**; tests 29/4,056→**35/4,597**;
  accelerator 1,640→**1,702**; total 160/20,284→**175/22,546**.
- **Documentation gate now EXISTS and RUNS:** `scripts/docs_audit.py`. It checks
  markdown link resolution, backticked `docs/` paths, status headers on living
  documents, register coverage, provenance banners on history, and the absence of
  superseded figures. **RESULT: PASS** (24 documents, 6 checks, exit 0). This
  replaces the permanent SKIP recorded in OPS-10.
- **Verification sweep (2026-11-13, macOS arm64, Apple silicon):**
  - `swift build` → `Build complete!`, exit 0
  - `./scripts/ci/test_engine.sh` → 19 executables, **429 checks passed, 0 failed**
  - `./scripts/ci/test_bridge.sh` → 2 executables, **73 checks passed, 0 failed**
  - `swift test` → **75 tests, 1 skipped, 0 failures** (the skip is the known
    vacuous forced-draw test at `GameViewModelTests.swift:81`, unchanged and
    tracked in audit §13.3 — not counted as a pass)
  - `python3 scripts/docs_audit.py` → **PASS**
- **Not done, deliberately:** no commit, no tag, no push. All three are separate
  owner gates, per the standing rule in this log. `graphify-out/` was not
  regenerated — it still records the pre-reorganisation tree. Code comments
  C24/C25 (`IsolynBridge.hpp`, `EngineSession.swift`) still contradict the
  documents and are left for an engineering pass.

## OPS-12 — Closeout Initiative (2026-11-14: Overdrive closeout, graph refresh, push)

**Scope:** close out the Project Overdrive round (E-020 – E-026), refresh the
structural graph, and commit/push the whole tree.

- **Verification sweep (macOS arm64, Apple silicon, 2026-11-14):**
  - `./scripts/ci/test_engine.sh` → 19 executables, **432 checks passed, 0 failed**
    (was 429; +3 are the new voluntary-draw contract checks in
    `SearchEngineTests.cpp`).
  - `./scripts/ci/test_bridge.sh` → 2 executables, **73 checks passed, 0 failed**
  - `swift build` → `Build complete!`; `swift test` → **75 tests, 1 skipped,
    0 failures** (same known vacuous skip, not counted as a pass)
  - `python3 scripts/docs_audit.py` → **PASS**
- **Strength state recorded this round:** parallel root search **+17.6 Elo**
  (1v1); partnership weight **+15.8 Elo** (2v2, pooled n=15,000); depth ladder
  5-vs-4 **+16.9**, 8-vs-5 **+20.9**; voluntary draws **+2.5 at depth 4, +9.4 at
  depth 5, +44.3 at depth 8** (pooled n=1,207, two seeds). Full detail in
  `docs/research/EXPERIMENT_REGISTRY.md`; nothing here is a shipped default
  change.
- **Graph refreshed (was stale from before the restructure):**
  `graphify update . --force` → **2,381 nodes, 4,418 edges, 161 communities**;
  `graph.json`, `graph.html` (the 3D view) and `GRAPH_REPORT.md` rebuilt. The
  prior curated graph was auto-backed up to `graphify-out/2026-11-13/`.
- **CI is RED and it is not the change.** Both jobs fail in under 50 seconds with
  zero steps executed and no retrievable logs (`log not found`) on two
  consecutive docs-only SHAs, while the three preceding SHAs were green and no
  workflow file changed between them. Re-running reproduced the identical
  instant failure. Recorded as runner infrastructure, NOT as a verified pass.
- **Not done, deliberately:** the `SearchDecision::isDraw` bridge/app wiring —
  the measured +44 Elo is unreachable until a draw is executable end-to-end, and
  that is a cross-language ABI change that deserves its own pass. No tag cut.

## OPS-12a — Correction to OPS-12 (same session, 2026-11-14)

OPS-12 described `graphify-out/graph.html` as "the 3D view" and reported the 3D
page as rebuilt. **Both statements were wrong**, and are corrected here rather
than edited in place (this log is append-only).

- `graph.html` is the **2D community export** from `graphify update`. The 3D
  builder's own docstring says so, and records that the aggregated community view
  was retired on 2026-10-29.
- The 3D page is `graphify-out/graph-3d-full.html`, produced by
  `python3 scripts/build-graph-3d.py`. `graphify update` does **not** rebuild it,
  and at the time of OPS-12 it was **stale**.
- **Detected by** `python3 scripts/build-graph-3d.py --check` → printed
  `STALE /…/graph-3d-full.html`, which is exactly the check the new `AGENTS.md`
  §6 procedure mandates.
- **Corrected state:** rebuilt → `ok`; **2,381 nodes / 4,418 links, 2.87 MiB**
  (3,014,638 bytes), matching `graph.json`. The file is gitignored
  (`.gitignore:17`), so it is a local artifact and correctly does not appear in
  any commit; the `--check` output is the receipt.

**Lesson recorded:** "refresh the graphs" is two artifacts, not one. A single
`graphify update` refreshes 2D only, and saying otherwise is a false claim even
when the count quoted alongside it is true.

## OPS-12b — CI root cause identified: account billing, not code (2026-11-14)

Required by `AGENTS.md` §9 after three consecutive red runs. The earlier entries
correctly refused to call CI green but only *suspected* infrastructure; this entry
replaces the suspicion with the platform's own statement.

- **Literal annotation from GitHub** on job `Documentation gate` (check-run
  `132327917473`), reproduced verbatim:
  > "The job was not started because recent account payments have failed or your
  > spending limit needs to be increased. Please check the 'Billing & plans'
  > section in your settings"
- **Job evidence:** `runner_id: 0`, `runner_name: ""`, `started_at` and
  `completed_at` 2 seconds apart, `steps: 0`. Nothing in the repository executed.
- **Contributing fact:** `repos/Johan21era/isolyn` reports `private: true`, so
  hosted runner minutes are billed to the account.
- **Conclusion:** there is no defect in this tree. Every job is rejected before a
  runner is assigned, which is why the logs are unavailable and why re-running
  produced the identical result. The same suites pass locally (432 engine / 73
  bridge / 75 Swift / docs PASS).
- **Owner action required (cannot be fixed from the repository):** GitHub →
  Settings → Billing & plans → resolve the failed payment and/or raise the
  spending limit. Until then CI cannot execute for this repository at all.
- **Not done, deliberately:** the workflow was not disabled, weakened or made
  conditional to manufacture a green check. A red run caused by billing is honest
  evidence; a disabled workflow would be a false one.

## OPS-13 — Chain layout is a path, not a row grid (2026-11-13)

**Trigger.** Owner live testing, with two photographs of a real game: "one of the
core aspects of dominoes ... it just mutates whatever shape u want to ... we
currently dont have this". The chain was a fixed serpentine of equal rows and
could not turn where the game turned.

**What changed** (`SnakeChainLayout`, `Sources/IsolynApp/Game/Board/ChainAndZonesView.swift`).
- `compute` is now a layout of RUNS. Tiles advance along a run; when the run
  reaches the table edge the tile at the end lies ACROSS the run as the corner,
  and the next run starts beneath it heading back the other way. Rows are one
  short axis plus one gap apart (42pt), so runs sit tight like a real chain.
- Doubles lie across the run, in the run or at a corner, and are pitched by the
  short axis (42pt) rather than the long one. This was the actual cause of the
  original "stiff" look: a double was being advanced by its long axis.
- A crosswise double stands half a tile proud of its run, so the neighbouring run
  is nudged down locally (`short / 2` at a time) instead of being moved wholesale.
  That local bow is the raggedness a real chain has around its doubles.
- A final de-overlap pass makes "no tile on top of another" structural: a tile
  that would land on an occupied spot drops to the next free row. On any table
  large enough for the chain this pass never fires.
- The finished chain is translated to the table centre when it fits; an oversized
  chain keeps its coordinates and relies on the existing uniform auto-fit + pan.

**Verification.**
- `swift test`: **81 tests, 0 failures**.
- New `Tests/IsolynAppTests/SnakeChainLayoutTests.swift` (5 tests) asserts, for
  1–40 tiles at 900×620 and 1–28 at 420×320: no two tiles overlap, consecutive
  tiles are adjacent within one gap (plus half a tile when a crosswise double is
  involved), appending tiles does not re-flow placed ones, output is
  deterministic, and every coordinate is finite.
- The SVG render of a 23-tile chain was inspected directly: one long run, a
  corner tile across it, a return run below, doubles crosswise.

**Bugs found and fixed during the work** (all caught by the new tests, none
shipped): advancing a vertical tile by its short axis (tiles stacked exactly on
each other); starting the run outside its own reserved band (first tile forced
to turn); and a run reaching the edge with no room left for its corner (chain
marched off the table).

## OPS-14 — Analyze could never recommend a draw; it now can, and the engine draws freely (2026-11-14)

**Trigger.** Owner live testing: "the 'analyze' button almost NEVER seems to
recommend drawing, ever ... either that, or we have to open and see the 'elite'
engine play against the master one ... if it truly never draws on its own, then
theres a real possibility that its entire elo is fake".

**Root cause — three independent defects, all in the product path, none in search.**
1. `bridge_analysis_run` built `SearchEngine::Config config;` and set only
   `maxDepthPlies` / `determinizationCount`. `maxVoluntaryDraws` therefore stayed
   at its default **0**, and the draw branch is gated on it
   (`SearchEngine.cpp`: `context.maxVoluntaryDraws > 0 && drawsLeft > 0 && ...`).
   Analysis was *structurally incapable* of considering a draw at any depth.
2. `AnalysisResultDTO` had no `isDraw` field and the bridge assigned
   `r.recommendedMove = fromEngineMove(decision.move)` unconditionally, so even a
   perfect draw decision could only surface as an unrelated placement.
3. **Search-engine bug found while wiring it:** when the best action was the
   draw, `candidates[bestIndex]` indexed *past the end* of the placement vector,
   because `drawIndex == candidates.size()`. The decision therefore carried a
   garbage "placeholder" move (out-of-bounds read) that the new DTO would have
   forwarded to the app. `tests` had only checked `boneyard().drawableCount() > 0`
   for draw decisions, never the placeholder's legality.

**Fix.**
- `SearchEngine.cpp`: `chosenMove = bestIsDraw ? candidates[0] : candidates[bestIndex]`
  -- a draw now reports a genuinely legal placeholder, as the DTO contract requires.
- `IsolynBridge.hpp/.cpp`: `AnalysisResultDTO::isDraw` added; analysis runs with
  `maxVoluntaryDraws = 1`; `failedAnalysis` reports `isDraw = false`.
- `EngineTypes.swift`: `AnalysisOutcome.isDraw`; `GameViewModel` plays
  `voluntaryDraw()` instead of submitting the placeholder, publishes the hidden
  draw, and refreshes; `InteractiveGameBoardView` shows "Engine suggests drawing
  a tile".
- Tests added: engine assertion that a draw decision's placeholder is legal
  (the check whose absence hid the OOB read), bridge assertion that the reported
  tile is real.

**Evidence that the Elo was never fake.** Self-play, draws enabled, CSV rows with
`side == -1` counted:
- depth 4 / 20 samples (the Analyze configuration), 10 games:
  **23 draws in 200 decisions = 11.5%** (`lab/data/draws-d4.csv`, seed 11).
- depth 8 / 64 samples (shipped elite), 3 games:
  **14 draws in 62 decisions = 22.6%** (`lab/data/draws-d8.csv`, seed 21).
Draw frequency *rises* with depth, which is what E-026's +44.3 Elo at depth 8
predicts. The engine always could draw; the UI simply never asked it to.

**Verification.** `TOTAL CHECKS PASSED: 433` (engine, +1), `TOTAL CHECKS PASSED: 74`
(bridge, +1), `swift test` 81 tests / 0 failures, `swift build` complete.

**Not done, deliberately.** Analyze still runs depth 4 / 20 samples rather than
the elite 8 / 64; that is a latency choice, not a draw bug, and is now visible
as such. The engine's own `Config` default for `maxVoluntaryDraws` remains 0.

## OPS-15 — The chain only turns at the edge of the TABLE, not the window (2026-11-14)

**Trigger.** Owner live test after OPS-13, with a screenshot of a real game: the
chain was still one straight row 1400pt wide. "this is still garbage. what
happened to ur ui updates and or fixes".

**What was NOT wrong.** The running bundle was current: `build/IsolynV2.0.app`
was stamped 00:13, after the layout rewrite at 23:51, and the screenshot shows
doubles lying crosswise (vertical) exactly as the rewrite intends. The change was
deployed and simply had no visible effect.

**Root cause.** Runs continued until the *window* edge. On the owner's ~1600pt
window an 18-tile chain (18 x 80 = 1440pt) fits in a single run, so the chain
never turned -- identical to the old behaviour. My verification canvases were
900x620, where the same chain must wrap, so every test and the rendered SVG
passed while the real desktop case was untested. This is the actual process
failure: the test size was chosen where the behaviour was already correct.

**Fix.** `SnakeChainLayout.maxRunWidth = 760` (~9 tiles) bounds the table, so a
run turns where a real table ends. Chains longer than nine tiles now coil on any
window size; shorter ones stay in one line, as they should.

**Tests changed.** New `test_wideDesktopWindow_stillCoilsTheChain` (1600x900,
18 tiles: at least two runs, at most ten tiles per run). The adjacency allowance
was corrected to one gap plus half a tile for every pair, because a run that
continues past a crosswise double is offset by that double's protrusion -- a
19pt step is physical, not a break.

**Verification.** `swift test` **82 tests, 0 failures**; `swift build` complete;
bundle re-copied and re-signed at 00:19. Rendered 18 tiles at 1600x900 and
inspected it: two runs joined by a corner, doubles crosswise.

**Lesson recorded.** A layout invariant tested only at a canvas size that forces
the interesting branch has not been tested. Width-dependent behaviour needs at
least one case at the size the product actually runs at.

## OPS-16 — Corner geometry: runs now reserve room for their own turn (2026-11-14)

**Trigger.** Owner live test after OPS-15: the chain coiled, but into a
staggered block with tiles dangling below both rows. "genuinely the highest
level of garbage ive ever seen".

**Root causes, both measured from the placement dump rather than guessed.**
1. Rows were `short + gap` (42pt) apart while a crosswise double stands half a
   tile proud on each side, so parallel runs could collide. The safety net then
   nudged individual tiles down 19pt, producing the stagger.
2. A run filled all the way to the table edge, leaving no room for its own
   corner. The corner was clamped back over the last tile, collided with it,
   and was pushed down 38pt -- dragging the following double down with it. That
   is the dangling tile in the screenshot.

**Fix.**
- `rowPitch = long + gap` (80pt): two runs each with doubles need a full tile
  plus a gap, so with this pitch no row can ever collide and the safety net
  never fires in normal play.
- The corner sits low in its band (`rowY + (rowPitch - long)/2 + short/2`), so
  its long face reaches the return run: the runs meet at the turn instead of
  leaving a hole.
- Each run reserves `short + gap` before the edge for that corner, so the
  corner is never clamped back onto the run it ends.

**Verification.** Placement dump of 20 tiles at 1600x900: row of nine at
y=399.5, corner at (1141, 420.5), return run ten tiles at y=479.5, doubles
in-line, no nudged tiles. `swift test`: **82 tests, 0 failures** (the turn test
now asserts the real geometry: 59pt across, 38pt along). Bundle re-signed.

**Tooling trap found.** My first two renders of this change were wrong images,
not wrong layouts: `qlmanage` stretches a 16:9 SVG to fill a square thumbnail
and crops the right-hand side, which faked an off-centre, clipped chain twice.
The preview canvas is now square, and coordinates are printed alongside the
image so a rendering artifact cannot be mistaken for a layout defect.

## OPS-17 — Stale suggestion showed an illegal move; last tile no longer turns (2026-11-14)

**Trigger.** Owner live test after OPS-16, with a screenshot: "i thought the 1-3
was playable but it wasnt", plus two tiles hanging below the right-hand run.

**The game-breaking bug (not the layout).** `refresh()` never cleared
`analysisOutcome`, and the status line renders it whenever analysis is not
running. After the board moved, the window still read "Engine suggests 6-2" --
a recommendation for a PREVIOUS position, naming a tile that was not legal. The
owner read it as a playable move and lost the turn. A stale hint is not a weaker
hint; it is a wrong one.
- Fix: `discardStaleAnalysis()` runs on every refresh and drops the outcome when
  `stateVersionAnalyzed` no longer matches the snapshot, or when the suggested
  move is not in the current `legalMoves`. The status line also re-checks
  legality before displaying a placement suggestion.

**The dangling tiles.** The chain's LAST tile was being turned into a corner: a
corner exists to start another run, so with nothing left to place it becomes a
stub sticking out of the end.
- Fix: the final tile always continues in line (`isLastTile`), so a chain ends
  as a run, not as a disconnected-looking turn.

**Build identity.** Three rounds were spent judging a window whose binary could
not be verified. The top bar now shows the build hash from the bundle's
`IsolynBuild` key, which `run.sh` writes from `git rev-parse --short HEAD` at
launch. This is a temporary diagnostic, not decoration, and is removed once the
layout is confirmed in live play.

**Verification.** Placement dump, 24 tiles at 1600x900: rows at y=370 / 450 /
530 (80 apart), corners at (1141, 391) and (478, 471), final double in line at
y=530, no nudged tiles. Rendered and inspected. `swift test`: **82 tests, 0
failures**. Bundle rebuilt and signed at 00:33, stamped `207c387-next`.

## OPS-18 — Live layout probe, table-width runs, and the opener-draw rules bug (2026-11-14)

**Trigger.** Owner live tests: the chain still read as a cramped block, and the
computer drew a tile while it was the opener, which the rules forbid. Live
observation is authority (AGENTS §0); three earlier attempts had guessed at
geometry from screenshots and each was wrong.

**Diagnosis, measured not inferred.** A DEBUG probe (`LayoutProbe`) writes the
real layout inputs and exposes them in the top bar. First live reading:
`available=1322x725 tiles=1 scale=1.000 content=38x76`. Next live reading from a
played position: `1536x640 n18 s1.90 r4`. So the algorithm was not mistiling:
it laid out correctly and refused to grow (`fitScale` was pinned at 1.0), then
coiled at a hardcoded `maxRunWidth = 760` on a 1536pt-wide table.

**Changes.**
- `fitScale` grows into slack up to `maxScale = 1.9`; tighter axis still governs,
  floor unchanged.
- Run bound is the board's width, capped at `maxRunTiles = 20`, replacing the
  760pt constant: 18 tiles now lay one line across the table instead of two rows.
- **Opener may not draw.** `MatchController::canVoluntaryDraw()` (with an assert
  in `voluntaryDraw`), `bridge_voluntary_draw`, both `SearchEngine` draw branches,
  the self-play harness, and `GameViewModel.canVoluntaryDraw` now require a
  non-empty chain. Previously the only gate was `boneyard.drawableCount() > 0`.
- Tests: opener-cannot-draw at controller and search level; wide-window test
  rewritten from "must coil at ~9 tiles" to "18 tiles is one run, 24 and 40 turn".

**Evidence (literal).** `./scripts/ci/test_engine.sh`: `TOTAL CHECKS FAILED: 0`,
19 executables. `./scripts/ci/test_bridge.sh`: `Runtime failures: none`.
`swift test`: `Executed 82 tests, with 0 failures (0 unexpected)`.
Commits `be81ef9`, `7b3b458`; bundle launched as `7b3b458` via `scripts/iso`.

**Retraction.** The +44.3 Elo draw figure (E-026) was measured with opener draws
permitted. That subset is now illegal, so the number no longer describes shipped
behaviour exactly; it is un-retested, not withdrawn.

**Not done.** The probe is still in the build (DEBUG only) until the owner
confirms the rendering; no rendering claim is made here.

## Round scoring: the double blank is worth ten; tighter tile spacing

**Symptom (owner).** Round ended with the owner holding the double blank; it was
counted as 0 instead of 10.

**Cause.** Two sums used `DominoTile::value()`, which is pips: the round-end
reveal in `SnapshotBuilder` (`finalHandValues`, what the summary shows) and
`bridge_record_round`'s `participantValues` (what `computeRoundScores` awards).
The double blank has no pips, so it contributed nothing at either step.

**Fix.** `DominoTile::pointValue()` -- pips, or 10 for the double blank -- is now
the scoring value, used by the reveal, the bridge's round scoring, and the
self-play harness. Swift `Tile.pointValue` mirrors it; `RoundRevealTests` and the
bridge reveal-sum check now sum point values rather than raw pips.

**Spacing.** `tileShortAxis` 38 -> 42 and `hGap` 10 -> 6 (row pitch 90): tiles
sat too far apart to read as one line on the table.

**Evidence (literal).** `./scripts/ci/test_engine.sh`: `TOTAL CHECKS FAILED: 0`,
including a new section asserting `DominoTile(0,0).pointValue() == 10` and that a
one-tile double-blank hand scores 10 to the winner. `./scripts/ci/test_bridge.sh`:
`Runtime failures: none`. `swift test`: `Executed 82 tests, with 0 failures`.

**Not done.** The new spacing has not been rendered or seen; no visual claim is
made. Leaf evaluation heuristics (`EvaluationEngine` pip sums) deliberately still
treat 0-0 as 0 pips -- that is a static evaluation weight, not the scoring rule,
and changing it would alter playing strength with no measurement.

## OPS-19 — The rulebook exists, and it is mechanically enforced

**Scope.** Create the missing rulebook and make it tier 0: the authoritative
statement of the game, against which the implementation is judged.

**Why it was missing.** The rules came from two external documents ("Rules Spec",
"Concept Spec") that were never committed. They survived only as twelve
ambiguity resolutions in `history/legacy-handoff.md` §5.3. The test suite had
therefore been written by reading the code, so every test agreed with the
implementation -- including the double-blank-worth-zero mistake fixed in the
preceding entry, which no test could have caught because no rule said otherwise.

**What was built.**

- `docs/rules/RULEBOOK.md` -- 28 numbered rules, each with a status, the code
  that enforces it, and the single assertion that fails if the rule breaks.
  Statuses: 24 `ENFORCED`, 1 `VARIANT` (voluntary draw), 1 `GAP`
  (mandatory play is not enforced by `MatchController::endTurnWithNoPlay`), and
  2 `OPEN` (the 1v1 One Domino Rule; all-doubles closes).
- `scripts/rules_audit.py` -- fails when a rule has no assertion anchor, when an
  anchor does not resolve to real text in a real test file, when named code does
  not exist, when an ID is duplicated or the numbering skips, and when a
  declared hole is absent from Known gaps. `--strict` fails if any gap remains.
- Wired into `.github/workflows/ci.yml` (before the docs gate), `AGENTS.md` §0
  and §2, and the `docs/README.md` authority table, where the rulebook now sits
  at tier 0 above running code.

**Evidence (literal).** `python3 scripts/rules_audit.py`:
`RESULT: PASS — every enforced rule names real code and a real assertion; 3 declared hole(s)`,
exit 0. The gate was then tested against four deliberately broken copies of the
rulebook, each rejected with exit 1: a non-existent assertion anchor
(`R-01: ... does not contain 'a test that does not exist'`), a hidden gap
(`R-10: GAP rule is not listed under Known gaps`), a duplicate ID
(`R-02: duplicate id`), and a missing code file
(`R-09: Sources/IsolynEngine/NoSuchFile.cpp does not exist`).
`python3 scripts/docs_audit.py`: `RESULT: PASS`.

**Not done, deliberately.** R-10 is declared, not fixed: refusing the pass needs
a bridge status the app can display rather than an `assert` that release builds
discard. R-26 and R-27 need an owner ruling before any code.

## OPS-20 — The rulebook becomes the owner's, and the engine is made to obey it

**Scope.** Replace the agent-written rulebook with the owner's dictated ruleset
(2026-11-14) and align the engine with it: scoring, hand values, and the 1v1v1
threshold.

**Provenance.** The owner dictated the rules from memory and then answered six
questions where the dictation contradicted itself. The answers are quoted in
`docs/rules/RULEBOOK.md` §0. 21 rules: 15 enforced, 6 declared gaps, 0 open.

**What changed in code (all from the dictation, not from inference).**

- `RulesEngine::computeRoundScores` — two participants (1v1, and 2v2 teams now
  score the same way) credit the **winner with the loser's total**; the loser
  adds nothing. Three participants keep the "0-12-41" form the owner gave.
  Previously the lowest hand scored 0 and every other hand added its own value,
  which paid the loser.
- `RulesEngine::handPoints` — a hand is its pips, except the double blank, which
  is worth ten **when it is the only tile left** and zero alongside any other
  tile. This reconciles the two statements that looked contradictory: the
  rulebook's tally (4-3, 0-0, 2-1 = 10) and the live report of a lone 0-0
  scoring nothing. `DominoTile::pointValue` is deleted so the wrong rule cannot
  be reintroduced at tile level.
- `kOneVsOneVsOneMatchLossThreshold` 101 -> 151 (R-06: only 1v1 may play to 101).
- `ClosingOpportunityHeuristic` sign flipped: `roundScores` now holds points
  **won**, not points charged, so the old negation would have rewarded losing.

**Evidence (literal).** `python3 scripts/rules_audit.py`:
`RESULT: PASS — every enforced rule names real code and a real assertion; 6 declared hole(s)`.
`./scripts/ci/local.sh`: `LOCAL CI: PASS — 6 step(s), 0 failed`, with
`TOTAL CHECKS PASSED: 449 TOTAL CHECKS FAILED: 0` (engine),
`TOTAL CHECKS PASSED: 74 TOTAL CHECKS FAILED: 0` (bridge),
`Executed 82 tests, with 0 failures` (Swift), `Build complete!`.
`./tools/selfplay/build.sh` exit 0.

**Behaviour change, and its limits.** The scoring inversion changes what the
engine's own search considers a good close, because
`ClosingOpportunityHeuristic` now maximises points won. That is a
strength-affecting change and it has **not been measured**; no Elo claim is made
in either direction. The previous heuristic was scoring a model the rulebook no
longer describes.

**Not done, deliberately.** R-06 (the 101 option), R-07 (sets and games), R-15
(unlimited draws), R-17 (the locked pair), R-18 (One Domino Rule) and R-21
(2v2 table talk) remain declared gaps; none was guessed at.

## OPS-21 — The rulebook reaches zero open questions

**Scope.** Close the last three owner-facing gaps in the dictated ruleset.

**Rulings recorded.**

- **R-22, new:** in 1v1v1 a player who reaches 151 is *out of the set*, not the
  set's loser. The two survivors play on inside the same set as a 1v1, carrying
  their existing points (151-86-98 leaves 86 and 98 playing on), and the first of
  those two to reach 151 loses the set. Last man standing wins it. This was not
  in the original dictation at all and changes what a 1v1v1 set is.
- **R-21, table talk:** the owner ruled that this stays between the players and
  the software does not model it. Status changed to a new `BY_HAND`: recorded
  because it is part of the game, deliberately not enforced in code, and not
  counted as a gap.
- **R-17, the private look:** the owner declined a "privacy mechanism" and asked
  simply to code it. The rule stands; the implementation obligation is now
  unblocked.

**Evidence (literal).** `python3 scripts/rules_audit.py`:
`RESULT: PASS — every enforced rule names real code and a real assertion; 6 declared hole(s)`,
22 rules: 15 enforced, 6 gaps, 0 open, 1 by hand. `python3 scripts/docs_audit.py`:
`RESULT: PASS`.

**Not done.** No behaviour changed in this entry; it is a rules-closure receipt.
The six remaining gaps are implementation work: sets and games (R-07), the
1v1v1 elimination (R-22, blocked behind sets), the locked pair (R-17), unlimited
draws (R-15), the One Domino Rule (R-18), and the 101 option (R-06).

## OPS-22 — The seal: rules hash, strength stamps, and the evaluation wired to R-19

**Scope.** Reset the strength baseline after the rulebook changed, audit the
engine for rulebook wiring, and make drift structurally impossible.

**Wiring audit found three faults, all the same defect in different places.**
`EvaluationEngine::handValueOf`, `EvaluationEngine::handFacts` and
`ExpectedValueHeuristic::score` each summed raw pips, so a hand holding only the
double blank was worth 0 to the AI while R-19 scores it 10. The engine's own
batch-parity tests caught it as a scalar-vs-batch delta of exactly 10.0. All
three now call `RulesEngine::handPoints`.

The 2v2 closing test encoded the old value: player 0's team holds a lone double
blank (10) plus 1-1 (2) = 12 against 7, so it is the *higher* team and now loses
the hand, keeping only the closer bonus. The assertion was updated to the
rulebook, not weakened.

**The seal.**

- `docs/rules/RULES_VERSION` records the SHA-256 of `RULEBOOK.md`
  (`9ce8aee81a8a…`). `scripts/rules_audit.py` recomputes it and fails on a
  mismatch: editing the rules without bumping the version is now a build error.
- Every document under `docs/research/` that mentions Elo must declare a
  `Rules version:`; if it is not the current hash it must carry a SUPERSEDED
  banner in its first 15 lines. A stale claim cannot sit in the living docs.
- `docs/research/STRENGTH_BASELINE.md` is the only home for a strength claim and
  is stamped with the current hash; it currently records **no claim**.
- `AGENTS.md` §11 now says no current strength claim exists, rather than quoting
  superseded figures.

**Old results.** Not deleted. `PROJECT_OVERDRIVE.md`, `EXPERIMENT_REGISTRY.md`
and `BENCHMARK_BASELINE.md` are each marked `SUPERSEDED 2026-11-14` with
`Rules version: PRE-RULEBOOK`. Deleting measured evidence would make the reset
unauditable; the banner makes it impossible to quote them as current.

**Evidence (literal).** Two deliberate tamper tests were rejected with exit 1:
`[version] rules changed: rulebook is 9ce8aee81a8a, RULES_VERSION records
000000000000` and `[strength-stamp] docs/research/ZZ_TEMP_CLAIM.md: cites a stale
rules version and is not marked SUPERSEDED`; restoring the files returned exit 0.
`./scripts/ci/local.sh`: `LOCAL CI: PASS — 6 step(s), 0 failed`, engine
`TOTAL CHECKS PASSED: 451 TOTAL CHECKS FAILED: 0`, bridge 74, Swift 82.

**Volume reality for the planned 5–10M game run.** Recorded rates on this machine
are ~53 s per 1,000 rounds at depth 4 and ~230 s per 1,000 at depth 8. Ten million
rounds is therefore on the order of six days at depth 4 and four weeks at depth 8,
not an overnight run. Tomorrow should start with a 1,000-round timing run, then
choose N from the measured rate and run in seeded chunks.

## OPS-23 — Old measurements stamped VOID, repeatedly and with reasons

**Scope.** The three pre-rulebook research documents are stamped VOID rather than
merely "superseded", at every point where a reader could encounter a number.

**How it is stamped.** In each of `PROJECT_OVERDRIVE.md`, `EXPERIMENT_REGISTRY.md`
and `BENCHMARK_BASELINE.md`:

- the title carries `(VOID)`;
- a `Status: VOID` line sits directly under the title;
- a banner headed "⛔ VOID — DO NOT CITE, DO NOT BUILD ON" gives the reasons;
- a marker line sits above **every** markdown table (13 in total: 2 + 6 + 5);
- a closing section restates that everything above it is void.

**The reasoning recorded in the banner, not left implicit.** These runs predate
RULES_VERSION 1 and measured a different game: scoring inverted so the winner is
credited with the loser's total (R-03/R-05), `ClosingOpportunityHeuristic` changed
sign with that inversion, a lone double blank became worth ten (R-19), 1v1v1 moved
to 151 and gained elimination (R-06/R-22), and draws were capped at one per turn
where the rulebook allows unlimited (R-15). The results are therefore **not
reproducible from the current tree**.

**Gate.** `scripts/rules_audit.py` treats `VOID` and `SUPERSEDED` as the only
acceptable marks on a document that quotes Elo with a stale rules hash; a stale
claim with neither fails the build.

**Evidence (literal).** `python3 scripts/rules_audit.py`:
`RESULT: PASS — every enforced rule names real code and a real assertion; 6 declared hole(s)`.
`python3 scripts/docs_audit.py`:
`RESULT: PASS — links, paths, status headers, register, banners and figures are consistent`.

**Correction made while doing this.** The first pass pushed each old `Status:`
line past the documentation gate's twelve-line window and tripped
`status-headers: FAIL (3)`; the VOID status line was moved directly under the
title and the stale "living" paragraphs removed, so the documents no longer
contradict their own banner.

## OPS-24 — Resumable sharded self-play runner and a single lab entry point

**Scope.** Make the offline lab reachable and make a multi-million-game run one
restartable command. No engine, rule or scoring code changed.

**What was added.**

- `scripts/lab` — the entry point the lab never had: `run`, `status`, `list`,
  `merge`, `evaluate`, `build`. It sets `PYTHONPATH` itself, so the lab no longer
  requires the owner to know where the package lives.
- `lab/src/isolyn_lab/runner.py` — plans shards, runs them with bounded
  parallelism, and records each shard as `done` only when the harness exited 0,
  its log reports zero incomplete rounds, **and** its CSV ends on a complete
  line. Everything else is replayed from that shard's seed.

**Two design decisions that are not cosmetic.**

- **Shards resume from a seed, not a byte offset.** The C++ harness has no
  mid-file resume, so a shard is the unit of loss; the default 5,000 games is
  about two minutes at depth 8.
- **Shard seeds advance by 1, not by the harness's golden-ratio stride.** The
  harness seeds game `j` with `seed + j * 0x9E3779B97F4A7C15`; advancing each
  shard's base by that constant would silently replay another shard's deals.

**Two failures found by testing it, and fixed.**

1. Ctrl-C recorded the in-flight shards as `failed` (`harness exit -15`). A shard
   we stopped is unfinished, not broken; it is now `pending`, and `status`
   reports 18 pending / 0 failed.
2. SIGKILL of the runner left the harness children alive in their own session,
   still writing the CSV the resumed run was about to truncate — two writers, one
   file. Shard pids are now recorded at launch and any surviving `selfplay`
   process is reaped on resume.

**Evidence (literal, from this machine).**

- `./scripts/lab run --games 400 --shards 8 --parallel 4 --depth 8
  --determinizations 64`: `8/8 shards | 400/400 games (100.0%) | 33.0 games/s`,
  `complete: 400 games`.
- Rerunning the identical command: `nothing to do: every shard is already complete`.
- Interrupt test at 900 games: exit `130`, status `18 total, 0 verified done,
  18 pending, 0 failed`.
- SIGKILL test at 900 games: `orphans alive after SIGKILL: 4`, then
  `reaping orphaned shard 0..3`, `complete: 900 games`, `orphans after resume: 0`,
  status `18 verified done, 0 pending, 0 failed`.
- SIGKILL test at 600 games with a stale lock file: resumed to `600/600`.
- Merged output audit: `merged: 900 unique games, ids 0..899, 15266 move rows`,
  `gaps: none`.

**Measured throughput (development M3, depth 8 / det 64).** Four parallel
single-worker shards sustain ~33 games/s; eight sustain ~43. Five million games
is therefore ~32 hours and ~9.5 GB of CSV at ~1.95 KB per game — a different
order of magnitude from the archived "weeks" estimate, which came from a
different configuration.

**Not done, deliberately.** No trainer, no weight export, no app UI for Training
or Sandbox. Those remain scaffolds; this change only makes the existing lab
runnable at volume.

## OPS-25 — The lab in the app, with the Start button made idempotent

**Scope.** Reach the offline lab from the app, and make repeated presses of a
run button harmless. No engine, rule or scoring behaviour changed.

**What the app can now do.** `Entry → Lab` (the old "Training" link, renamed to
what it actually is) opens a screen that starts a sharded run, shows live games,
shards, rate and ETA from the run manifest, stops it, resumes any unfinished run,
merges a finished one, and reveals the run folder. Presets are Smoke 200, 10K,
1M and 5M.

**Why a service and not just a button.** A SwiftUI button can be pressed again
before its disabled state renders, and key repeat bypasses intent entirely. All
launch decisions therefore live in `LabService`, which owns at most one child:

- a second Start while a run is active is refused with a message, never spawned;
- a repeat of the same configuration inside a two-second window is treated as
  noise (double-click, key repeat);
- the runner's own `run.lock` is the last line of defence when the app is
  bypassed entirely;
- the service is owned by the app, not the screen, so navigating away does not
  lose the ability to stop the run.

**Two details that would have bitten later.**

- **Repository discovery from inside the bundle.** The app runs from
  `build/IsolynV2.0.app`, so neither the working directory nor `Bundle.main`
  points at the source tree. `LabPaths` walks up from
  `Contents/MacOS` until `lab/src/isolyn_lab/runner.py` appears; a test builds a
  fake bundle tree and asserts the walk finds the root.
- **Reattaching to a run from a previous app session.** Quitting the app does not
  kill the runner — that is what makes a 32-hour run practical. On reopen the
  service reads the lock pid, verifies via `ps` that it really is a Python
  process, and shows the run as active with a working Stop.

**Stress evidence (literal).**

- `test_twoHundredStartPressesLaunchExactlyOneProcess`: 200 `start()` calls →
  exactly 1 launch.
- `test_aDifferentConfigurationWhileRunningIsRejected`: 50 different
  configurations while one is active → still 1 launch, message
  "One run at a time — stop the active run first."
- `test_stopTerminatesTheChildAndAllowsANewRun`: Stop sets `terminated` on the
  child and a new run is then allowed.
- `test_pressesDuringTheRepeatWindowAfterAStopDoNotRelaunch`: 50 presses after a
  Stop inside the window → no second process.
- `test_realRunnerCompletesASmokeRun`: the real `/bin/bash scripts/lab` child
  runs 5 games and the service reports `finished` with `doneGames == 5`.
- Two shell runners on one run id: the second prints
  `run is already active (pid 11289); use 'lab status' to watch it` and the first
  completes `4 verified done`.
- `swift test`: `Executed 91 tests, with 0 failures`.
- `./scripts/ci/local.sh`: `LOCAL CI: PASS — 6 step(s), 0 failed`.

**Not done, deliberately.** No trainer and no Sandbox screen. The Lab screen
drives the existing runner; it does not invent capabilities the lab does not
have.

## OPS-26 — The Lab screen renders without a click

**Scope.** Close the one gap left by OPS-25: the tests proved the service, not
that the screen itself renders.

**What was added.** `test_labScreenRendersWithoutAClick` renders `LabView` through
`ImageRenderer` at the default 1080×720 window size with a real `AppState` and a
fake-backed `LabService`, and asserts an image is produced. A missing environment
value or a broken body would crash the render rather than pass silently.

**Evidence (literal).** `swift test`:
`Executed 92 tests, with 0 failures (0 unexpected) in 2.798 (2.805) seconds`,
with `test_labScreenRendersWithoutAClick` reported as passed (0.147 seconds).

**Correction to OPS-25.** That entry records 91 tests; the render test makes the
current total 92. The earlier figure was true when written and is not edited here,
per the append-only rule.

**Still not done.** No click-through of the native screen: this machine has no
UI-automation harness attached to the app, so the render test is the strongest
check available without a human at the window.

## OPS-27 — Analyses in the app, and the opponent default they exposed

**Scope.** Make the lab technical but readable in the app, add multi-report
calibration analyses, and fix a real configuration trap the first analysis
report exposed. No engine rules changed.

### The finding

The first JSON report showed every CSV carrying `config B: depth=4,
determinizations=20` when the runner had been asked for depth 8 / 64. The cause
is in the C++ harness: `opponentDepth` and `opponentDeterminizations` default to
**4 and 20**, not to side A's values, and its `--help` claimed otherwise. Every
run before this fix was therefore 8/64 against 4/20 — half its moves searched by
a weaker configuration — and the `+29.6` and `+38.0` Elo figures those reports
produced were that mismatch, not noise.

Fixes:

- `lab/src/isolyn_lab/runner.py` resolves side B to side A unless the caller
  passes `--opponent-depth` / `--opponent-determinizations`, and always sends
  both explicitly.
- `tools/selfplay/main.cpp` now states the real defaults in `--help`
  (`default: 4, NOT --depth`, `20, NOT --determinizations`).

**This invalidates the throughput numbers in OPS-24.** Those were measured with
the weaker default. Re-measured with both sides at 8/64: **22.7 games/s** with
eight single-worker shards, so 5M games is ~61 hours, not ~32.

### Analyses

- `calibration.report_to_dict` emits one JSON object per input: games, decisions,
  outcomes, per-player win rate with a Wilson interval, side-by-side Elo with its
  interval when both sides played equal games, and the starting-hand Spearman
  correlations.
- `isolyn-lab evaluate --input` is now repeatable and `--json` emits an array, so
  **one process analyzes several CSVs**. Text mode is unchanged.
- The app's **Analyses** tab lists finished runs, lets several be selected, sends
  them in one call, and renders one card per input: a plain-language summary, a
  monospaced participant table, the Elo line and the correlations. Asymmetric
  inputs are called out explicitly rather than presented as Elo.

### Technical but friendly

The screen is split into **Runs** and **Analyses**. Plain-language labels sit
next to monospaced detail (run ids, d8/64 notation, shard counts), every
stepper has a tooltip explaining the term, presets carry a duration estimate,
and nothing technical is hidden behind a mode switch — the detail is simply
quieter than the action.

### Evidence (literal)

- `./scripts/lab evaluate --json --input smoke-400/merged.csv --input
  kill-900/merged.csv`: `reports: 2`, e.g. `1v1 games=400 decisions=6801
  outcomes={'closed': 88, 'domino': 312}`.
- Symmetric check: `0,77,1v1,8,64,8,64` in the CSV, and the app's end-to-end
  test asserts `configB.depth == 2` after a symmetric run.
- `8x50 symmetric wall: 17.60 s -> 22.7 games/s; 5M at this rate: 61.1 h`.
- `swift test`: `Executed 98 tests, with 0 failures`.
- Python lab tests: `Ran 5 tests ... OK`.
- `test_hundredAnalysisPressesLaunchOneProcess`: 100 presses → 1 process.

## OPS-28 — Kaggle bridge: design, arithmetic, and two verified blockers

**Scope:** analysis only. No engine, app or runner behaviour changed; one
document added and registered.

**Added.** `docs/research/KAGGLE_BRIDGE.md`, registered in `docs/README.md`. It
records Kaggle's current free-tier shape (12 h CPU sessions, 4 cores / 30 GB RAM,
20 GB saved output, 30 h/week GPU, 20 h/week TPU), the session arithmetic for a
5M-game corpus, a five-piece bridge design (`cloud/` dataset + env-driven
notebook + `scripts/lab cloud` driver + assembly + determinism policy), the
risks, and a one-session first step.

**Findings from reading this tree, not from Kaggle's docs.**

1. `tools/selfplay/build.sh` hardcodes `-framework Security`; Linux rejects it.
   `EntropySource.cpp` already contains a `getrandom()` path, so the build flag is
   the only thing standing between this code and a Kaggle CPU session.
2. `dealSeeded`, `Determinizer` and `SimulationEngine` use `std::shuffle` and
   `std::uniform_*_distribution`, whose output is implementation-defined. A seed
   that reproduces on libc++ will not necessarily reproduce on libstdc++, so a
   Kaggle-generated corpus is not seed-reproducible against a local one unless a
   stable in-tree shuffle replaces those calls.

**The number the founders should see.** Local symmetric self-play is 22.7
games/s; a Kaggle CPU session has half the cores and slower ones, so 6–11
games/s. A 5M corpus is therefore 11–20 sessions, i.e. one to three weeks at one
or two sessions a day — **not faster than the owner's machine**, only off it.
Kaggle buys breadth and a free machine, not speed.

**Evidence.** `python3 scripts/docs_audit.py`:
`RESULT: PASS — links, paths, status headers, register, banners and figures are consistent`.
Kaggle limits quoted from `https://www.kaggle.com/docs/notebooks` (Technical
Specifications) on 2026-11-14; GPU weekly quota from Kaggle's 30 h/week
announcement.

## OPS-29 — The Lab screen, rewritten for people who have never heard "seed"

**Scope.** Presentation and one new capability (a measured workload meter).
No engine, rule or runner behaviour changed.

**What changed on screen.**

- **Custom game counts.** A text field sits beside the presets, so "3,750,000"
  is as easy as "5M". A non-positive count disables Start and the service
  refuses it with "Choose at least one game."
- **A workload meter measured, not guessed.** The screen runs a short real
  workload — 8 games per shard process, at the currently selected depth,
  samples, mode and parallel count — times it, and reports games/s, total
  duration, batch count and disk size. It re-measures when the settings change
  (debounced 800 ms) and has a "Measure again" action. Probe run ids start with
  `probe-` and are filtered out of Recent runs.
- **Plain words first, jargon second.** "Look-ahead" with `depth` as its
  caption; "Worlds per move" for samples; "Batches at once" for shards; "Deal
  seed" explained as *the same seed always deals the same games*. A sentence
  under the grid says what each knob does.
- **Cleaner structure.** One column at 720 pt, three cards with a single visual
  weight, a log-scale gauge from one minute to seven days, and Recent runs
  titled by what they are ("5.0M games · 1v1 · seed 1") rather than by folder
  name.

**The meter's own evidence.** A probe of 64 games at depth 8 / 64 samples with 8
shards: `probe: 2.95s -> 21.7 games/s`, against 22.7 games/s for a full run.
The probe includes Python and process startup, so it reads slightly
conservative — the honest direction for an estimate.

**A failure found by the tests, and what it meant.** Adding the estimator broke
the existing offscreen render test with
`Fatal error: No Observable object of type LabEstimator found` — the test built
`LabView` with the old environment. The app itself injects it; the test was the
thing that was stale. Fixed by giving the test the same environment the app
provides, which is exactly what a render test is for.

**Evidence.** `swift test`: `Executed 104 tests, with 0 failures (0 unexpected)
in 3.812 (3.819) seconds`. `./scripts/ci/local.sh` runs the full six-step gate.
