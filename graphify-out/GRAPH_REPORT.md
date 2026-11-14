# Graph Report - Isolyn-current_4  (2026-11-14)

## Corpus Check
- 225 files · ~241,470 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2843 nodes · 5431 edges · 168 communities (146 shown, 22 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 358 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `36dbbc9b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Appearance
- Root Docs
- Root Docs
- Hoverchain
- Include
- Isolynapptests
- Include
- Root Docs
- Isolynenginebridge
- Game
- Environment
- Isolynenginebridge
- Include
- Isolynapptests
- Game
- Include
- Isolynengine
- Include
- Engine
- Include
- Include
- Include
- Engine
- Include
- Root Docs
- Components
- Hoverchain
- Include
- Include
- Isolynenginetests
- Environment
- Isolynapp
- Engine
- Isolynengine
- Isolynengine
- Include
- Engine
- Isolynenginebridgetests
- Environment
- Include
- Root Docs
- Environment
- Appearance
- Include
- Isolynengine
- Include
- Include
- SamplePool
- Root Docs
- Game
- Include
- Isolynenginebridge
- Isolynengine
- Root Docs
- EnvironmentClock
- Include
- Include
- Include
- Root Docs
- Environment
- ISOLYN IMPLEMENTATION ROADMAP
- Include
- Components
- Components
- Views
- Isolynengine
- Include
- Root Docs
- Root Docs
- Isolynengine
- Isolynengine
- Include
- Isolynenginebridgetests
- Root Docs
- Root Docs
- Root Docs
- Root Docs
- Root Docs
- Root Docs
- Root Docs
- ISOLYN RELEASE CHECKLIST
- Dealer::deal
- 29. IMPLEMENTATION ORDER
- Feature Specifications — Training Mode and Sandbox Mode
- SearchDecision
- 26. EXACT INFORMATION HIERARCHY
- THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.
- 30. ACCEPTANCE CRITERIA
- EnvironmentTests.swift
- 3. DOMINO TILE SPECIFICATION
- DealResult
- RoundOutcome
- 4. BOARD MUST LOOK LIKE A DOMINO BOARD
- 9. PLAYER HAND
- DOMINOES UI FIX --- NON-NEGOTIABLE REBUILD MANDATE
- Isolyn Current Audit (Markdown edition)
- README.md
- IsolynV2.0 — Open Decisions & Architecture Records
- tree.md
- Audit Remediation Roadmap
- GameSnapshot Test Seam (internal init)
- OA-1: macOS Soak Test Is a Silent No-Op
- OA-4: Long Chains Exceed Board/Camera Bounds
- OA-5: Open Decisions (Ambiguity #6/#8, Approximation, Weights)
- Core Hardening Roadmap
- Swift/C++ Bridge (POD-Only Safety Wall)
- Bridge Architecture (Design Doc)
- Match Orchestration Surface (bridge_match_*)
- Two-Phase Analysis Design
- Blocked-Current-Player Analysis UB (Fuzz-Found)
- Bridge Testing (Verification Record)
- Adversarial-Input Fuzz Campaign (FuzzBridge.cpp)
- No Swift Toolchain Available (Linux Sandbox)
- DifficultyModel (Not Yet Built)
- Feature Specifications (Training & Sandbox)
- ExplanationEngine (Not Yet Built)
- PositionConstructor (Not Yet Built)
- Release Checklist
- Closing vs Domino-Run Decision (Estimation-Driven)
- Strategy Notes (Domain Knowledge for Engine Contributors)
- Elite Lockdown-Double Tactic (Confidence Reads)
- 1v1 Look-Ahead Depth (5–7 Moves)
- Dominoes UI Fix — Non-Negotiable Mandate
- Responsive Clause §17 (Scale Intelligently, Never Crush)
- Single-Rectangle Domino Law (§2)
- Fix Log (12-Field Protocol Entries)
- FIX-07: Terminal-Round Guard (RoundAlreadyOver = 10)
- FIX-09: Match Orchestration Surface + Logged Invariants
- EvaluationBreakdown
- STRENGTH_BASELINE.md
- .record
- rules_audit.py
- OPS-27 — Analyses in the app, and the opponent default they exposed
- DifficultyProfileDTO
- createFirstRound
- lab
- local.sh
- E-014 — Trimmed-mean root selection (rejected)
- Isolyn Offline Lab (scaffold)
- Isolyn Self-Play Harness (scaffold)
- ComingSoonView
- Move
- build_parser
- DominoTile.cpp
- benchmarkMode
- iso
- build.sh
- MetalAccelerator.mm
- isolyn-lab
- Options
- XCTestCase
- EvaluationWeights
- Dealer.cpp
- CalibrationTests
- Determinizer::sample
- GestureArbiter
- build.sh
- .automaticMove
- Dealer
- buildSnapshot
- GestureArbiter
- build.sh
- CenteredContent
- ComingSoonView
- BlockingHeuristic::score
- RoundOutcome
- DrawFlightView
- CommandOutcome

## God Nodes (most connected - your core abstractions)
1. `GameState` - 76 edges
2. `DominoTile` - 64 edges
3. `GameViewModel` - 57 edges
4. `Tile` - 54 edges
5. `SESSION: ENGINE/SEARCH/EVALUATION OVERHAUL + METAL BATCH EVALUATOR (2026-11-11)` - 52 edges
6. `LabService` - 46 edges
7. `SwiftUI` - 41 edges
8. `InteractiveGameBoardView` - 35 edges
9. `SearchContext` - 35 edges
10. `Color` - 34 edges

## Surprising Connections (you probably didn't know these)
- `bridge_match_record_round()` --calls--> `handValue()`  [INFERRED]
  Sources/IsolynEngineBridge/IsolynBridge.cpp → Accelerator/shaders/evaluation.metal
- `HandTapRouterTests` --calls--> `Tile`  [INFERRED]
  Tests/IsolynAppTests/HandTapRouterTests.swift → Sources/IsolynApp/Engine/EngineTypes.swift
- `main()` --calls--> `isTracked`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `probability`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `totalProbabilityMass`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp

## Import Cycles
- None detected.

## Communities (168 total, 22 thin omitted)

### Community 0 - "Appearance"
Cohesion: 0.04
Nodes (48): 0. Design correction — Offsuit-minimal (2026-11-12), 10. Implementation phases, 11. Acceptance criteria, 12. Risks and boundaries, 13. Immediate next slice, 1. Verdict, 2. What exists today, 3. Product direction: The Table (+40 more)

### Community 2 - "Root Docs"
Cohesion: 0.09
Nodes (25): Darwin, pid_t, Process, Handle, LabProcessHandle, LabService, Phase, failed (+17 more)

### Community 3 - "Hoverchain"
Cohesion: 0.06
Nodes (34): 1a. F‑04 — EnvironmentManager / LiveWeatherService race closure, 1b. F‑10 — Cancel-on-abandon for analyses, 1c. F‑11 — BeliefState divide-by-zero guard (ENGINE CHANGE — test-first, house rule #5), 2a. F‑07 — Truthful failure for unknown analysis handles, 2b. F‑08 — Observable divergence on unknown DTO enums, 2c. F‑12 — HandleTable comment truthing, 3a. CI pipeline, 3b. Full sanitizer baseline (post-fix code) (+26 more)

### Community 4 - "Include"
Cohesion: 0.10
Nodes (24): Alignment, Binding, Font, EnvironmentView, LegibilityScrim, LabRunDetailView, LabRunRow, LabRunsView (+16 more)

### Community 5 - "Isolynapptests"
Cohesion: 0.09
Nodes (23): kKillerSlots, kMaxHistoryPlayers, kMoveCodeCount, uint64_t, unordered_map, SearchContext, aborted, cancelRequested (+15 more)

### Community 6 - "Include"
Cohesion: 0.16
Nodes (5): vector, array, map, deque, main()

### Community 7 - "Root Docs"
Cohesion: 0.10
Nodes (17): GraphicsContext, RandomNumberGenerator, StarFieldView, Int, UInt64, CGSize, Double, WeatherEffectView (+9 more)

### Community 8 - "Isolynenginebridge"
Cohesion: 0.19
Nodes (24): CommandResultDTO, decidingPlayerIndex, diagnosticMessage, newStateVersion, roundOutcome, status, RoundOutcomeDTO, advanceStateVersion() (+16 more)

### Community 9 - "Game"
Cohesion: 0.14
Nodes (13): DrawEvent, GameViewModel, Bool, Int, MatchFormat, Move, Never, RoundOutcome (+5 more)

### Community 10 - "Environment"
Cohesion: 0.11
Nodes (16): CLLocation, CoreLocation, previewManager(), Int, LiveWeatherService, SkyCondition, clear, cloudy (+8 more)

### Community 11 - "Isolynenginebridge"
Cohesion: 0.08
Nodes (26): AnalysisSnapshotImpl, belief, believerPlayerIndex, cancelRequested, mode, stateVersionAnalyzed, world, atomic (+18 more)

### Community 12 - "Include"
Cohesion: 0.15
Nodes (31): _atomic_json(), build_parser(), _check_run_id(), _command(), _count_rows(), _csv_complete(), _default_run_id(), _execute() (+23 more)

### Community 14 - "Game"
Cohesion: 0.11
Nodes (15): GeometryProxy, BoardFrameKey, HandDragModel, HandDragPreview, InteractiveGameBoardView, SeatItem, Bool, CGFloat (+7 more)

### Community 15 - "Include"
Cohesion: 0.05
Nodes (40): int8_t, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map, vector, Chain::fromKnownState() (+32 more)

### Community 16 - "Isolynengine"
Cohesion: 0.08
Nodes (30): GameMode, vector, encodePositionBatch(), GameState, drawTile, hash, m_boneyard, m_chain (+22 more)

### Community 17 - "Include"
Cohesion: 0.57
Nodes (7): bridge_match_begin(), bridge_session_create_first_round(), bridge_session_create_subsequent_round(), ChainSideDTO, GameModeDTO, isValidMode(), toEngine()

### Community 18 - "Engine"
Cohesion: 0.13
Nodes (35): MoveExecutor, apply, undo, generate, generateInto, MoveValidator, isLegal, Move (+27 more)

### Community 19 - "Include"
Cohesion: 0.09
Nodes (24): BeliefState::applyOpponentDraw(), BeliefState::totalProbabilityMass(), map, mt19937_64, pair, vector, Determinizer::sample(), BeliefState (+16 more)

### Community 20 - "Include"
Cohesion: 0.09
Nodes (24): GameModeDTO, SnapshotDTO, boneyardDrawableCount, boneyardLockedCount, boneyardLockedTiles, chain, currentPlayerIndex, decidingPlayerIndex (+16 more)

### Community 21 - "Include"
Cohesion: 0.24
Nodes (9): Tile, CGPoint, CGRect, Move, HandTileFramesKey, CGRect, HandDropResolverTests, Int (+1 more)

### Community 22 - "Engine"
Cohesion: 0.14
Nodes (20): Element, os, Sendable, AnalysisOutcome, GameSnapshot, MatchFormat, MatchOutcome, Move (+12 more)

### Community 23 - "Include"
Cohesion: 0.10
Nodes (21): AnalysisResultDTO, completed, expectedValuePerPlayer, isDraw, playerCount, recommendedMove, samplesCompleted, samplesConfigured (+13 more)

### Community 24 - "Root Docs"
Cohesion: 0.33
Nodes (6): size_t, vector, PositionBatch, playerCount, rows, PositionRow

### Community 25 - "Components"
Cohesion: 0.06
Nodes (37): ChainSide, left, right, BoardDropTargetFrames, ChainAndZonesView, EndEdgeHighlight, EndTarget, GameSurfaceCoordinateSpace (+29 more)

### Community 26 - "Hoverchain"
Cohesion: 0.32
Nodes (4): Bool, Double, Int, TileKnowledgeResolver

### Community 27 - "Include"
Cohesion: 0.13
Nodes (15): GameMode, vector, ScoreSystem, applyRoundScores, hasMatchEnded, m_mode, m_scores, score (+7 more)

### Community 28 - "Include"
Cohesion: 0.18
Nodes (15): Chain, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles, placeLeft, placeOpening (+7 more)

### Community 29 - "Isolynenginetests"
Cohesion: 0.10
Nodes (31): fromKnownState, Determinizer, sample, DominoSet, shuffledTiles, ProbabilityEngine, constructFromGameState, expectedRemainingValue (+23 more)

### Community 30 - "Environment"
Cohesion: 0.16
Nodes (12): NSObjectProtocol, EnvironmentManager, Calendar, Int, Never, Task, Void, WeatherMode (+4 more)

### Community 31 - "Isolynapp"
Cohesion: 0.07
Nodes (27): 1a. Darwin RSS reader, 1b. Make "couldn't measure" loud instead of silently green, 1c. Verify the measurement is REAL before trusting it, 2a. Extract pure layout metrics (testability first), 2b. Auto-fit scale (uniform ⇒ the 2:1 law survives), 2c. Content-aware camera bounds, 2d. The GameSnapshot TEST SEAM (shared infrastructure with Phase 3), 3a. Fix the math to match the claim (or the claim to match the math — math wins) (+19 more)

### Community 32 - "Engine"
Cohesion: 0.25
Nodes (4): AIOpponentTests, GameViewModelTests, Bool, XCTestCase

### Community 33 - "Isolynengine"
Cohesion: 0.29
Nodes (6): AppearanceKeyframe, EnvironmentAppearance, EnvironmentAppearanceCurve, EnvironmentColor, Double, EnvironmentAppearanceCurveTests

### Community 34 - "Isolynengine"
Cohesion: 0.16
Nodes (12): OpeningDecision, openingPlayerIndex, openingTile, GameMode, pair, vector, RulesEngine::computeRoundScores(), RulesEngine::determineCloser() (+4 more)

### Community 35 - "Include"
Cohesion: 0.13
Nodes (14): AnyObject, Notification, NSApplication, NSApplicationDelegate, NSObject, IsolynAppDelegate, NSWindow, RestorableWindow (+6 more)

### Community 36 - "Engine"
Cohesion: 0.15
Nodes (13): Error, BridgeError, boneyardEmpty, bridgeFailure, engineFailure, invalidMove, invalidRequest, noLegalMove (+5 more)

### Community 37 - "Isolynenginebridgetests"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 38 - "Environment"
Cohesion: 0.15
Nodes (11): EnvironmentState, Date, Double, String, Double, TimePhase, afternoon, morning (+3 more)

### Community 39 - "Include"
Cohesion: 0.14
Nodes (23): GameMode, MatchController, advanceToNextPlayer, canVoluntaryDraw, checkForClose, currentPlayerHasLegalMove, dealFirstRound, dealSubsequentRound (+15 more)

### Community 40 - "Root Docs"
Cohesion: 0.13
Nodes (16): LabEstimator, LabWorkloadEstimate, Level, extreme, heavy, light, moderate, Bool (+8 more)

### Community 41 - "Environment"
Cohesion: 0.08
Nodes (26): E-001 — Parallel root determinization, E-002 — Validity control: parallel 20 vs sequential 20, E-003 — Parallel 64 vs sequential 20 (underpowered), E-004 — Parallel 64 vs sequential 20 (resolved), E-005 — Ladder re-measurement (baseline correction), E-006 — Smaller per-lane transposition-table reserve (rejected), E-007 — Sample-count saturation at depth 4, E-008 — Beyond saturation (confirmation) (+18 more)

### Community 42 - "Appearance"
Cohesion: 0.04
Nodes (51): ENGINE-01 — Search, terminal scoring, evaluation, difficulty, and AI mode, METAL-01 — Standalone Metal batch evaluator, METAL-02 — face-mask kernel optimization (2026-11-11), OPS-10 — Closeout Initiative, OPS-11 — Closeout Initiative (2026-11-13: documentation audit, tree reorganisation, gate execution), OPS-12 — Closeout Initiative (2026-11-14: Overdrive closeout, graph refresh, push), OPS-12a — Correction to OPS-12 (same session, 2026-11-14), OPS-12b — CI root cause identified: account billing, not code (2026-11-14) (+43 more)

### Community 43 - "Include"
Cohesion: 0.17
Nodes (12): Boneyard::Boneyard(), Boneyard::drawNext(), Boneyard::lockedTiles(), Boneyard::undoDraw(), vector, Boneyard, drawNext, lockedTiles (+4 more)

### Community 44 - "Isolynengine"
Cohesion: 0.11
Nodes (16): Context, NSEvent, NSPoint, NSView, NSViewRepresentable, Coordinator, InspectionEventMonitor, InspectionMouseButton (+8 more)

### Community 45 - "Include"
Cohesion: 0.12
Nodes (17): App, Scene, AppState, IsolynApp, LabAnalysisService, Date, Int32, String (+9 more)

### Community 46 - "Include"
Cohesion: 0.08
Nodes (24): 10. HAND ORDER AND VISUAL CONSISTENCY, 11. TOP HEADER, 12. SCORE DISPLAY, 13. "DRAW" AND "ANALYZE", 14. INSTRUCTIONS, 15. REMOVE DEBUG-STYLE VISUAL LANGUAGE, 16. SPACING SYSTEM, 17. RESPONSIVE BEHAVIOR (+16 more)

### Community 47 - "SamplePool"
Cohesion: 0.14
Nodes (13): condition_variable, function, mutex, SamplePool, m_done, m_generation, m_mutex, m_remaining (+5 more)

### Community 48 - "Root Docs"
Cohesion: 0.23
Nodes (6): HoverChainController, Int, Never, Task, UInt64, Void

### Community 49 - "Game"
Cohesion: 0.09
Nodes (23): 4. Per-document findings, A10. `design/UI_CHARTER.md` (was `UI_UX_OVERHAUL.md`), A11. `subsystems/ACCELERATOR.md`, A12. `subsystems/LAB.md`, A13. `roadmaps/strategy-roadmap.md`, A14. `audits/2026-08-24-audit.md`, A15. `audits/2026-11-13-audit.md`, A16. `history/2026-08-ui-rebuild-mandate.md` (was `design/ui-fix-directive.md`) (+15 more)

### Community 50 - "Include"
Cohesion: 0.10
Nodes (19): 1. EXECUTIVE SUMMARY, 2. ARCHITECTURE MAP, 3. DEAD CODE REPORT, 4. FINDINGS TABLE, 5. SCALABILITY VERDICT, 6. PRIORITIZED REMEDIATION PLAN, 7. WHAT'S GOOD, 8. SINGLE HIGHEST-LEVERAGE NEXT ACTION (+11 more)

### Community 51 - "Isolynenginebridge"
Cohesion: 0.10
Nodes (19): 1v1 Strategy — Look-Ahead Depth and Tile-Counting Reasoning, 1v1 Strategy — Skill Gap, Boneyard Draining, Score-Driven Playstyle, and Elite Tactics, 2v2 Strategy — Partner Communication and Coordination, Both decisions are estimation-driven, not rule-driven, Claimed look-ahead depth at high-level play, Closing is sometimes chosen over a visible Domino path, Definition: "missing a set", Draining the entire boneyard: a real, high-variance, high-skill tactic (+11 more)

### Community 52 - "Isolynengine"
Cohesion: 0.11
Nodes (19): FIX‑01 — Swift test target could not build at all, FIX‑02 — Engine/bridge scripts failed to link on macOS, FIX‑03 — Bridge test harness assumed GNU coreutils, FIX‑04 — SmokeTest deal-randomness flake, part A (blocked-player assumption), FIX‑05 — SmokeTest flake part B (helper spun forever in boneyard-less modes), FIX‑06 — libFuzzer runtime absent from Xcode 26 toolchain (infrastructure), FIX‑07 — Terminal-round guard (audit F‑03): play could continue past a finished round, FIX‑08 — ScoreSystem lacked participant-count accessor (additive) (+11 more)

### Community 53 - "Root Docs"
Cohesion: 0.17
Nodes (14): IsolynDominoTile, Bool, CGFloat, CGPoint, CGSize, Int, TileOrientation, horizontal (+6 more)

### Community 54 - "EnvironmentClock"
Cohesion: 0.18
Nodes (9): EnvironmentClock, FixedEnvironmentClock, Date, SystemEnvironmentClock, RandomWeatherService, Double, Int, String (+1 more)

### Community 55 - "Include"
Cohesion: 0.12
Nodes (16): array, size_t, uint8_t, RawEvaluation, count, values, SearchValue, raw (+8 more)

### Community 56 - "Include"
Cohesion: 0.11
Nodes (25): AnalysisHandle, Impl, MatchHandle, shared_ptr, bridge_analysis_request_cancel(), bridge_analysis_run(), bridge_analysis_snapshot_create(), bridge_analysis_snapshot_destroy() (+17 more)

### Community 57 - "Include"
Cohesion: 0.12
Nodes (16): 1. WHAT THIS PROJECT IS (plain words), 2. SCOREBOARD — 2026-08 SNAPSHOT (§6 re-proves the 2026-08 gates), 3. FOLDER MAP (every item, one line each), 4. THE LAST BIG SESSION — WHAT / WHY / HOW / WHERE, 5.1 Governing documents (authority order — still binding), 5.2 The sandbox-loss lesson (why "commit often" is house law), 5.3 The twelve ambiguity resolutions (numbering = load-bearing), 5.4 Engine rigor status (stated plainly — do NOT "fix" these) (+8 more)

### Community 58 - "Root Docs"
Cohesion: 0.09
Nodes (28): CaseIterable, CodingKey, Decoder, CodingKeys, config, createdAt, runId, shards (+20 more)

### Community 59 - "Environment"
Cohesion: 0.06
Nodes (36): Backend, capabilities, evaluate, BatchView, featureCount, features, playerCount, positionCount (+28 more)

### Community 60 - "ISOLYN IMPLEMENTATION ROADMAP"
Cohesion: 0.12
Nodes (17): 0. HOW TO READ THE PERCENTAGES, 1a. Version control + verification harness repair *(small, blocking everything)*, 1b. Terminal-round guard (F‑03) — the highest-severity unfixed bug, 1c. Match orchestration — the keystone design *(bulk of the phase)*, DEPENDENCY GRAPH (why this order and no other), EFFORT SUMMARY TABLE, FIRST THREE ACTIONS WHEN WORK BEGINS, ISOLYN IMPLEMENTATION ROADMAP (+9 more)

### Community 61 - "Include"
Cohesion: 0.09
Nodes (25): Hashable, HoverChain, HoverChainEntry, HoverChainNodeKind, baseUninformed, complete, historicalInformed, lockedOff (+17 more)

### Community 62 - "Components"
Cohesion: 0.12
Nodes (16): 10. Documentation claims verification, 11. Security and reliability assessment, 14. Technical debt and architectural weaknesses, 15. Implemented strengths, 16. Missing, incomplete and broken functionality, 18. Development history and timeline, 1. Executive summary, 20. Critical priorities and recommended actions (+8 more)

### Community 63 - "Components"
Cohesion: 0.15
Nodes (6): AppearanceManager, Double, String, Color, Double, ColorMathTests

### Community 64 - "Views"
Cohesion: 0.23
Nodes (10): HandRackView, Bool, CGFloat, CGPoint, CGSize, Gesture, Move, Set (+2 more)

### Community 65 - "Isolynengine"
Cohesion: 0.19
Nodes (8): FakeHandle, FakeLauncher, LabServiceTests, Int, Int32, String, URL, Void

### Community 66 - "Include"
Cohesion: 0.14
Nodes (14): FIX‑15 — EnvironmentManager weather race (audit F‑04), FIX‑16 — Cancel-on-abandon for analyses (audit F‑10), FIX‑17 — BeliefState.applyOpponentDraw totality (audit F‑11), FIX‑18 — Unknown analysis handle reports truthfully (audit F‑07), FIX‑19 — Observable enum divergence + HandleTable truthing (audits F‑08/F‑12), FIX‑20 — CI pipeline (roadmap P3a / audit remediation-plan item 10), FIX‑21 — Hue slider black-tile bug (NEW finding N-1), FIX‑22..25 — Appearance honesty + mechanical sweep (roadmap P4) (+6 more)

### Community 67 - "Root Docs"
Cohesion: 0.15
Nodes (12): Architecture, Backend rules, Build and run, Contracts, Correctness gates, Decision, Files, Integration plan (+4 more)

### Community 68 - "Root Docs"
Cohesion: 0.14
Nodes (13): App integration (2026-11-14), Boundary, Components, Data contracts, `lab/` — Python lab, Measured baseline (2026-11-11), Milestones, Non-goals (+5 more)

### Community 70 - "Isolynengine"
Cohesion: 0.11
Nodes (17): ButtonStyle, PreferenceKey, PrimaryCapsuleButtonStyle, CGFloat, Configuration, View, BoneyardAnchorKey, BoneyardFaceDownTile (+9 more)

### Community 71 - "Include"
Cohesion: 0.09
Nodes (21): config, depth, determinizations, games, games_per_shard, mode, opponent_depth, opponent_determinizations (+13 more)

### Community 72 - "Isolynenginebridgetests"
Cohesion: 0.15
Nodes (16): LabCard, LabLink, LabSectionTitle, LabStatusPill, Bool, Content, String, View (+8 more)

### Community 73 - "Root Docs"
Cohesion: 0.17
Nodes (12): Bridge Architecture, Cancellation, Error model, Explicitly out of scope, Match orchestration (added Phase 1), Ownership: handles, not pointers, Snapshot model — hidden information, State versioning (+4 more)

### Community 74 - "Root Docs"
Cohesion: 0.18
Nodes (8): ModeCard, ModeOption, Bool, String, Void, ModeSelectorView, CGFloat, String

### Community 77 - "Root Docs"
Cohesion: 0.12
Nodes (17): 0. Provenance, 1. How a rule binds, 2. Vocabulary, 3. The rules, A. Winning a hand and scoring it, B. Dealing and opening, C. Drawing, D. Scoring a hand (+9 more)

### Community 78 - "Root Docs"
Cohesion: 0.35
Nodes (4): Move, UInt64, CommandOutcome, UInt64

### Community 79 - "Root Docs"
Cohesion: 0.20
Nodes (9): 1. App shell, 2. Privacy manifest (`PrivacyInfo.xcprivacy`), 3. Usage-description strings (Info.plist), 4. Capabilities & entitlements, 5. Icon & assets, 6. Build, sign, notarize, 7. Pre-flight functional checks on the packaged app, Explicitly out of scope until after UI revival (+1 more)

### Community 80 - "ISOLYN RELEASE CHECKLIST"
Cohesion: 0.22
Nodes (9): 29. IMPLEMENTATION ORDER, Step 1 --- Replace the domino renderer, Step 2 --- Rebuild board layout, Step 3 --- Rebuild player hand, Step 4 --- Rebuild header/status, Step 5 --- Rebuild action area, Step 6 --- Responsive pass, Step 7 --- Interaction pass (+1 more)

### Community 81 - "Dealer::deal"
Cohesion: 0.20
Nodes (9): Ambition, Architecture, Build and run, Correctness gates, Files, IsolynV2.0 Metal Accelerator, Measured throughput, Non-goals (+1 more)

### Community 82 - "29. IMPLEMENTATION ORDER"
Cohesion: 0.22
Nodes (8): FIX-27 - SoakTest measures RSS on macOS; sanitizer sweep de-confounded (audit OA-1), FIX-28 - Board layout truth + auto-fit resilience + snapshot test seam; FOUND+FIXED latent off-board snake bug (audit OA-4), SESSION: AUDIT REMEDIATION (2026-08-25, owner-approved Phases 0-2 of `docs/history/roadmaps/audit-remediation-roadmap.md`), UI‑01 — Canonical single-rectangle renderer (§2/§3 — THE core law), UI‑02 — Snake-chain board (§4–§8), UI‑03 — Real hand + screen chrome (§9–§14, §28), UI‑QA — OWNER VISUAL SIGN-OFF, UI REBUILD — docs/history/2026-08-ui-rebuild-mandate.md EXECUTED

### Community 83 - "Feature Specifications — Training Mode and Sandbox Mode"
Cohesion: 0.22
Nodes (8): Measured throughput (this machine, 2026-11-14), Metal Integration — Audit, Measurements and Verdict, Non-goals, The number that decides it, Verdict, Verified state of the production path, What a real search actually needs, What exists

### Community 84 - "SearchDecision"
Cohesion: 0.15
Nodes (13): Move, uint64_t, vector, SearchDecision, completed, depthReached, exactEndgame, expectedValuePerPlayer (+5 more)

### Community 85 - "26. EXACT INFORMATION HIERARCHY"
Cohesion: 0.22
Nodes (9): Charter, Current champion, ⛔ Everything above this line is VOID, Limitations of the current evidence, Missing action: voluntary draw, Next actions, in order, Project Overdrive — Research Journal (VOID), Standing method (+1 more)

### Community 86 - "THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT."
Cohesion: 0.14
Nodes (16): GameMode, EvaluationEngine::evaluateAll(), EvaluationEngine::evaluateAllWithClosed(), EvaluationTotals, playerCount, totals, EvaluationWeights, blocking (+8 more)

### Community 87 - "30. ACCEPTANCE CRITERIA"
Cohesion: 0.25
Nodes (7): Correct-move handling, Cross-cutting implications worth flagging now, Feature Specifications — Training Mode and Sandbox Mode, Sandbox Mode, Training Mode, Visual design, Wrong-move handling

### Community 88 - "EnvironmentTests.swift"
Cohesion: 0.22
Nodes (17): ofstream, ostream, RootAggregation, applyWeightList(), string, string_view, uint64_t, main() (+9 more)

### Community 89 - "3. DOMINO TILE SPECIFICATION"
Cohesion: 0.25
Nodes (7): 1. Authority model, 2. Verdict register, 3. Contradiction register, 5. Numeric claim verification, 6. What changed in this pass, 7. Residual risks, Documentation Audit — 2026-11-13

### Community 90 - "DealResult"
Cohesion: 0.11
Nodes (28): EvalParams, componentCount, playerCount, positionCount, EvalPositionParams, playerCount, positionCount, handValue() (+20 more)

### Community 91 - "RoundOutcome"
Cohesion: 0.08
Nodes (27): Equatable, Int, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, Screen, comingSoon (+19 more)

### Community 92 - "4. BOARD MUST LOOK LIKE A DOMINO BOARD"
Cohesion: 0.25
Nodes (8): Benchmark Baseline (VOID), Environment, ⛔ Everything above this line is VOID, Game shape, Measured 1v1 ladder (seed 42, alternating seats, no time cap), Other modes (seed 42, 500 games each, 2/8 vs 5/40), Reference configurations, Timing

### Community 93 - "9. PLAYER HAND"
Cohesion: 0.29
Nodes (6): Components and LOC, IsolynV2.0 Project Inventory, Naming boundary, Relevant callers, Repository layout, Where new code belongs

### Community 94 - "DOMINOES UI FIX --- NON-NEGOTIABLE REBUILD MANDATE"
Cohesion: 0.29
Nodes (6): Bridge Testing, Current verification matrix, Environment, Historical findings, Not covered, What the bridge suite covers

### Community 96 - "README.md"
Cohesion: 0.33
Nodes (6): Architecture, Documentation, IsolynV2.0, Project identity, Run, Status

### Community 97 - "IsolynV2.0 — Open Decisions & Architecture Records"
Cohesion: 0.16
Nodes (6): ADR-001 — Product languages: C++20 + Swift; Python offline only, ADR-002 — Offline lab and trainer, ADR-003 — Metal accelerator is a first-class backend, ADR-004 — One source of game truth, IsolynV2.0 — Open Decisions & Architecture Records, Open questions

### Community 98 - "tree.md"
Cohesion: 0.29
Nodes (7): Authority model, Claim → evidence, Conventions, IsolynV2.0 — Documentation, Read in this order, Register, Related

### Community 99 - "Audit Remediation Roadmap"
Cohesion: 0.33
Nodes (6): 17.1 Code implementation completeness — 72%, 17.2 Functional completeness — 71%, 17.3 Testing and validation coverage — 52%, 17.4 Production readiness — 15%, 17.5 Domain sub-rubrics, 17. Quantitative scoring methodology

### Community 100 - "GameSnapshot Test Seam (internal init)"
Cohesion: 0.33
Nodes (6): 19. Remaining development roadmap, Phase 1 — Critical deficiencies (blocking), Phase 2 — Core implementation, Phase 3 — Application completion, Phase 4 — Quality and stabilisation, Phase 5 — Production readiness

### Community 101 - "OA-1: macOS Soak Test Is a Silent No-Op"
Cohesion: 0.33
Nodes (6): 26. EXACT INFORMATION HIERARCHY, Priority 1, Priority 2, Priority 3, Priority 4, Priority 5

### Community 102 - "OA-4: Long Chains Exceed Board/Camera Bounds"
Cohesion: 0.33
Nodes (6): 2. ABSOLUTE RULE: DOMINOES ARE SINGLE RECTANGLES, Acceptance test, Forbidden implementation, Required geometry, Required implementation model, THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.

### Community 103 - "OA-5: Open Decisions (Ambiguity #6/#8, Approximation, Weights)"
Cohesion: 0.33
Nodes (6): 30. ACCEPTANCE CRITERIA, Board, Domino construction, Hand, Layout, Quality

### Community 104 - "Core Hardening Roadmap"
Cohesion: 0.60
Nodes (3): DateFormatter, EnvironmentTimeLabel, String

### Community 105 - "Swift/C++ Bridge (POD-Only Safety Wall)"
Cohesion: 0.40
Nodes (5): 6.1 Evaluation criteria, declared before scoring, 6.2 What the engine genuinely supports, 6.3 What the engine does not support, 6.4 Measured engine strength, 6. Core engine capability assessment

### Community 106 - "Bridge Architecture (Design Doc)"
Cohesion: 0.40
Nodes (5): 3. DOMINO TILE SPECIFICATION, Base tile, Center divider, Pips, Tile silhouette

### Community 107 - "Match Orchestration Surface (bridge_match_*)"
Cohesion: 0.60
Nodes (4): all_docs(), main(), Path, strip_fences()

### Community 108 - "Two-Phase Analysis Design"
Cohesion: 0.23
Nodes (9): GestureArbiter, GestureOwner, boardPan, dominoDrag, idle, pending, Bool, CGFloat (+1 more)

### Community 109 - "Blocked-Current-Player Analysis UB (Fuzz-Found)"
Cohesion: 0.33
Nodes (4): FileManager, LabPaths, Bool, URL

### Community 110 - "Bridge Testing (Verification Record)"
Cohesion: 0.19
Nodes (6): PipGlyph, CGFloat, Int, ComingSoonView, String, Void

### Community 111 - "Adversarial-Input Fuzz Campaign (FuzzBridge.cpp)"
Cohesion: 0.50
Nodes (4): 13.1 Executed in this audit, 13.2 Coverage by layer, 13.3 Weaknesses, 13. Testing and quality assurance assessment

### Community 112 - "No Swift Toolchain Available (Linux Sandbox)"
Cohesion: 0.50
Nodes (4): 4.1 Measured scale, 4.2 Documentation inventory, 4.3 Undocumented and disconnected artefacts, 4. Repository and documentation inspection

### Community 113 - "DifficultyModel (Not Yet Built)"
Cohesion: 0.50
Nodes (4): 5.1 What the architecture actually is, 5.2 What is strong, with evidence, 5.3 Architectural weaknesses, 5. Technical architecture review

### Community 114 - "Feature Specifications (Training & Sandbox)"
Cohesion: 0.50
Nodes (4): 7.1 Design strengths, 7.2 CRITICAL — verified out-of-bounds read and release segfault, 7.3 Other backend findings, 7. Backend assessment

### Community 116 - "PositionConstructor (Not Yet Built)"
Cohesion: 0.14
Nodes (13): 0. Authority, in strict order, 10. Standing engineering rules, 11. Current state (update at each closeout), 1. The "Closeout Initiative" trigger, 2. The verification commands (run all of them, capture literal output), 3. Step 1 — deep analysis of this session's work, 4. Step 2 — cleanup, allowlist only, 5. Step 3 — documentation updates, evidence-backed (+5 more)

### Community 117 - "Release Checklist"
Cohesion: 0.26
Nodes (6): HorizontalAlignment, LabAnalysisView, Int, Set, String, URL

### Community 118 - "Closing vs Domino-Run Decision (Estimation-Driven)"
Cohesion: 0.67
Nodes (3): 12.1 Measured, 12.2 Structural issues, 12. Performance and scalability assessment

### Community 119 - "Strategy Notes (Domain Knowledge for Engine Contributors)"
Cohesion: 0.67
Nodes (3): 8.1 What exists, 8.2 Findings, 8. Frontend and UI/UX assessment

### Community 121 - "1v1 Look-Ahead Depth (5–7 Moves)"
Cohesion: 0.20
Nodes (9): Alternatives, for when Kaggle is the wrong shape, First step — one session, one day, Kaggle Bridge — Free Cloud Compute for the Offline Lab, Risks worth stating plainly, The arithmetic, The bridge, in five pieces, Three blockers, verified in this tree, What Kaggle provides (verified) (+1 more)

### Community 128 - "EvaluationBreakdown"
Cohesion: 0.20
Nodes (10): EvaluationBreakdown, blocking, closingOpportunity, expectedValue, mobility, pipControl, teamSupport, tempo (+2 more)

### Community 129 - "STRENGTH_BASELINE.md"
Cohesion: 0.22
Nodes (5): Protocol for any number recorded here, Results, Strength Baseline — the only home for playing-strength claims, The tomorrow run — plan before games, What changed, and why the old numbers do not transfer

### Community 130 - ".record"
Cohesion: 0.29
Nodes (5): LayoutProbe, Bool, CGFloat, CGSize, Int

### Community 131 - "rules_audit.py"
Cohesion: 0.47
Nodes (5): anchor_of(), cells(), main(), Split a markdown table row into its cells., Interpret `path :: section` as (path, section).

### Community 132 - "OPS-27 — Analyses in the app, and the opponent default they exposed"
Cohesion: 0.40
Nodes (5): Analyses, Evidence (literal), OPS-27 — Analyses in the app, and the opponent default they exposed, Technical but friendly, The finding

### Community 133 - "DifficultyProfileDTO"
Cohesion: 0.40
Nodes (5): DifficultyProfileDTO, determinizationCount, maxDepthPlies, strength, bridge_difficulty_profile()

### Community 134 - "createFirstRound"
Cohesion: 0.60
Nodes (5): GameMode, mt19937_64, vector, createFirstRound(), dealSeeded()

### Community 135 - "lab"
Cohesion: 0.50
Nodes (3): lab script, PYTHONDONTWRITEBYTECODE, PYTHONPATH

### Community 145 - "Isolyn Offline Lab (scaffold)"
Cohesion: 0.22
Nodes (8): Boundary, IsolynV2.0 Offline Lab, Large runs (resumable), Layout, Non-goals, Planned milestones, Quick start, Related decisions

### Community 149 - "Isolyn Self-Play Harness (scaffold)"
Cohesion: 0.33
Nodes (5): Build and run, CSV fields, IsolynV2.0 Self-Play Generator, Modes, What it deliberately does not do yet

### Community 150 - "ComingSoonView"
Cohesion: 0.14
Nodes (14): RoundOutcomeKind, GameSummary, aDepth, aDeterminizations, bDepth, bDeterminizations, decidingPlayer, decisions (+6 more)

### Community 152 - "Move"
Cohesion: 0.11
Nodes (18): Options, aggregation, depth, determinizations, games, mode, opponentAggregation, opponentDepth (+10 more)

### Community 153 - "build_parser"
Cohesion: 0.07
Nodes (47): Counter, analyze(), CalibrationReport, elo_from_score(), elo_interval(), participant_label(), ParticipantStats, _rank() (+39 more)

### Community 154 - "DominoTile.cpp"
Cohesion: 0.18
Nodes (11): MoveRow, depthReached, evaluation, exactEndgame, moveIndex, nodes, player, side (+3 more)

### Community 155 - "benchmarkMode"
Cohesion: 0.09
Nodes (29): EvaluationBatch, componentCount, features, playerCount, positionCount, size_t, GameMode, vector (+21 more)

### Community 158 - "MetalAccelerator.mm"
Cohesion: 0.20
Nodes (9): DifficultyModel, kMaxStrength, kMinStrength, kProfiles, DifficultyProfile, determinizationCount, maxDepthPlies, strength (+1 more)

### Community 160 - "Options"
Cohesion: 0.11
Nodes (26): GameMode, vector, Dealer::deal(), Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode(), Dealer (+18 more)

### Community 161 - "XCTestCase"
Cohesion: 0.12
Nodes (17): ColorEditorRow, DominoAppearanceSection, HueSlider, InspectionSection, SettingsDrawer, Bool, CGFloat, Double (+9 more)

### Community 162 - "EvaluationWeights"
Cohesion: 0.10
Nodes (36): optional, evaluateAllImpl(), EvaluationEngine::evaluate(), HandFacts, legalMoves, value, handValueOf(), teamMobility() (+28 more)

### Community 163 - "Dealer.cpp"
Cohesion: 0.33
Nodes (3): BoneyardRulesTests, MatchFormat, RoundRevealTests

### Community 166 - "Determinizer::sample"
Cohesion: 0.10
Nodes (18): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles(), size_t, uint64_t, uint8_t (+10 more)

### Community 168 - "GestureArbiter"
Cohesion: 0.22
Nodes (5): MatchCoordinator, Bool, Int, isolyn, MatchFormat

### Community 172 - ".automaticMove"
Cohesion: 0.25
Nodes (4): HandTapRouter, Bool, Move, HandTapRouterTests

### Community 173 - "Dealer"
Cohesion: 0.45
Nodes (10): Decodable, Identifiable, LabAnalysisReport, LabEloReport, LabParticipantReport, LabSearchConfig, LabSpearmanReport, Bool (+2 more)

### Community 175 - "buildSnapshot"
Cohesion: 0.13
Nodes (18): ChainDTO, count, leftEnd, rightEnd, tiles, ChainSideDTO, LegalMovesDTO, count (+10 more)

### Community 177 - "GestureArbiter"
Cohesion: 0.07
Nodes (18): AppKit, CoreGraphics, Foundation, IsolynApp, IsolynEngineBridge, Observation, RootView, AtmosphericBackgroundView (+10 more)

### Community 179 - "CenteredContent"
Cohesion: 0.25
Nodes (5): CenteredContent, IsolynLayout, CGFloat, Content, ResponsiveLayoutTests

### Community 180 - "ComingSoonView"
Cohesion: 0.24
Nodes (10): BlockingHeuristic::score(), hasImmediateDominoWin(), size_t, MoveGenerator, countLegalMoves, hasAnyLegalMove, vector, MatchController::currentPlayerHasLegalMove() (+2 more)

### Community 181 - "BlockingHeuristic::score"
Cohesion: 0.13
Nodes (13): AppliedMove, kind, move, playerIndex, Move, PlacementKind, string, Move::describe() (+5 more)

### Community 184 - "RoundOutcome"
Cohesion: 0.50
Nodes (4): RoundOutcomeKind, RoundOutcome, decidingPlayerIndex, kind

### Community 187 - "DrawFlightView"
Cohesion: 0.10
Nodes (22): Codable, DominoAppearance, EdgeHighlightMode, none, standard, strong, subtle, RevealRow (+14 more)

### Community 188 - "CommandOutcome"
Cohesion: 0.16
Nodes (9): ObjectIdentifier, AnalysisTask, EngineSession, Error, Int, Int32, isolyn, MatchFormat (+1 more)

## Knowledge Gaps
- **959 isolated node(s):** `version`, `run_id`, `created_at`, `started_at`, `updated_at` (+954 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameState` connect `Isolynengine` to `Options`, `EvaluationWeights`, `Include`, `Include`, `Include`, `Isolynenginebridge`, `Include`, `Engine`, `Include`, `ComingSoonView`, `BlockingHeuristic::score`, `THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.`, `Include`, `Include`, `benchmarkMode`, `Include`, `Isolynenginetests`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Why does `DominoTile` connect `Include` to `Options`, `Isolynengine`, `Determinizer::sample`, `Include`, `Include`, `Isolynenginebridge`, `Include`, `Isolynengine`, `Include`, `Engine`, `Include`, `ComingSoonView`, `BlockingHeuristic::score`, `Include`, `Isolynenginetests`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **Why does `Tile` connect `Include` to `Views`, `Game`, `.automaticMove`, `DrawFlightView`, `Game`, `Engine`, `Components`, `Hoverchain`, `RoundOutcome`, `Include`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `GameState` (e.g. with `bridge_match_record_round()` and `buildSnapshot()`) actually correct?**
  _`GameState` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `GameViewModel` (e.g. with `.test_computer_plays_its_own_turn_without_human_input()` and `.test_computer_plays_two_v_two_partner_turn_without_stalling()`) actually correct?**
  _`GameViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `Tile` (e.g. with `.test_orient_flipsEachTileToTouchItsNeighbour()` and `.test_orient_marksDoubles()`) actually correct?**
  _`Tile` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `version`, `run_id`, `created_at` to the rest of the system?**
  _959 weakly-connected nodes found - possible documentation gaps or missing edges._