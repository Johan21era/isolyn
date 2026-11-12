# Graph Report - Isolyn-current_4  (2026-11-12)

## Corpus Check
- 195 files · ~149,690 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2232 nodes · 4182 edges · 185 communities (117 shown, 68 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 289 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c7153f0d`
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
- Isolynenginebridge
- Root Docs
- Game
- Include
- Isolynenginebridge
- Isolynengine
- Root Docs
- Game
- Include
- Include
- Include
- Root Docs
- Environment
- Root Docs
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
- .shutdown
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
- FIX-27: Darwin RSS Soak Truth + ASan Quarantine De-confound (OA-1)
- FIX-28: SnakeChainLayout + Latent Snake-Bug Fix (OA-4)
- Session: UI Rebuild (UI-01…UI-QA)
- F-02: run_tests.sh Link Failure on macOS
- F-03: No Terminal-State Guard in Bridge Mutators
- F-04: Weather Source Data Race
- F-05: No App Packaging Substrate
- F-11: applyOpponentDraw Divide-by-Zero (NDEBUG)
- Appendix C: Graph Trace Findings (F-T1…F-T5)
- Isolyn Implementation Roadmap
- MatchCoordinator Design (Math in Engine, Policy in Swift)
- Phase 1: Correctness Lock & Match Architecture
- Phase 3: DifficultyModel + AI Turns + Calibration
- Twelve Ambiguity Resolutions (Numbering Load-Bearing)
- Legacy Handoff (Read Me First)
- House Rules 1–8
- File Tree (tree.md)
- Isolyn Offline Lab (scaffold)
- Isolyn — Open Decisions & Architecture Records
- SimulationEngine::sampleDeterminizedState
- CommandResultDTO
- Isolyn Self-Play Harness (scaffold)
- ComingSoonView
- Boneyard.cpp
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
- TTEntry
- CalibrationTests
- Determinizer::sample
- .makeBody
- GestureArbiter
- buildAllTiles
- build.sh
- Dealer
- IsolynV2.0 Project Inventory
- buildSnapshot
- RoundEndOverlay
- GestureArbiter
- build.sh
- ComingSoonView
- BlockingHeuristic::score
- EnvironmentTimeLabel
- GestureArbiter
- RoundOutcome
- TTEntry
- DepthResult
- DrawFlightView

## God Nodes (most connected - your core abstractions)
1. `GameState` - 75 edges
2. `DominoTile` - 63 edges
3. `GameViewModel` - 56 edges
4. `Tile` - 53 edges
5. `View` - 52 edges
6. `SwiftUI` - 35 edges
7. `InteractiveGameBoardView` - 35 edges
8. `SearchContext` - 31 edges
9. `Color` - 29 edges
10. `Chain` - 29 edges

## Surprising Connections (you probably didn't know these)
- `Isolyn Current Audit (Markdown edition)` --semantically_similar_to--> `Isolyn Current Audit (PDF edition)`  [INFERRED] [semantically similar]
  isolyn current audit.md → isolyn current audit.pdf
- `main()` --calls--> `markTileKnown`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `applyOpponentDraw`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `undoPlayTile`  [INFERRED]
  Tests/IsolynEngineTests/GameStateTests.cpp → Sources/IsolynEngine/include/GameState.hpp
- `main()` --calls--> `undoDrawTile`  [INFERRED]
  Tests/IsolynEngineTests/GameStateTests.cpp → Sources/IsolynEngine/include/GameState.hpp

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Audit–Roadmap Governance Set** — isolyn_current_audit_document, core_hardening_roadmap_document, audit_remediation_roadmap_document, isolyn_roadmap_document [EXTRACTED 1.00]
- **Bridge Design ↔ Verification Trust Chain** — docs_bridge_architecture_document, docs_bridge_architecture_bridge, docs_bridge_testing_document, docs_bridge_testing_blocked_player_ub [EXTRACTED 1.00]
- **OA Remediation Executed as FIX-27/FIX-28** — audit_remediation_roadmap_oa_1_macos_soak_noop, audit_remediation_roadmap_oa_4_chain_board_bounds, fix_log_fix_27_soak_truth, fix_log_fix_28_board_layout [EXTRACTED 1.00]

## Communities (185 total, 68 thin omitted)

### Community 0 - "Appearance"
Cohesion: 0.13
Nodes (18): PipGlyph, CGFloat, Int, Color, IsolynDominoTile, Bool, CGFloat, CGPoint (+10 more)

### Community 1 - "Root Docs"
Cohesion: 0.67
Nodes (3): CI Pipeline (Phase 3a / OPS-04), F-02-Class Drift Structural Guard, CI Workflow (GitHub Actions macOS)

### Community 2 - "Root Docs"
Cohesion: 0.10
Nodes (19): ChainAndZonesView, EndEdgeHighlight, EndTarget, GameSurfaceCoordinateSpace, Metrics, Oriented, Placed, SnakeChainBoard (+11 more)

### Community 3 - "Hoverchain"
Cohesion: 0.16
Nodes (12): PredictivePolicy, Double, TileKnowledge, historical, lockedOff, mine, predictedOpponent, unknown (+4 more)

### Community 4 - "Include"
Cohesion: 0.18
Nodes (15): Int, HoverChain, HoverChainEntry, HoverChainNodeKind, baseUninformed, complete, historicalInformed, lockedOff (+7 more)

### Community 5 - "Isolynapptests"
Cohesion: 0.10
Nodes (22): kKillerSlots, kMaxHistoryPlayers, kMoveCodeCount, atomic, uint64_t, SearchContext, aborted, cancelRequested (+14 more)

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
Cohesion: 0.05
Nodes (34): ObjectIdentifier, AnalysisTask, EngineSession, Error, Int, Int32, isolyn, MatchFormat (+26 more)

### Community 10 - "Environment"
Cohesion: 0.11
Nodes (16): CLLocation, CoreLocation, previewManager(), Int, LiveWeatherService, SkyCondition, clear, cloudy (+8 more)

### Community 11 - "Isolynenginebridge"
Cohesion: 0.12
Nodes (17): mutex, GameMode, EngineSessionImpl, cachedDecidingPlayer, cachedRoundOutcome, controller, mode, mutex (+9 more)

### Community 12 - "Include"
Cohesion: 0.11
Nodes (19): EvaluationBatch, componentCount, features, playerCount, positionCount, size_t, GameMode, vector (+11 more)

### Community 13 - "Isolynapptests"
Cohesion: 0.21
Nodes (4): Calendar, Int, String, TimePhaseTests

### Community 14 - "Game"
Cohesion: 0.14
Nodes (10): ButtonStyle, Configuration, Font, PrimaryCapsuleButtonStyle, CGFloat, IsolynTheme, CGFloat, EntryView (+2 more)

### Community 15 - "Include"
Cohesion: 0.10
Nodes (16): int8_t, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map, vector, string (+8 more)

### Community 16 - "Isolynengine"
Cohesion: 0.07
Nodes (27): BlockingHeuristic::score(), ExpectedValueHeuristic::score(), GameState, hash, m_boneyard, m_chain, m_currentPlayerIndex, m_hands (+19 more)

### Community 17 - "Include"
Cohesion: 0.18
Nodes (16): AnalysisHandle, MatchHandle, bridge_analysis_request_cancel(), bridge_analysis_run(), bridge_analysis_snapshot_create(), bridge_analysis_snapshot_destroy(), bridge_match_close(), bridge_match_record_round() (+8 more)

### Community 18 - "Engine"
Cohesion: 0.19
Nodes (14): Determinizer, sample, DominoSet, shuffledTiles, mt19937_64, SimulationEngine::sampleDeterminizedState(), main(), main() (+6 more)

### Community 19 - "Include"
Cohesion: 0.15
Nodes (14): BeliefState::applyOpponentDraw(), BeliefState, applyOpponentDraw, kBoneyardLocation, m_distributions, m_tracked, markTileKnown, totalProbabilityMass (+6 more)

### Community 20 - "Include"
Cohesion: 0.09
Nodes (24): GameModeDTO, SnapshotDTO, boneyardDrawableCount, boneyardLockedCount, boneyardLockedTiles, chain, currentPlayerIndex, decidingPlayerIndex (+16 more)

### Community 21 - "Include"
Cohesion: 0.25
Nodes (10): CoreGraphics, Tile, HandDropResolver, CGFloat, CGPoint, CGRect, Move, HandDropResolverTests (+2 more)

### Community 22 - "Engine"
Cohesion: 0.11
Nodes (23): Element, Equatable, os, Sendable, AnalysisOutcome, GameSnapshot, MatchFormat, MatchOutcome (+15 more)

### Community 23 - "Include"
Cohesion: 0.11
Nodes (20): AnalysisResultDTO, completed, expectedValuePerPlayer, playerCount, recommendedMove, samplesCompleted, samplesConfigured, stateVersionAnalyzed (+12 more)

### Community 24 - "Root Docs"
Cohesion: 0.13
Nodes (22): size_t, vector, PositionBatch, playerCount, rows, GameMode, vector, encodePositionBatch() (+14 more)

### Community 25 - "Components"
Cohesion: 0.10
Nodes (19): AtmosphericBackgroundView, EnvironmentSettingsView, EnvironmentView, LegibilityScrim, ColorEditorRow, DominoAppearanceSection, HueSlider, InspectionSection (+11 more)

### Community 26 - "Hoverchain"
Cohesion: 0.32
Nodes (4): Bool, Double, Int, TileKnowledgeResolver

### Community 27 - "Include"
Cohesion: 0.13
Nodes (15): GameMode, vector, ScoreSystem, applyRoundScores, hasMatchEnded, m_mode, m_scores, score (+7 more)

### Community 28 - "Include"
Cohesion: 0.14
Nodes (19): Chain, fromKnownState, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles, placeLeft (+11 more)

### Community 29 - "Isolynenginetests"
Cohesion: 0.12
Nodes (22): BeliefState::totalProbabilityMass(), isTracked, probability, ProbabilityEngine, constructFromGameState, expectedRemainingValue, observeDraw, observePlay (+14 more)

### Community 30 - "Environment"
Cohesion: 0.20
Nodes (8): NSObjectProtocol, EnvironmentManager, Calendar, Int, Never, Task, Void, EnvironmentManagerTests

### Community 31 - "Isolynapp"
Cohesion: 0.04
Nodes (47): 0. Design correction — Offsuit-minimal (2026-11-12), 10. Implementation phases, 11. Acceptance criteria, 12. Risks and boundaries, 13. Immediate next slice, 1. Verdict, 2. What exists today, 3. Product direction: The Table (+39 more)

### Community 32 - "Engine"
Cohesion: 0.18
Nodes (12): EvaluationEngine::evaluate(), teamMobility(), BlockingHeuristic, score, ClosingOpportunityHeuristic, kNextRoundStartBonus, score, ExpectedValueHeuristic (+4 more)

### Community 33 - "Isolynengine"
Cohesion: 0.07
Nodes (21): Content, IsolynApp, AppearanceKeyframe, EnvironmentAppearance, EnvironmentAppearanceCurve, EnvironmentColor, Double, HandTapRouter (+13 more)

### Community 34 - "Isolynengine"
Cohesion: 0.16
Nodes (11): OpeningDecision, openingPlayerIndex, openingTile, GameMode, pair, vector, RulesEngine::computeRoundScores(), RulesEngine::determineCloser() (+3 more)

### Community 35 - "Include"
Cohesion: 0.19
Nodes (9): BoardCamera, CGFloat, CGPoint, CGSize, Double, Never, Task, Void (+1 more)

### Community 36 - "Engine"
Cohesion: 0.15
Nodes (13): Error, BridgeError, boneyardEmpty, bridgeFailure, engineFailure, invalidMove, invalidRequest, noLegalMove (+5 more)

### Community 37 - "Isolynenginebridgetests"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 38 - "Environment"
Cohesion: 0.11
Nodes (16): CaseIterable, EnvironmentState, Date, Double, String, Double, TimePhase, afternoon (+8 more)

### Community 39 - "Include"
Cohesion: 0.20
Nodes (18): setCurrentPlayerIndex, GameMode, MatchController, currentPlayerHasLegalMove, dealFirstRound, dealSubsequentRound, endTurnWithNoPlay, m_mode (+10 more)

### Community 40 - "Root Docs"
Cohesion: 0.38
Nodes (5): PreferenceKey, BoneyardAnchorKey, CGPoint, HandTileFramesKey, CGRect

### Community 41 - "Environment"
Cohesion: 0.21
Nodes (7): EnvironmentClock, FixedEnvironmentClock, Date, SystemEnvironmentClock, RandomWeatherService, Double, TimeZone

### Community 42 - "Appearance"
Cohesion: 0.09
Nodes (23): ENGINE-01 — Search, terminal scoring, evaluation, difficulty, and AI mode, METAL-01 — Standalone Metal batch evaluator, METAL-02 — face-mask kernel optimization (2026-11-11), OPS-10 — Closeout Initiative, PERF-01 — CPU evaluator/hash and Metal kernel throughput round (2026-11-11), PERF-02 — batch leaf evaluation + inline raw totals (2026-11-11), PERF-03 — batch leaf Closed/mobility consolidation (2026-11-12), REGRESSION-01 — post-Metal regression matrix (2026-11-11) (+15 more)

### Community 43 - "Include"
Cohesion: 0.17
Nodes (12): Boneyard::Boneyard(), Boneyard::drawNext(), Boneyard::lockedTiles(), Boneyard::undoDraw(), vector, Boneyard, drawNext, lockedTiles (+4 more)

### Community 44 - "Isolynengine"
Cohesion: 0.10
Nodes (16): Context, NSEvent, NSPoint, NSView, NSViewRepresentable, Coordinator, InspectionEventMonitor, InspectionMouseButton (+8 more)

### Community 45 - "Include"
Cohesion: 0.18
Nodes (9): App, Scene, AppState, Screen, comingSoon, entry, game, modeSelect (+1 more)

### Community 46 - "Include"
Cohesion: 0.18
Nodes (10): PlacementKind, uint64_t, GameState::drawTile(), GameState::hash(), GameState::playTile(), GameState::undoDrawTile(), GameState::undoPlayTile(), hashMix() (+2 more)

### Community 47 - "Isolynenginebridge"
Cohesion: 0.44
Nodes (8): bridge_match_begin(), bridge_session_create_first_round(), bridge_session_create_subsequent_round(), ChainSideDTO, GameModeDTO, isValidMode(), toEngine(), unique_ptr

### Community 48 - "Root Docs"
Cohesion: 0.23
Nodes (6): HoverChainController, Int, Never, Task, UInt64, Void

### Community 49 - "Game"
Cohesion: 0.14
Nodes (14): FIX‑15 — EnvironmentManager weather race (audit F‑04), FIX‑16 — Cancel-on-abandon for analyses (audit F‑10), FIX‑17 — BeliefState.applyOpponentDraw totality (audit F‑11), FIX‑18 — Unknown analysis handle reports truthfully (audit F‑07), FIX‑19 — Observable enum divergence + HandleTable truthing (audits F‑08/F‑12), FIX‑20 — CI pipeline (roadmap P3a / audit remediation-plan item 10), FIX‑21 — Hue slider black-tile bug (NEW finding N-1), FIX‑22..25 — Appearance honesty + mechanical sweep (roadmap P4) (+6 more)

### Community 50 - "Include"
Cohesion: 0.11
Nodes (19): FIX‑01 — Swift test target could not build at all, FIX‑02 — Engine/bridge scripts failed to link on macOS, FIX‑03 — Bridge test harness assumed GNU coreutils, FIX‑04 — SmokeTest deal-randomness flake, part A (blocked-player assumption), FIX‑05 — SmokeTest flake part B (helper spun forever in boneyard-less modes), FIX‑06 — libFuzzer runtime absent from Xcode 26 toolchain (infrastructure), FIX‑07 — Terminal-round guard (audit F‑03): play could continue past a finished round, FIX‑08 — ScoreSystem lacked participant-count accessor (additive) (+11 more)

### Community 51 - "Isolynenginebridge"
Cohesion: 0.15
Nodes (16): Hashable, ChainSide, left, right, BoardDropTargetFrames, CGRect, HandRackView, Bool (+8 more)

### Community 52 - "Isolynengine"
Cohesion: 0.06
Nodes (34): 1a. F‑04 — EnvironmentManager / LiveWeatherService race closure, 1b. F‑10 — Cancel-on-abandon for analyses, 1c. F‑11 — BeliefState divide-by-zero guard (ENGINE CHANGE — test-first, house rule #5), 2a. F‑07 — Truthful failure for unknown analysis handles, 2b. F‑08 — Observable divergence on unknown DTO enums, 2c. F‑12 — HandleTable comment truthing, 3a. CI pipeline, 3b. Full sanitizer baseline (post-fix code) (+26 more)

### Community 53 - "Root Docs"
Cohesion: 0.07
Nodes (27): 1a. Darwin RSS reader, 1b. Make "couldn't measure" loud instead of silently green, 1c. Verify the measurement is REAL before trusting it, 2a. Extract pure layout metrics (testability first), 2b. Auto-fit scale (uniform ⇒ the 2:1 law survives), 2c. Content-aware camera bounds, 2d. The GameSnapshot TEST SEAM (shared infrastructure with Phase 3), 3a. Fix the math to match the claim (or the claim to match the math — math wins) (+19 more)

### Community 54 - "Game"
Cohesion: 0.24
Nodes (8): Impl, shared_ptr, size_t, unordered_map, HandleTable, m_entries, m_mutex, m_nextId

### Community 55 - "Include"
Cohesion: 0.08
Nodes (24): 10. HAND ORDER AND VISUAL CONSISTENCY, 11. TOP HEADER, 12. SCORE DISPLAY, 13. "DRAW" AND "ANALYZE", 14. INSTRUCTIONS, 15. REMOVE DEBUG-STYLE VISUAL LANGUAGE, 16. SPACING SYSTEM, 17. RESPONSIVE BEHAVIOR (+16 more)

### Community 56 - "Include"
Cohesion: 0.10
Nodes (19): 1v1 Strategy — Look-Ahead Depth and Tile-Counting Reasoning, 1v1 Strategy — Skill Gap, Boneyard Draining, Score-Driven Playstyle, and Elite Tactics, 2v2 Strategy — Partner Communication and Coordination, Both decisions are estimation-driven, not rule-driven, Claimed look-ahead depth at high-level play, Closing is sometimes chosen over a visible Domino path, Definition: "missing a set", Draining the entire boneyard: a real, high-variance, high-skill tactic (+11 more)

### Community 57 - "Include"
Cohesion: 0.10
Nodes (19): 1. EXECUTIVE SUMMARY, 2. ARCHITECTURE MAP, 3. DEAD CODE REPORT, 4. FINDINGS TABLE, 5. SCALABILITY VERDICT, 6. PRIORITIZED REMEDIATION PLAN, 7. WHAT'S GOOD, 8. SINGLE HIGHEST-LEVERAGE NEXT ACTION (+11 more)

### Community 58 - "Root Docs"
Cohesion: 0.27
Nodes (8): Codable, InspectionMouseButton, extra, middle, right, InspectionSettings, Stored, Bool

### Community 59 - "Environment"
Cohesion: 0.06
Nodes (36): Backend, capabilities, evaluate, BatchView, featureCount, features, playerCount, positionCount (+28 more)

### Community 60 - "Root Docs"
Cohesion: 0.21
Nodes (13): Config, array, GameMode, mt19937_64, size_t, uint8_t, evaluateAll(), RawEvaluation (+5 more)

### Community 61 - "Include"
Cohesion: 0.22
Nodes (5): Chain::fromKnownState(), Chain::placeLeft(), Chain::placeOpening(), Chain::placeRight(), deque

### Community 62 - "Components"
Cohesion: 0.11
Nodes (17): 0. HOW TO READ THE PERCENTAGES, 1a. Version control + verification harness repair *(small, blocking everything)*, 1b. Terminal-round guard (F‑03) — the highest-severity unfixed bug, 1c. Match orchestration — the keystone design *(bulk of the phase)*, DEPENDENCY GRAPH (why this order and no other), EFFORT SUMMARY TABLE, FIRST THREE ACTIONS WHEN WORK BEGINS, ISOLYN IMPLEMENTATION ROADMAP (+9 more)

### Community 63 - "Components"
Cohesion: 0.19
Nodes (4): Double, CGFloat, String, ColorMathTests

### Community 64 - "Views"
Cohesion: 0.12
Nodes (16): 1. WHAT THIS PROJECT IS (plain words), 2. CURRENT STATE — SCOREBOARD (current run; §6 re-proves the core gates), 3. FOLDER MAP (every item, one line each), 4. THE LAST BIG SESSION — WHAT / WHY / HOW / WHERE, 5.1 Governing documents (authority order — still binding), 5.2 The sandbox-loss lesson (why "commit often" is house law), 5.3 The twelve ambiguity resolutions (numbering = load-bearing), 5.4 Engine rigor status (stated plainly — do NOT "fix" these) (+8 more)

### Community 65 - "Isolynengine"
Cohesion: 0.15
Nodes (12): Architecture, Backend rules, Build and run, Contracts, Correctness gates, Decision, Files, Integration plan (+4 more)

### Community 66 - "Include"
Cohesion: 0.15
Nodes (12): Bridge Architecture, Cancellation, Error model, Explicitly out of scope, Match orchestration (added Phase 1), Ownership: handles, not pointers, Snapshot model — hidden information, State versioning (+4 more)

### Community 70 - "Isolynengine"
Cohesion: 0.29
Nodes (6): Bridge Testing, Current verification matrix, Environment, Historical findings, Not covered, What the bridge suite covers

### Community 71 - "Include"
Cohesion: 0.15
Nodes (12): Boundary, Components, Data contracts, `lab/` — Python lab, Measured baseline (2026-11-11), Milestones, Non-goals, Offline Lab & Trainer (+4 more)

### Community 72 - "Isolynenginebridgetests"
Cohesion: 0.22
Nodes (8): AnalysisSnapshotImpl, belief, believerPlayerIndex, cancelRequested, mode, stateVersionAnalyzed, world, atomic

### Community 80 - "ISOLYN RELEASE CHECKLIST"
Cohesion: 0.20
Nodes (9): 1. App shell, 2. Privacy manifest (`PrivacyInfo.xcprivacy`), 3. Usage-description strings (Info.plist), 4. Capabilities & entitlements, 5. Icon & assets, 6. Build, sign, notarize, 7. Pre-flight functional checks on the packaged app, Explicitly out of scope until after UI revival (+1 more)

### Community 81 - "Dealer::deal"
Cohesion: 0.20
Nodes (9): Ambition, Architecture, Build and run, Correctness gates, Files, IsolynV2.0 Metal Accelerator, Measured throughput, Non-goals (+1 more)

### Community 82 - "29. IMPLEMENTATION ORDER"
Cohesion: 0.22
Nodes (9): 29. IMPLEMENTATION ORDER, Step 1 --- Replace the domino renderer, Step 2 --- Rebuild board layout, Step 3 --- Rebuild player hand, Step 4 --- Rebuild header/status, Step 5 --- Rebuild action area, Step 6 --- Responsive pass, Step 7 --- Interaction pass (+1 more)

### Community 83 - "Feature Specifications — Training Mode and Sandbox Mode"
Cohesion: 0.25
Nodes (7): Correct-move handling, Cross-cutting implications worth flagging now, Feature Specifications — Training Mode and Sandbox Mode, Sandbox Mode, Training Mode, Visual design, Wrong-move handling

### Community 84 - "SearchDecision"
Cohesion: 0.17
Nodes (12): Move, uint64_t, vector, SearchDecision, completed, depthReached, exactEndgame, expectedValuePerPlayer (+4 more)

### Community 85 - "26. EXACT INFORMATION HIERARCHY"
Cohesion: 0.33
Nodes (6): 26. EXACT INFORMATION HIERARCHY, Priority 1, Priority 2, Priority 3, Priority 4, Priority 5

### Community 86 - "THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT."
Cohesion: 0.33
Nodes (6): 2. ABSOLUTE RULE: DOMINOES ARE SINGLE RECTANGLES, Acceptance test, Forbidden implementation, Required geometry, Required implementation model, THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.

### Community 87 - "30. ACCEPTANCE CRITERIA"
Cohesion: 0.33
Nodes (6): 30. ACCEPTANCE CRITERIA, Board, Domino construction, Hand, Layout, Quality

### Community 88 - "EnvironmentTests.swift"
Cohesion: 0.23
Nodes (16): ofstream, ostream, GameMode, string, string_view, uint64_t, handValueOf(), main() (+8 more)

### Community 89 - "3. DOMINO TILE SPECIFICATION"
Cohesion: 0.40
Nodes (5): 3. DOMINO TILE SPECIFICATION, Base tile, Center divider, Pips, Tile silhouette

### Community 90 - "DealResult"
Cohesion: 0.11
Nodes (28): EvalParams, componentCount, playerCount, positionCount, EvalPositionParams, playerCount, positionCount, handValue() (+20 more)

### Community 91 - "RoundOutcome"
Cohesion: 0.12
Nodes (13): AILevel, casual, club, elite, expert, master, MatchFormat, OpponentMode (+5 more)

### Community 96 - "README.md"
Cohesion: 0.29
Nodes (6): Architecture, Decisions, IsolynV2.0, Project identity, Run, Status

### Community 97 - ".shutdown"
Cohesion: 0.48
Nodes (6): GameMode, vector, Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode()

### Community 145 - "Isolyn Offline Lab (scaffold)"
Cohesion: 0.25
Nodes (7): Boundary, IsolynV2.0 Offline Lab, Layout, Non-goals, Planned milestones, Quick start, Related decisions

### Community 146 - "Isolyn — Open Decisions & Architecture Records"
Cohesion: 0.29
Nodes (6): ADR-001 — Product languages: C++20 + Swift; Python offline only, ADR-002 — Offline lab and trainer, ADR-003 — Metal accelerator is a first-class backend, ADR-004 — One source of game truth, IsolynV2.0 — Open Decisions & Architecture Records, Open questions

### Community 147 - "SimulationEngine::sampleDeterminizedState"
Cohesion: 0.32
Nodes (3): AppearanceManager, Double, String

### Community 148 - "CommandResultDTO"
Cohesion: 0.22
Nodes (8): FIX-27 - SoakTest measures RSS on macOS; sanitizer sweep de-confounded (audit OA-1), FIX-28 - Board layout truth + auto-fit resilience + snapshot test seam; FOUND+FIXED latent off-board snake bug (audit OA-4), SESSION: AUDIT REMEDIATION (2026-08-25, owner-approved Phases 0-2 of `audit remediation roadmap.md`), UI‑01 — Canonical single-rectangle renderer (§2/§3 — THE core law), UI‑02 — Snake-chain board (§4–§8), UI‑03 — Real hand + screen chrome (§9–§14, §28), UI‑QA — OWNER VISUAL SIGN-OFF, UI REBUILD — dominoes_ui_fix_non_negotiable.md EXECUTED

### Community 149 - "Isolyn Self-Play Harness (scaffold)"
Cohesion: 0.33
Nodes (5): Build and run, CSV fields, IsolynV2.0 Self-Play Generator, Modes, What it deliberately does not do yet

### Community 150 - "ComingSoonView"
Cohesion: 0.14
Nodes (14): RoundOutcomeKind, GameSummary, aDepth, aDeterminizations, bDepth, bDeterminizations, decidingPlayer, decisions (+6 more)

### Community 151 - "Boneyard.cpp"
Cohesion: 0.14
Nodes (12): GeometryProxy, HandDragModel, InteractiveGameBoardView, SeatItem, Bool, CGFloat, CGPoint, CGSize (+4 more)

### Community 152 - "Move"
Cohesion: 0.20
Nodes (10): Options, depth, determinizations, games, mode, opponentDepth, opponentDeterminizations, output (+2 more)

### Community 153 - "build_parser"
Cohesion: 0.07
Nodes (43): ArgumentParser, Counter, analyze(), CalibrationReport, elo_from_score(), elo_interval(), participant_label(), ParticipantStats (+35 more)

### Community 154 - "DominoTile.cpp"
Cohesion: 0.18
Nodes (11): MoveRow, depthReached, evaluation, exactEndgame, moveIndex, nodes, player, side (+3 more)

### Community 155 - "benchmarkMode"
Cohesion: 0.31
Nodes (10): Fn, benchmarkMode(), array, GameMode, size_t, main(), makeFixture(), median() (+2 more)

### Community 158 - "MetalAccelerator.mm"
Cohesion: 0.20
Nodes (9): DifficultyModel, kMaxStrength, kMinStrength, kProfiles, DifficultyProfile, determinizationCount, maxDepthPlies, strength (+1 more)

### Community 160 - "Options"
Cohesion: 0.13
Nodes (25): Dealer::deal(), Dealer, deal, excludedTilesForMode, handSizeForMode, isMisdeal, playerCountForMode, DealResult (+17 more)

### Community 161 - "XCTestCase"
Cohesion: 0.33
Nodes (5): map, mt19937_64, pair, vector, Determinizer::sample()

### Community 162 - "EvaluationWeights"
Cohesion: 0.13
Nodes (22): optional, GameMode, evaluateAllImpl(), EvaluationEngine::evaluateAll(), EvaluationEngine::evaluateAllWithClosed(), HandFacts, legalMoves, value (+14 more)

### Community 163 - "Dealer.cpp"
Cohesion: 0.20
Nodes (10): EvaluationBreakdown, blocking, closingOpportunity, expectedValue, mobility, pipControl, teamSupport, tempo (+2 more)

### Community 164 - "TTEntry"
Cohesion: 0.33
Nodes (6): GameMode, vector, GameState::GameState(), PlayRecord, playerIndex, tile

### Community 166 - "Determinizer::sample"
Cohesion: 0.25
Nodes (8): size_t, uint64_t, uint8_t, EntropySource::fillSecureRandomBytes(), EntropySource::nextUint64(), EntropySource::uniformIndexBelow(), fillSecureRandomBytes, nextUint64

### Community 167 - ".makeBody"
Cohesion: 0.40
Nodes (4): Move, describe, side, tile

### Community 169 - "buildAllTiles"
Cohesion: 0.33
Nodes (5): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles()

### Community 173 - "Dealer"
Cohesion: 0.20
Nodes (10): Identifiable, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, ModeCard, ModeOption, Bool (+2 more)

### Community 174 - "IsolynV2.0 Project Inventory"
Cohesion: 0.40
Nodes (4): Components and LOC, IsolynV2.0 Project Inventory, Naming boundary, Relevant callers

### Community 175 - "buildSnapshot"
Cohesion: 0.10
Nodes (23): ChainDTO, count, leftEnd, rightEnd, tiles, DifficultyProfileDTO, determinizationCount, maxDepthPlies (+15 more)

### Community 176 - "RoundEndOverlay"
Cohesion: 0.32
Nodes (6): RevealRow, RoundEndOverlay, Bool, Int, String, Void

### Community 177 - "GestureArbiter"
Cohesion: 0.14
Nodes (10): AppKit, Foundation, IsolynEngineBridge, Observation, Phase, loading, matchOver, playing (+2 more)

### Community 180 - "ComingSoonView"
Cohesion: 0.16
Nodes (28): hasImmediateDominoWin(), advanceToNextPlayer, checkForClose, MoveExecutor, apply, undo, size_t, MoveGenerator (+20 more)

### Community 181 - "BlockingHeuristic::score"
Cohesion: 0.13
Nodes (13): AppliedMove, kind, move, playerIndex, Move, PlacementKind, string, Move::describe() (+5 more)

### Community 182 - "EnvironmentTimeLabel"
Cohesion: 0.60
Nodes (3): DateFormatter, EnvironmentTimeLabel, String

### Community 183 - "GestureArbiter"
Cohesion: 0.23
Nodes (9): GestureArbiter, GestureOwner, boardPan, dominoDrag, idle, pending, Bool, CGFloat (+1 more)

### Community 184 - "RoundOutcome"
Cohesion: 0.50
Nodes (4): RoundOutcomeKind, RoundOutcome, decidingPlayerIndex, kind

### Community 185 - "TTEntry"
Cohesion: 0.29
Nodes (7): TTEntry, bestCode, depth, flag, raw, score, TTFlag

### Community 186 - "DepthResult"
Cohesion: 0.15
Nodes (18): Move, unordered_map, vector, DepthResult, depth, move, samples, values (+10 more)

### Community 187 - "DrawFlightView"
Cohesion: 0.10
Nodes (21): DominoAppearance, EdgeHighlightMode, none, standard, strong, subtle, BoneyardFaceDownTile, BoneyardView (+13 more)

## Knowledge Gaps
- **738 isolated node(s):** `build.sh script`, `features`, `positionCount`, `featureCount`, `values` (+733 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **68 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameState` connect `Isolynengine` to `Include`, `Include`, `Include`, `Include`, `Engine`, `Include`, `Include`, `Root Docs`, `benchmarkMode`, `Include`, `Isolynenginetests`, `Engine`, `Options`, `EvaluationWeights`, `TTEntry`, `Include`, `Include`, `Include`, `ComingSoonView`, `BlockingHeuristic::score`, `DepthResult`, `Root Docs`, `Isolynenginebridgetests`, `EnvironmentTests.swift`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **Why does `DominoTile` connect `Include` to `Include`, `Isolynenginebridge`, `Isolynengine`, `Engine`, `Include`, `Include`, `Isolynenginetests`, `Options`, `XCTestCase`, `Isolynengine`, `TTEntry`, `.makeBody`, `Include`, `buildAllTiles`, `Include`, `Include`, `Isolynenginebridge`, `ComingSoonView`, `BlockingHeuristic::score`, `DepthResult`, `Include`, `.shutdown`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Why does `InteractiveGameBoardView` connect `Boneyard.cpp` to `Include`, `GestureArbiter`, `Game`, `Root Docs`, `GestureArbiter`, `Isolynenginebridge`, `SimulationEngine::sampleDeterminizedState`, `Include`, `GestureArbiter`, `Components`, `Root Docs`, `RoundOutcome`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `GameState` (e.g. with `bridge_match_record_round()` and `buildSnapshot()`) actually correct?**
  _`GameState` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `GameViewModel` (e.g. with `.test_computer_plays_its_own_turn_without_human_input()` and `.test_computer_plays_two_v_two_partner_turn_without_stalling()`) actually correct?**
  _`GameViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `Tile` (e.g. with `.test_orient_flipsEachTileToTouchItsNeighbour()` and `.test_orient_marksDoubles()`) actually correct?**
  _`Tile` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `build.sh script`, `features`, `positionCount` to the rest of the system?**
  _738 weakly-connected nodes found - possible documentation gaps or missing edges._