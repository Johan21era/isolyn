# ISOLYN IMPLEMENTATION ROADMAP

> **Document status: historical plan, partially executed (verified 2026-11-13).**
> Phases 1 and 2 shipped (match orchestration, terminal guard, game board).
> Phase 3 shipped a five-band `DifficultyModel` whose intermediate bands are
> not statistically separable. Phases 4–7 have not started. The baseline in the
> header below is the 2026-08 starting point and is intentionally frozen; it is
> not current state. For current state use `docs/audits/2026-11-13-audit.md`.

**Companion to:** `docs/audits/2026-08-24-audit.md` (findings F‑01…F‑12) · `graphify-out/GRAPH_REPORT.md` (trace findings F‑T1…F‑T5)
**Baseline at roadmap writing (2026-08):** entire package builds & tests green on macOS (Swift 6.3 / Xcode 26.6) · engine 356/356 · bridge 33/33 · Swift suite 25/25 · zero force-unwraps · zero doc/code divergence confirmed by graph trace. Current verified counts live in `README.md`, `docs/history/legacy-handoff.md`, and `docs/engineering/BRIDGE_TESTING.md`; this roadmap is a plan, not a status report.

---

## 0. HOW TO READ THE PERCENTAGES

Every phase carries **% of Total Remaining Effort** — the estimated share of work standing between today's tree and "Isolyn 1.0": a distributable macOS app with playable matches vs. AI, plus Training and Sandbox modes per FEATURE_SPECS.md. Percentages are relative sizing, not calendar promises; each carries a confidence band. Sums to 100%.

**Ordering principle (per directive):** descending effort, hardest problems first. Phase 1 concentrates the two genuinely difficult open problems (terminal-state correctness + match-level architecture) alongside every confirmed High/Critical bug, so that by Phase 5 the residue is templated UI and hygiene.

**Standing rules carried forward:** Finality doctrine before any edit · engine changes land test-first · every claim verified by an actual compile/run shown in-session · zip/commit after each meaningful batch (F‑06 makes this enforceable at last).

---

## DEPENDENCY GRAPH (why this order and no other)

```
P1 ──► P2 ──► P3
 │      │
 │      └────► P5 ──► P6 ──► P7
 └────────────► P4 ────────┘   (P4 needs P1's guard; P5 needs P4's PositionConstructor)
```

- **P2 (board) cannot exist sensibly before P1**: the board's round-end overlay consumes `finalHandValues` (a P1 DTO addition), and multi-round flow requires the match coordinator.
- **P3 (AI) sits after P2** because AI turns are just a different driver of the same turn-flow state machine P2 introduces.
- **P4 (positions) needs P1's terminal guard** (constructed positions must respect ended-round semantics) and unlocks **P5**, whose puzzle generator synthesizes mid-game states through it.
- **P6/P7** are deliberately last: polish on features that finally exist, then release engineering once the surface stops moving.

---

## PHASE 1 — CORRECTNESS LOCK & MATCH ARCHITECTURE (~30% ±4)

**Objective:** eliminate every confirmed correctness defect, put the repo under version control, and build the single largest missing piece of architecture: round-to-round match orchestration. After this phase, Isolyn goes from "one round in a vacuum" to "a real match."

### 1a. Version control + verification harness repair *(small, blocking everything)*
- `git init` + `.gitignore`: `.build/`, `build/`, `.DS_Store`, `*.o`, `*.dSYM`, `.swiftpm/`, `graphify-out/cache/`. Initial commit of the audited green tree **before** touching anything else.
- Add `-framework Security` to the compile/link invocations in `scripts/ci/test_engine.sh`, `scripts/ci/test_bridge.sh`, and `scripts/ci/fuzz_bridge.sh` (exact fix already validated manually during the audit — F‑02). Re-run: expect **356/356** and **33/33** through the project's own scripts.
- Full sanitizer sweep while touching nothing: ASan+UBSan across all 18 engine binaries + bridge suite; TSan on SmokeTest and SearchEngineCancellationTests. Baseline must be zero-findings before edits begin (any finding found *now* becomes a Phase 1 work item, not a surprise later).

### 1b. Terminal-round guard (F‑03) — the highest-severity unfixed bug
Design decisions, made explicit:
- **New status, not reuse:** add `RoundAlreadyOver = 10` to `BridgeStatus`. Reusing `InvalidRequest` would force the UI to guess between "your tap was nonsense" and "the round you're looking at finished" — different recovery flows.
- **Additive ABI safety:** enums are `int32_t` with explicit values; existing consumers see it via `@unknown default` until the same commit updates `EngineTypes.swift`'s `BridgeError` mapping with a new `.roundAlreadyOver` case (this also retires half of F‑08's risk surface for free).
- **Check ordering stays fail-closed and retry-aware:** stale-version check **first**, then round-state check, then input validity, then legality — so a duplicated tap against a finished round reports `StaleRequest` (idempotency preserved), while a fresh-version command against a finished round reports `RoundAlreadyOver`.
- Applied to all four mutators: `bridge_submit_move`, `bridge_voluntary_draw`, `bridge_resolve_forced_draw`, `bridge_end_turn_with_no_play`. Read paths (`bridge_get_snapshot`) stay unguarded — observing a finished round is legitimate.
- **Regression tests (SmokeTest.cpp):** drive a 1v1 session to `DominoVictory` via bounded legal-move loop (deals are CSPRNG-nondeterministic, so loop-with-break, not scripted tiles), then assert all four mutators return `RoundAlreadyOver` and `stateVersion` is unchanged afterward. Mirror assertions for a driven `Closed`.

### 1c. Match orchestration — the keystone design *(bulk of the phase)*
Today's truth: bridge is deliberately round-scoped; `ScoreSystem` is built, tested, and wired to **nothing**; nobody owns `determineNextRoundStarter` between rounds (BRIDGE_ARCHITECTURE.md names this as designed-out pending a real design). Here is that design:

**Decision: scoring math stays in C++; orchestration policy lives in a thin Swift `MatchCoordinator`.** Rationale: `RulesEngine::computeRoundScores` / `combineTeamValue` / thresholds are already tested single-source-of-truth engine code — reimplementing them in Swift violates the project's own SSOT discipline. Conversely, session lifecycle policy is exactly what Swift actors are good at. The bridge grows data plumbing, not rules.

**Bridge additions (all POD, matching house style):**
```cpp
// SnapshotDTO gains (populated ONLY when roundOutcome != InProgress):
int32_t finalHandValues[kMaxPlayers];   // per-PLAYER remaining pip totals at reveal
// Reveal-on-end mirrors physical dominoes: hands are secret until the round
// concludes, so this leaks nothing during play and is zeroed otherwise.

MatchHandle bridge_match_begin(GameModeDTO mode);
// Wraps ScoreSystem(participantCountForMode) in the existing HandleTable pattern
// (shared_ptr, monotonic IDs, idempotent close — zero new concurrency concepts).

MatchResultDTO bridge_match_record_round(MatchHandle, SessionHandle finishedRound);
// Bridge-side steps, in order, all under existing locks:
//   1. pull cachedRoundOutcome/finalHandValues from the finished session
//   2. 2v2: combine partner values via RulesEngine::combineTeamValue
//   3. participantScores = RulesEngine::computeRoundScores(...)
//   4. ScoreSystem::applyRoundScores(...)
//   5. nextStarter = RulesEngine::determineNextRoundStarter(cachedDecidingPlayer)
// Returns scores, matchEnded, winnerParticipantIndex (-1 if ongoing),
// nextRoundStarterIndex. Rejects with RoundAlreadyOver-equivalent
// (BridgeFailure "match already ended") if fired after matchEnded.
```
**Swift side — `MatchCoordinator` (@Observable, MainActor):** owns the `MatchHandle` + the current `EngineSession`; publishes `scores: [Int]`, `currentStarter`, `matchWinner: Int?`; exposes `beginMatch(mode:)`, `finishCurrentRound()` (calls `bridge_match_record_round`, surfaces reveal), `dealNextRound()` (creates subsequent-round session via stored starter). Every failure path typed through the existing `BridgeError`.

**Edge cases enumerated up front (each gets a test):** simultaneous threshold crossing in 1v1v1 (documented ambiguity #10 stands: strictly-lowest wins outright); 2v2 team-score indexing vs. player indexing at the reveal boundary; `record_round` called twice (second must fail closed); session closed before reveal (typed error, match survives).

**Exit criteria:** full 3-round match drivable headlessly in SmokeTest across all three modes; `swift test` still 25/25; new bridge checks ≥ +12.

---

## PHASE 2 — THE GAME BOARD (~25% ±4)

**Objective:** the actual game screen — the largest single block of UI work in the project — consuming everything Phase 1 built. Human hot-seat first; AI arrives in Phase 3 through the same turn-flow interface.

**Architecture:** one `@MainActor @Observable final class GameViewModel` owning the current `EngineSession` (+ weak ref to `MatchCoordinator`). Its single source of UI truth is the last `GameSnapshot`, projected into a five-state machine:
`awaitingPlay → mustResolveForcedDraw → (boneyardExhaustedNoPlay) → roundEnded(reveal) → matchEnded(winner)`
Transitions occur only on successful commands; every mutation sends `expectedStateVersion`, making double-taps self-healing (stale → silent refresh, per optimistic-concurrency design already in the bridge).

**Components:**
- **TileView** — bone-white face, ebony back, center divider; pips drawn by generalizing `PipGlyph` to render 0–6 (currently 1–6; zero-pip blank face is the one gap). Refactor is parameter-addition, not rewrite.
- **ChainView** — horizontally scrolling bidirectional strip; doubles rendered perpendicular (pure visual convention — orientation isn't stored anywhere in the model, and per Chain.hpp never will be; derivable at render time as `low == high`).
- **HandRackView** — tiles sorted high-desc/low-desc; drag-and-drop via `.draggable`/`.dropDestination` onto two end drop-zones. Legality is **pre-checked locally** against `snapshot.legalMoves` for instant gray-out feedback, with the bridge's `InvalidMove` as the authoritative second gate — deliberate defense-in-depth mirroring the bridge's own philosophy.
- **Forced-draw flow:** when the state machine lands on `mustResolveForcedDraw`, the VM auto-calls `resolveForcedDraw(expecting:)` and animates the drawn count; the "end turn without playing" action renders only when the snapshot shows `boneyardDrawableCount == 0` and the player is still blocked — exactly the bridge's own precondition, surfaced as UI affordance.
- **Analysis drawer:** wraps the existing two-phase `requestAnalysis` — indeterminate progress + working **Cancel** button (wired to `AnalysisTask.cancel()`), result panel shows highlighted recommended tile and per-player value bars. Honors the `samplesCompleted == 0 → do not display` contract as a hard rule, not a suggestion.
- **Round-end overlay:** reveal animation over `finalHandValues` (Phase 1 DTO), points-applied readout, next-starter announcement, "Deal Next Round" → `MatchCoordinator.dealNextRound()`.
- **Error surface:** every `BridgeError` maps to a typed, dismissible alert; `sessionClosed` routes to match teardown rather than a dead screen.

**Accessibility baseline (cheap now, painful later):** every tile carries `accessibilityLabel("domino 4-6")`; drop zones labeled "attach to left end showing 3".

**Exit criteria:** a complete multi-round 1v1 hot-seat match playable start to finish, all three modes navigable, no unhandled bridge status anywhere (grep-auditable).

---

## PHASE 3 — OPPONENT INTELLIGENCE: DIFFICULTYMODEL + AI TURNS (~15% ±3)

⚠️ *HANDOFF gate: "confirm with the user before starting DifficultyModel." Adopting this roadmap constitutes that confirmation — flagging explicitly rather than silently proceeding.*

**Objective:** engine-driven opponents with a calibrated strength dial (100–3000), honoring STRATEGY_NOTES' twin requirements: strong play ≈ 5–7 ply lookahead, and win-rate-vs-hand-quality correlation as the measurable calibration proxy.

**Calibration harness (engine-only, no UI):** `tools/selfplay/main.cpp` — sweeps a `(maxDepthPlies × determinizationCount × strength-label)` grid, plays N≥200 games/cell pairwise between adjacent strengths, emits CSV: win rate, average score delta, and Spearman correlation between initial hand quality and outcome. Committed under `tools/calibration/` so recalibration is reproducible evidence, not vibes.
**Initial mapping hypothesis to be validated, then frozen into `DifficultyModel`:**
| Strength | Depth | Determinizations | Expected character |
|---|---|---|---|
| 100–400 | 2 | 8 | playable, blunder-prone |
| 400–900 | 3 | 16 | solid basics |
| 900–1600 | 4 | 24 | ≈ current defaults |
| 1600–2300 | 5 | 40 | competitive |
| 2300–3000 | 8 | 64 | elite; **implemented as depth 8**, measured −53.2 Elo vs 100–400 |

Acceptance: monotonic win-rate ladder (each tier beats the previous ≥55%), correlation-vs-hand-quality declining with strength (STRATEGY_NOTES' stated signal of good calibration).

**AI turn flow (reuses Phase 2's machinery — that's why P3 follows P2):** on opponent turns, `GameViewModel` dispatches `requestAnalysis(believer: seat, config-from-DifficultyModel)` via the existing detached-task path (UI never blocks — 10,716,606 concurrent queries during one analysis, measured 2026-08-24; re-measured 2.2–6.7M on 2026-11-13, same property), awaits the outcome, submits `recommendedMove`. Hard rule inherited unchanged: `samplesCompleted == 0` → fall back to a uniformly-random *legal* move and log, never display. Fairness note: the AI reasons from its own believer perspective only — hidden-info isolation is structural (snapshot model), not honor-system.

**Explicitly deferred:** heuristic-weight tuning (`kNextRoundStartBonus`, eval weights) stays untouched this phase — changing evaluation while introducing opponents would confound the calibration signals. Weight tuning becomes a Phase 5+ follow-up only if ladder acceptance fails.

---

## PHASE 3.5 — OFFLINE LAB + METAL ACCELERATOR (owner-added track)

**Status:** standalone batch evaluator implemented 2026-11-11; search
integration pending. Not included in the original 100% budget. This track runs
beside Phases 3–5, not instead of them. See
`docs/engineering/OPEN_DECISIONS.md` (ADR-002/003), `docs/subsystems/LAB.md`, and
`docs/subsystems/ACCELERATOR.md` for the binding detail.

- **Offline lab/trainer:** `tools/selfplay/` is a C++ harness that links the real
  engine and emits reproducible CSV/JSONL; `lab/` is a Python package for
  calibration, datasets, and optional training. Python never ships in the app
  and never owns a game rule. Trained weights return to C++ inference.
- **Metal accelerator:** a first-class GPU compute backend, not a micro-
  optimization. Start with batched leaf evaluation and parallel root
  determinizations; a GPU-resident frontier comes only after parity and
  throughput are proven. CPU is the reference and always the fallback.
- **Gates:** CPU parity, deterministic tie-breaking, no rules in shaders,
  fallback on missing/unsupported GPUs, and a measured strength ladder — not
  kernel throughput alone.
- **Order:** self-play baseline first, then calibration, then accelerator;
  learned evaluation only if the ladder justifies it.

---

## PHASE 4 — POSITION CONSTRUCTION: SANDBOX FOUNDATION (~12% ±3)

**Objective:** build the named-but-absent `PositionConstructor` (FEATURE_SPECS calls it "shared answer to both modes — worth prioritizing"), expose it through the bridge, ship the Sandbox setup screen and the live eval bar.

**Engine — `PositionConstructor`:** validates `{mode, hands[4], chainTiles[], currentPlayer}` against hard invariants, returning a list of specific violations (not a bool): exact tile conservation (28 minus mode-excluded — reuses `Dealer::excludedTilesForMode`), chain internal consistency (every adjacent pair shares a face; declared ends match the walk), currentPlayer bounds. Sandbox permissiveness question resolved as: **conservation and chain-validity are non-negotiable; hand-size/misdeal constraints get an explicit `allowNonstandardHands` flag** — arbitrary positions yes, physically impossible ones no.

**Bridge:** `SessionHandle bridge_session_from_position(SandboxPositionDTO)` where the DTO is fixed-size POD (`TileDTO hands[4][28]` + counts + chain array) — sized for the 28-ceiling exactly like every existing array, so truncation-corruption is structurally impossible. Plus the cheap evaluator: `EvaluationDTO bridge_evaluate_position(session, believerIndex)` running `ProbabilityEngine::constructFromGameState` + `EvaluationEngine::evaluate` on the live state with **zero search** — microseconds, safe synchronously on the actor, which is what makes a continuously-updating eval bar trivial.

**Sandbox UI:** tile inventory grid → drag into hand slots / onto the chain builder; mode selector; validity checklist rendered live from PositionConstructor's violation list; then straight into the Phase 2 board. Eval bar component subscribes post-every-move.

**Exit criteria:** hand-construct a classic endgame (e.g., the audit's 4-4/4-6/4-1 trap from SearchEngineTests) in the UI and play it out; invalid constructions rejected with named reasons.

---

## PHASE 5 — EXPLANATIONENGINE + TRAINING MODE (~10% ±3)

**Objective:** the second spec'd mode, and the feature that makes Isolyn *worth* playing beyond novelty: teaching.

**Design stance (from FEATURE_SPECS):** explanations must be "simple but deep," tunable-register — therefore the engine returns **structured reasons, never prose**: `ExplanationReason` codes (`DOMINO_RISK_CREATED`, `CLOSE_WINDOW_MISSED`, `MOBILITY_COLLAPSE`, `VALUE_SWING_AGAINST`, `SET_UNSAFE_TO_OPEN`, …) each carrying numeric params (delta components from `EvaluationBreakdown`, relevant `probabilityHoldsAtLeast` figures, next-round-start stakes). Prose lives in Swift templates — swappable register, localizable, unit-testable independently of math.

**Mechanism:** for a candidate (or played) move M vs. engine-best B: evaluate both resulting states (concrete world, believer POV — no search needed for the *why*, only for identifying B), decompose the criterion delta per component, attach belief-query context ("you hold 2 sixes; 4 remain unaccounted — opening 6-6 here succeeds only if neither opponent holds a third"). The lockdown-double tactic from STRATEGY_NOTES becomes explainable the day its inference numbers are exposed — which BeliefState already supports.

**Puzzle generator:** random deal → apply k sampled legal playouts (reuse `SimulationEngine`-style determinized rollouts) to reach a plausible mid-game → run high-config `SearchEngine` to identify the correct move → persist the puzzle as **seeds only** (deal entropy + playout seeds), regenerating the position on demand — compact, verifiable, infinite supply.

**Training UI:** Phase 2 board in read-only mode; wrong move → red highlight + shake + centered explanation box (spec-exact); correct move → consequence explanation; difficulty selector maps to puzzle search-config tier.

**Dependency:** strictly after P4 (generator synthesizes through PositionConstructor).

---

## PHASE 6 — ENVIRONMENT COMPLETION, POLISH & PACKAGING PREP (~5% ±2)

The residue, deliberately last — each item small, none architecturally risky:
- **F‑04 closure (the one design fix left):** `EnvironmentManager` gains `@MainActor` on all mutating/query paths except `deinit`; `weatherSource` captured to a local before any `await`; `LiveWeatherService.lastKnownGood` confined behind those same MainActor callsites (option *a* from the project's own HANDOFF batch-6 menu). Clears the sole Swift-6-mode warning (`EnvironmentManager.swift:146`) in the same stroke.
- **Wire-or-remove decision executed:** `EnvironmentSettingsView` hosted in a proper Settings scene (⌘,) with `EnvironmentTimeLabel` in the game HUD; limbo ends either way.
- **WeatherKit robustness:** delegate-based `CLLocationManager` wrapper actor (authorization states handled explicitly), 10-minute condition TTL, existing didBecomeActive refresh kept.
- **Micro-fixes in one sweep:** F‑07 (`failedAnalysis` → `BridgeFailure`), F‑08 (`os_log` on unknown DTO enums), F‑09 (cached `DateFormatter`), F‑10 (cancel-on-disappear for abandoned analyses), F‑11 (`applyOpponentDraw` mass≤0 early-return), F‑12 (HandleTable comment truthing).
- **Distribution prep:** release build configuration, app icon set, `PrivacyInfo.xcprivacy` (CoreLocation access type), `NSLocationWhenInUseUsageDescription`, WeatherKit capability, hardened-runtime/signing checklist. Fog-as-discrete-layer only if budget remains — tint treatment is already acceptable.

---

## PHASE 7 — RELEASE ENGINEERING & CLOSEOUT (~3% ±1)

- **CI:** GitHub Actions macOS runner — `swift build && swift test`, all three fixed scripts, scheduled weekly ASan job. Makes F‑02-class drift structurally impossible to reintroduce unnoticed.
- **Versioning + artifact:** SemVer tags; `swift build -c release` → bundled `.app` script → `codesign` + notarization invocation documented step-by-step.
- **Docs closeout:** HANDOFF.md rewritten to post-roadmap reality (what exists, what's verified, what's next); every audit finding F‑01…F‑12 marked fixed/verified with pointer to commit; fix-log finalized. Session-close-out rule satisfied: a stranger could resume with zero questions.

---

## EFFORT SUMMARY TABLE

| Phase | Title | % of total | Confidence | Hardest single problem inside |
|---|---|---|---|---|
| 1 | Correctness Lock & Match Architecture | **30%** ±4 | Medium-High | Reveal-semantics + match state contract |
| 2 | The Game Board | **25%** ±4 | High | Turn-flow state machine + DnD |
| 3 | DifficultyModel + AI Turns | **15%** ±3 | Medium | Empirical calibration ladder |
| 4 | PositionConstructor + Sandbox | **12%** ±3 | High | Arbitrary-position validation |
| 5 | ExplanationEngine + Training | **10%** ±3 | Medium | Structured-reason decomposition |
| 6 | Polish, Env Completion, Packaging Prep | **5%** ±2 | High | — (deliberately shallow) |
| 7 | Release Engineering & Closeout | **3%** ±1 | High | — |

## RISK REGISTER (top 4)

1. **P1 match-reveal semantics** — the `finalHandValues`-on-end DTO is the one place hidden-info architecture and scoring intersect; mitigated by keeping computation in tested engine code and gating with new bridge tests before Swift touches it.
2. **P3 calibration may refuse to cooperate** — depth/determinization ladder might not produce monotonic strength; mitigation: harness exists precisely to detect this early, and eval-weight tuning is held in reserve, explicitly deferred.
3. **P2 DnD ergonomics on macOS** — drag-and-drop polish is historically time-hungry; mitigation: legality pre-check means even janky drops are *correct*, only unpolished.
4. **Scope gravity in P2/P5** — the board invites feature creep; mitigation: exit criteria are written down above and binding.

## FIRST THREE ACTIONS WHEN WORK BEGINS

1. `git init` + ignore list + commit the green tree (ten minutes; makes everything else reversible).
2. `-framework Security` into the three scripts; re-run to 356/356 + 33/33 through the repo's own tooling.
3. Open Phase 1b: `RoundAlreadyOver` status + guards + SmokeTest regressions, Finality-gated per protocol.
