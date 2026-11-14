# ISOLYN CORE HARDENING ROADMAP

> **Status: completed plan (2026-08), archived 2026-11-13.** Phases 1–6 were
> executed; receipts are in `docs/history/fix-log.md` (FIX-15…FIX-26, OPS-05…08).
> Kept as the record of how the hardening session was scoped and ordered. Its
> baseline numbers (356/356, 57/57, 28 tests) are 2026-08 measurements. Current
> state: `docs/audits/2026-11-13-audit.md`.

**Purpose:** make the core architecture *sound and extremely strong* before the planned UI revival.
**Companion to:** `docs/roadmaps/strategy-roadmap.md` (feature roadmap — unchanged, still governs Phases 3–7 feature work) · `docs/audits/2026-08-24-audit.md` (findings F‑01…F‑12) · `docs/history/fix-log.md` (protocol format for every fix below) · `docs/history/legacy-handoff.md` (house rules — ALL binding).
**Baseline (verified this session):** `swift build` clean · `swift test` → 28 tests, 1 skipped, 0 failures · git clean except one untracked doc (Step 0 closes that).
**Owner directive:** descending workload per phase. Phases 1–3 carry the absolute heaviest lifting; 4–6 shrink to fixes and adjustments. Total budget ≈ a few hours. UI revival happens AFTER this roadmap completes — explicitly out of scope here.

---

## SCOPE BOUNDARY (read first)

This roadmap contains **zero new features and zero visual redesign**. Everything here makes existing code correct, safe, verifiable, or honest:

| Category | Included | Excluded |
|---|---|---|
| Correctness | F‑04, F‑07, F‑08, F‑09, F‑10, F‑11, F‑12, N‑1…N‑7 (new findings, see §A) | Any gameplay/rule change |
| Safety | Concurrency confinement, cancel-on-abandon, sanitizer baseline | New subsystems |
| Verifiability | CI pipeline, regression tests, final proof gates | Test-framework churn |
| Honesty | Wiring or removing dead controls/comments, doc closeout | Cosmetic polish |

DifficultyModel/AI, Sandbox, Training, drag-and-drop, and the entire UI revival remain governed by `docs/roadmaps/strategy-roadmap.md` and come after this document is done.

---

## DEPENDENCY LOGIC (why this order)

```
P1 ──► P2 ──► P3 ──► P4 ──► P5 ──► P6
 │      │      │
 │      │      └─ CI must exist AFTER the fixes it will guard,
 │      │         or it just automates brokenness.
 │      └─ Bridge semantics settle BEFORE CI freezes expectations.
 └─ Concurrency/lifecycle first: highest blast radius, and the
    sanitizer sweep (P3) must measure the POST-fix code.
```

Front-loading rule satisfied by construction: P1/P2/P3 are design-and-infrastructure work; P4/P5/P6 are increasingly mechanical sweeps that terminate in paperwork.

---

## STEP 0 — REPO HYGIENE GATE *(minutes — do before anything else)*

Non-negotiable preconditions, per house rules §5.2 and §7.4:

1. `git add "docs/audits/2026-08-24-audit.md"` + commit — the audit is meaningful work living in exactly one place (**closes N‑7**).
2. Re-run the three proofs to pin the baseline in-session: `./scripts/ci/test_engine.sh` → 356/356 · `./scripts/ci/test_bridge.sh` → 57/57 · `swift test` → 28/0-failures. Record outputs in the session log. If ANY differs → STOP and report verbatim (handoff §8.1).

---

## PHASE 1 — CONCURRENCY & LIFECYCLE HARDENING *(~30% of effort — heaviest)*

**Objective:** eliminate every known shared-mutable-state hazard and resource-lifecycle leak. These are the fixes with the widest failure radius and the ones a sanitizer sweep would otherwise chase ghosts around.

### 1a. F‑04 — EnvironmentManager / LiveWeatherService race closure
- Files: `Sources/IsolynApp/Environment/EnvironmentManager.swift`, `LiveWeatherService.swift`.
- Apply HANDOFF batch‑6 option (a): confine the weather-refresh path to `@MainActor`; capture `weatherSource` into a local **before any `await`**; bring `LiveWeatherService.lastKnownGood` writes behind those same confined callsites.
- Acceptance: the Swift‑6-mode concurrency warning at `EnvironmentManager.swift:146` is gone (`swift build` output greps clean for that warning class); `swift test` still 28/0; `.live` mode toggle + foreground-refresh exercised once manually.

### 1b. F‑10 — Cancel-on-abandon for analyses
- Files: `Sources/IsolynApp/Game/GameViewModel.swift`, `InteractiveGameBoardView.swift`, `Sources/IsolynApp/Engine/EngineSession.swift`.
- Today: an `AnalysisTask` dropped without awaiting burns CPU to completion on a detached task. `shutdown()` already cancels, but nothing guarantees it runs when the game screen leaves the hierarchy.
- Fixes: (1) `.onDisappear { viewModel.shutdown() }` on the board view so teardown always cancels + releases handles; (2) audit every `analysisTask` replacement/drop site routes through `invalidateAnalysis()` (already true — assert it with a comment anchor); (3) document the contract on `AnalysisTask`: callers MUST either await `result` or call `cancel()`.
- Acceptance: start an analysis, navigate Back mid-search → search stops within one determinization sample (observable via brief CPU spike ending); no leaked snapshot handles (SmokeTest's handle-count invariant unaffected).

### 1c. F‑11 — BeliefState divide-by-zero guard (ENGINE CHANGE — test-first, house rule #5)
- Files: `Sources/IsolynEngine/BeliefState.cpp` (+ header precondition doc), new case in `Tests/IsolynEngineTests/BeliefStateTests.cpp`.
- Under NDEBUG, `applyOpponentDraw` with boneyard mass ≤ 0 divides by zero → NaN beliefs. Unreachable through today's bridge, but public API.
- Fix: write the failing/guarded test FIRST (construct belief, reveal the locked pair to empty the yard-mass, call `applyOpponentDraw`, assert probabilities stay finite and sum to 1), then add the early-return guard + precondition comment.
- Acceptance: new test passes; full `scripts/ci/test_engine.sh` ≥ 357 checks, zero warnings.

### Exit criteria (all of Phase 1)
`swift build` zero warnings · `swift test` 28/0 · engine suite green incl. new check · one commit per sub-item (1a, 1b, 1c separately — 1c cites its test).

---

## PHASE 2 — BRIDGE & API SEMANTICS SWEEP *(~25% of effort)*

**Objective:** make every boundary status truthful. The bridge's reputation rests on fails-closed honesty; two spots currently bend it.

### 2a. F‑07 — Truthful failure for unknown analysis handles
- Files: `Sources/IsolynEngineBridge/IsolynBridge.cpp` (`bridge_analysis_run` first guard), `Tests/IsolynEngineBridgeTests/SmokeTest.cpp`, comment touch-up in `Sources/IsolynApp/Engine/EngineTypes.swift`.
- Change: unknown analysis handle → `failedAnalysis(BridgeStatus::BridgeFailure, "unknown analysis handle")` instead of `SessionClosed` (a session word misdescribing a snapshot problem).
- Regression: new SmokeTest check — `bridge_analysis_run(kInvalidAnalysisHandle, …)` returns `BridgeFailure`. Suite goes 57 → 58.
- Swift side already maps generically (`bridgeFailure(diagnostic:)`) — only the stale comment needs updating.

### 2b. F‑08 — Observable divergence on unknown DTO enums
- Files: `Sources/IsolynApp/Engine/EngineTypes.swift` (`@unknown default` arms: `RoundOutcome.init`, mode switch, `BridgeError.init(status:)`).
- Replace silent fallbacks with `os.Logger(subsystem: "com.isolyn.app", category: "bridge-dto")` fault logs so a future C++ enum evolution surfaces loudly instead of masquerading as `.inProgress`.
- Acceptance: grep shows every `@unknown default` either logs or has a written justification; build clean.

### 2c. F‑12 — HandleTable comment truthing
- File: `Sources/IsolynEngineBridge/IsolynBridge.cpp` (`HandleTable::insert`).
- Delete the no-op `if (m_nextId == 0) m_nextId = 0;` line and the misleading clamp comment; the entry guard is the sole mechanism — say exactly that.
- Acceptance: bridge suite still 58/58 (no behavior change intended or permitted).

### Exit criteria
`./scripts/ci/test_bridge.sh` → 58/58 through the repo's own tooling · engine suite untouched-green · commits per sub-item.

---

## PHASE 3 — VERIFICATION INFRASTRUCTURE *(~20% of effort)*

**Objective:** make F‑02-class drift structurally impossible and pin a memory-safety baseline measured against post-Phase‑1 code.

### 3a. CI pipeline
- New file: `.github/workflows/ci.yml` — macOS runner: `swift build && swift test`, then `./scripts/ci/test_engine.sh` and `./scripts/ci/test_bridge.sh`. Trigger: push + PR to main; optional weekly scheduled job for fuzz (`./scripts/ci/fuzz_bridge.sh 15`) so coverage keeps refreshing without slowing merges.
- Acceptance: workflow passes on a pushed branch (owner pushes; agent verifies YAML locally + documents expected runtime).

### 3b. Full sanitizer baseline (post-fix code)
- Commands (documented in fix-log entry): ASan+UBSan across all 18 engine binaries + bridge suite; TSan on SmokeTest and SearchEngineCancellationTests; quick standalone-fuzz pass.
- Gate: **zero findings**, recorded verbatim. Any finding found NOW becomes a Phase‑1-style work item immediately — surprises later are forbidden.

### 3c. Packaging groundwork (paper-only, F‑05 prep)
- New doc: `docs/engineering/RELEASE_CHECKLIST.md` — enumerates the Xcode-target requirements (PrivacyInfo.xcprivacy CoreLocation declaration, NSLocationWhenInUseUsageDescription copy, WeatherKit capability, hardened-runtime/signing, icon pipeline) so the eventual app-shell work is a checklist, not archaeology. NO Xcode project created in this roadmap.

### Exit criteria
CI green on main · sanitizer log committed to fix-log · checklist doc exists · one commit.

---

## PHASE 4 — APPEARANCE DATA-MODEL CORRECTNESS & MECHANICAL FIXES *(~13% of effort)*

**Objective:** repair the appearance pipeline's real correctness bug, make its controls honest, and clear the small audit debt. (These are data/model integrity items — NOT the UI revival.)

### 4a. N‑1 — Kill the hex-cache; make HSB math pure *(the one real bug in this phase)*
- File: `Sources/IsolynApp/Game/Appearance/DominoAppearance.swift`.
- Today `Color.hsB`/`hexString` resolve through a static `_hexCache` that `init(hex:)` never populates → `setBodyHue` reads `(0,0,0)` and snaps tiles to black; thumb position always hue 0; unsynchronized global mutable state besides.
- Fix: delete `_hexCache` entirely. Derive HSB purely from hex strings (`resolveHex → rgbToHsb`); produce hex purely from HSB (`hsbToRgb → rgbToHexString`). `setBodyHue` computes saturation/brightness from `appearance.bodyColorHex` directly. `HueSlider.thumbOffset` likewise reads the pure function.
- Acceptance: dragging hue preserves the tile's saturation/brightness and only rotates hue; thumb tracks current hue; `swift test` green (add a small pure-function unit test for rgb↔hsb round-trip if the environment allows — otherwise assert via the drawer flow manually and record it).

### 4b. N‑2 — Wire edge-highlight settings into the renderer
- Files: `IsolynDominoTile.swift`, (read-only) `SettingsDrawer.swift`.
- Rule: when `appearance.edgeMode != .none` AND no `semanticEdge` is active, stroke the border with `appearance.edgeColor.opacity(appearance.edgeIntensity)` at width scaled subtly by mode. `semanticEdge` (engine semantics) ALWAYS wins precedence — analytical edges must never be drowned out by decoration.
- Acceptance: cycling None/Subtle/Standard/Strong visibly changes tiles live; presets render sensibly; preview tile in drawer reflects instantly.

### 4c. F‑09 — Cache the DateFormatter
- File: `Components/EnvironmentTimeLabel.swift`.
- Static cache `[String: DateFormatter]` keyed by `timeZoneIdentifier` (MainActor-confined access — label body already is). One formatter per zone, built once.

### 4d. N‑4 — PipGlyph honesty for counts outside domino range
- File: `Components/PipGlyph.swift`.
- Real double-six faces only exist for 1–6; a 7-tile rack currently renders an EMPTY glyph (silence = lie). Fix: counts ≤6 keep pip patterns (add explicit `0` → empty is fine); counts ≥7 render a monospaced digit badge instead of inventing a pip arrangement (house rule: never fabricate). Update `opponentCountsView` clamp accordingly.
- Acceptance: opponent holding a full 7-tile hand displays "7", not blank space.

### 4e. N‑6 — Silence the SPM resource warning
- File: `Package.swift` — `exclude: ["Info.plist"]` on the IsolynApp target. Build log loses the warning.

### Exit criteria
Build zero warnings · `swift test` green · hue slider demonstrably fixed · one commit (4a alone, rest batched or split as convenient).

---

## PHASE 5 — INTERACTION CONTRACTS & DEAD-CODE DECISIONS *(~8% of effort)*

**Objective:** end the "limbo" states — promises made by comments/controls that nothing fulfils.

### 5a. N‑3 — Hover-chain overlay gets real dismissal logic
- Files: `ChainAndZonesView.swift`, `HoverChainOverlay.swift`, `HoverChainController.swift`.
- Implement the exit logic the comments already promise: (1) pointer leaves both end-zone AND overlay for a grace period (~250ms) → `dismiss()`; (2) explicit close affordance (✕) on the overlay; (3) auto-dismiss on any successful move / stateVersion advance / phase change (stale knowledge is worse than no knowledge); (4) preserve suspend-during-camera-drag semantics.
- Also resolve the no-op `handleHover(at:)` stub: either delete it or give it the world-space hit-test it apologizes for lacking — deletion preferred this phase.
- Acceptance: hover end-zone → panel appears; move pointer away → gone; play a tile → gone; pan board → suspended then resumed correctly.

### 5b. Wire-or-remove sweep
- `EnvironmentSettingsView` — END THE LIMBO (audit's explicit demand): host it in a proper `Settings` scene (⌘,) in `IsolynApp.swift`. Small, additive, resolves the oldest open placement question. (If owner prefers removal, say so and delete instead — one or the other, no third state.)
- Delete genuinely dead display code found this session: `RulesOfDisplay` enum (RoundEndOverlay.swift), `displayLeft/displayRight` (HoverChainOverlay.swift).
- Leave test-seams alone (ProbabilityEngine observe*, `determineNextRoundStarter`, ScoreSystem) — those are documented reserved architecture, not cruft.

### Exit criteria
No comment in `Sources/` promises behavior that doesn't exist (spot-audit) · settings reachable via ⌘, · build+test green · one commit.

---

## PHASE 6 — DOCS CLOSEOUT & FINAL GREEN GATE *(~4% of effort — lightest)*

**Objective:** leave the tree stranger-resumable than we found it, with every claim machine-checkable.

1. **docs/history/fix-log.md** — append entries in the 12-field protocol format: FIX‑15 (F‑04), FIX‑16 (F‑10), FIX‑17 (F‑11 + test anchor), FIX‑18 (F‑07), FIX‑19 (F‑08/F‑12), FIX‑20 (N‑1…N‑6 compressed), OPS‑04 (CI), OPS‑05 (sanitizer baseline log). Each with grep-able anchors, per protocol.
2. **docs/history/legacy-handoff.md** — refresh the scoreboard table (356→357+, 57→58, 28 tests, CI row added) and §4 table with this session's rows.
3. **Audit ledger** — mark F‑04, F‑07, F‑08, F‑09, F‑10, F‑11, F‑12 resolved in a short addendum to `docs/audits/2026-08-24-audit.md` (do NOT rewrite history — append).
4. **Final proofs, verbatim outputs into the log:** `./scripts/ci/test_engine.sh` · `./scripts/ci/test_bridge.sh` · `swift test` · `./scripts/ci/fuzz_bridge.sh 15` · CI badge green on GitHub.
5. Push. Tag the state (e.g. `core-hardened-1`) so the UI revival starts from a named, immutable baseline.

---

## EFFORT SUMMARY

| Phase | Title | % | Character |
|---|---|---|---|
| 0 | Repo hygiene gate | — | minutes |
| 1 | Concurrency & lifecycle hardening | **30%** | hardest design work (F‑04 confinement strategy, test-first engine change) |
| 2 | Bridge & API semantics sweep | **25%** | cross-layer coordination + regression authoring |
| 3 | Verification infrastructure | **20%** | CI authoring + full sanitizer campaign |
| 4 | Appearance model & mechanical fixes | **13%** | one real bug (N‑1) + small honest-UI repairs |
| 5 | Interaction contracts & dead-code decisions | **8%** | dismissal logic + wire-or-remove judgment calls |
| 6 | Docs closeout & final green gate | **4%** | paperwork, proofs, tag |

Strictly descending ✓. Heavy lifting exhausted by Phase 3 ✓. Everything after is fixes/adjustments ✓.

---

## RISK REGISTER

1. **F‑04 confinement may surface latent MainActor assumptions elsewhere in Environment/** — mitigation: option (a) is deliberately the minimal-conversion path; compiler guides the rest.
2. **Sanitizer sweep might find something real** — mitigation: it's scheduled BEFORE CI freezes expectations precisely so findings become Phase‑1-style work immediately, not post-hoc shame.
3. **N‑2 edge wiring could fight `semanticEdge` visuals** — mitigation: strict precedence (semantic wins) specified up front; presets eyeballed in acceptance.
4. **Scope gravity toward UI revival mid-phase** — mitigation: this document's scope table is binding; anything visual goes on the revival backlog, not in these commits.

## EXPLICITLY DEFERRED (post-roadmap)

UI revival (entire — owner-led, next session) · AI/DifficultyModel (`docs/roadmaps/strategy-roadmap.md` P3) · PositionConstructor/Sandbox (P4) · ExplanationEngine/Training (P5) · distribution/packaging execution (only the checklist ships here) · drag-and-drop placement.

---

*House rules in force throughout: Finality doctrine before edits · engine changes land test-first · every claim proven by shown command output · commit after every meaningful chunk · when torn between readings, stop and ask the owner.*
