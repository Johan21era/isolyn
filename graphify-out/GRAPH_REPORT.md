# Graph Report - Isolyn-current_4  (2026-11-11)

## Corpus Check
- 176 files · ~126,111 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1936 nodes · 3581 edges · 173 communities (104 shown, 69 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 265 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `62371dcc`
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
- StandaloneFuzzDriver.cpp
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
- __init__.py
- iso
- build.sh
- MetalAccelerator.mm
- isolyn-lab
- Options
- EntropySource.cpp
- EvaluationWeights
- Dealer.cpp
- TTEntry
- CalibrationTests
- Determinizer::sample
- .makeBody
- BeliefState.hpp
- shuffle
- RoundOutcome
- build.sh
- StandaloneFuzzDriver.cpp

## God Nodes (most connected - your core abstractions)
1. `GameState` - 67 edges
2. `DominoTile` - 63 edges
3. `GameViewModel` - 48 edges
4. `View` - 38 edges
5. `SearchContext` - 31 edges
6. `SwiftUI` - 30 edges
7. `Tile` - 30 edges
8. `Chain` - 29 edges
9. `MatchController` - 28 edges
10. `playOneRound()` - 28 edges

## Surprising Connections (you probably didn't know these)
- `Isolyn Current Audit (Markdown edition)` --semantically_similar_to--> `Isolyn Current Audit (PDF edition)`  [INFERRED] [semantically similar]
  isolyn current audit.md → isolyn current audit.pdf
- `main()` --calls--> `markTileKnown`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `applyOpponentDraw`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `lockedTiles`  [INFERRED]
  Tests/IsolynEngineTests/BoneyardTests.cpp → Sources/IsolynEngine/include/Boneyard.hpp
- `main()` --calls--> `Chain`  [INFERRED]
  Tests/IsolynEngineTests/GameStateTests.cpp → Sources/IsolynEngine/include/Chain.hpp

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Audit–Roadmap Governance Set** — isolyn_current_audit_document, core_hardening_roadmap_document, audit_remediation_roadmap_document, isolyn_roadmap_document [EXTRACTED 1.00]
- **Bridge Design ↔ Verification Trust Chain** — docs_bridge_architecture_document, docs_bridge_architecture_bridge, docs_bridge_testing_document, docs_bridge_testing_blocked_player_ub [EXTRACTED 1.00]
- **OA Remediation Executed as FIX-27/FIX-28** — audit_remediation_roadmap_oa_1_macos_soak_noop, audit_remediation_roadmap_oa_4_chain_board_bounds, fix_log_fix_27_soak_truth, fix_log_fix_28_board_layout [EXTRACTED 1.00]

## Communities (173 total, 69 thin omitted)

### Community 0 - "Appearance"
Cohesion: 0.08
Nodes (28): Codable, AppearanceManager, Double, String, Color, DominoAppearance, EdgeHighlightMode, none (+20 more)

### Community 1 - "Root Docs"
Cohesion: 0.67
Nodes (3): CI Pipeline (Phase 3a / OPS-04), F-02-Class Drift Structural Guard, CI Workflow (GitHub Actions macOS)

### Community 2 - "Root Docs"
Cohesion: 0.13
Nodes (17): Gesture, ChainAndZonesView, EndMarker, Metrics, Oriented, Placed, SnakeChainBoard, SnakeChainLayout (+9 more)

### Community 3 - "Hoverchain"
Cohesion: 0.16
Nodes (13): Hashable, PredictivePolicy, Double, TileKnowledge, historical, lockedOff, mine, predictedOpponent (+5 more)

### Community 4 - "Include"
Cohesion: 0.13
Nodes (24): Dealer::deal(), Dealer, deal, excludedTilesForMode, handSizeForMode, isMisdeal, playerCountForMode, DealResult (+16 more)

### Community 5 - "Isolynapptests"
Cohesion: 0.27
Nodes (7): Equatable, AppearanceKeyframe, EnvironmentAppearance, EnvironmentAppearanceCurve, EnvironmentColor, Double, EnvironmentAppearanceCurveTests

### Community 7 - "Root Docs"
Cohesion: 0.10
Nodes (19): GraphicsContext, RandomNumberGenerator, StarFieldView, Int, UInt64, CGSize, Double, WeatherEffectView (+11 more)

### Community 8 - "Isolynenginebridge"
Cohesion: 0.17
Nodes (27): CommandResultDTO, decidingPlayerIndex, diagnosticMessage, newStateVersion, roundOutcome, status, RoundOutcomeDTO, advanceStateVersion() (+19 more)

### Community 9 - "Game"
Cohesion: 0.11
Nodes (15): ObjectIdentifier, GameViewModel, Bool, Int, Move, Never, RoundOutcome, Set (+7 more)

### Community 10 - "Environment"
Cohesion: 0.12
Nodes (20): CaseIterable, CLLocation, Sendable, previewManager(), Int, LiveWeatherService, SkyCondition, clear (+12 more)

### Community 11 - "Isolynenginebridge"
Cohesion: 0.12
Nodes (17): GameMode, EngineSessionImpl, cachedDecidingPlayer, cachedRoundOutcome, controller, mode, mutex, stateVersion (+9 more)

### Community 12 - "Include"
Cohesion: 0.18
Nodes (16): GameMode, EvaluationEngine::evaluate(), handValueOf(), hasImmediateDominoWin(), teamMobility(), BlockingHeuristic, score, ClosingOpportunityHeuristic (+8 more)

### Community 13 - "Isolynapptests"
Cohesion: 0.19
Nodes (3): Calendar, EnvironmentManagerTests, TimePhaseTests

### Community 14 - "Game"
Cohesion: 0.13
Nodes (10): IsolynApp, IsolynEngineBridge, Observation, Phase, loading, matchOver, playing, roundOver (+2 more)

### Community 15 - "Include"
Cohesion: 0.06
Nodes (27): int8_t, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map, vector, Chain::fromKnownState() (+19 more)

### Community 16 - "Isolynengine"
Cohesion: 0.10
Nodes (18): ExpectedValueHeuristic::score(), GameState, hash, m_boneyard, m_chain, m_currentPlayerIndex, m_hands, m_mode (+10 more)

### Community 17 - "Include"
Cohesion: 0.10
Nodes (21): ChainDTO, count, leftEnd, rightEnd, tiles, DifficultyProfileDTO, determinizationCount, maxDepthPlies (+13 more)

### Community 18 - "Engine"
Cohesion: 0.18
Nodes (8): AnalysisTask, EngineSession, Error, Int, Int32, isolyn, MatchFormat, Task

### Community 19 - "Include"
Cohesion: 0.11
Nodes (18): BeliefState, kBoneyardLocation, m_distributions, m_tracked, kTileCount, ProbabilityEngine::expectedRemainingValue(), ProbabilityEngine::observeDraw(), ProbabilityEngine::observePlay() (+10 more)

### Community 20 - "Include"
Cohesion: 0.11
Nodes (19): GameModeDTO, SnapshotDTO, boneyardDrawableCount, boneyardLockedCount, boneyardLockedTiles, chain, currentPlayerIndex, decidingPlayerIndex (+11 more)

### Community 21 - "Include"
Cohesion: 0.16
Nodes (32): Config, MoveExecutor, apply, undo, GameMode, Move, mt19937_64, vector (+24 more)

### Community 22 - "Engine"
Cohesion: 0.11
Nodes (21): Element, os, AnalysisOutcome, ChainSide, left, right, MatchFormat, MatchOutcome (+13 more)

### Community 23 - "Include"
Cohesion: 0.10
Nodes (21): AnalysisResultDTO, completed, expectedValuePerPlayer, playerCount, recommendedMove, samplesCompleted, samplesConfigured, stateVersionAnalyzed (+13 more)

### Community 24 - "Root Docs"
Cohesion: 0.22
Nodes (9): Font, InteractiveGameBoardView, Bool, Int, MatchFormat, String, Void, IsolynTheme (+1 more)

### Community 25 - "Components"
Cohesion: 0.09
Nodes (15): AtmosphericBackgroundView, EnvironmentSettingsView, EnvironmentView, LegibilityScrim, PipGlyph, CGFloat, Int, View (+7 more)

### Community 26 - "Hoverchain"
Cohesion: 0.36
Nodes (6): GameSnapshot, Tile, Bool, Double, Int, TileKnowledgeResolver

### Community 27 - "Include"
Cohesion: 0.13
Nodes (15): GameMode, vector, ScoreSystem, applyRoundScores, hasMatchEnded, m_mode, m_scores, score (+7 more)

### Community 28 - "Include"
Cohesion: 0.18
Nodes (15): Chain, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles, placeLeft, placeOpening (+7 more)

### Community 29 - "Isolynenginetests"
Cohesion: 0.13
Nodes (15): array, Determinizer, sample, DominoSet, shuffledTiles, mt19937_64, SimulationEngine::sampleDeterminizedState(), main() (+7 more)

### Community 30 - "Environment"
Cohesion: 0.28
Nodes (7): NSObjectProtocol, EnvironmentManager, Calendar, Int, Never, Task, Void

### Community 31 - "Isolynapp"
Cohesion: 0.14
Nodes (13): App, Scene, AppState, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, Screen (+5 more)

### Community 32 - "Engine"
Cohesion: 0.47
Nodes (3): Move, UInt64, CommandOutcome

### Community 33 - "Isolynengine"
Cohesion: 0.16
Nodes (16): BlockingHeuristic::score(), MoveGenerator, generate, hasAnyLegalMove, isPositionClosed, determineCloser, vector, MatchController::checkForClose() (+8 more)

### Community 34 - "Isolynengine"
Cohesion: 0.16
Nodes (11): OpeningDecision, openingPlayerIndex, openingTile, GameMode, pair, vector, RulesEngine::computeRoundScores(), RulesEngine::determineCloser() (+3 more)

### Community 35 - "Include"
Cohesion: 0.12
Nodes (22): size_t, vector, PositionBatch, playerCount, rows, GameMode, vector, encodePositionBatch() (+14 more)

### Community 36 - "Engine"
Cohesion: 0.15
Nodes (13): Error, BridgeError, boneyardEmpty, bridgeFailure, engineFailure, invalidMove, invalidRequest, noLegalMove (+5 more)

### Community 37 - "Isolynenginebridgetests"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 38 - "Environment"
Cohesion: 0.17
Nodes (11): EnvironmentState, Date, Double, String, Double, TimePhase, afternoon, morning (+3 more)

### Community 39 - "Include"
Cohesion: 0.19
Nodes (19): playTile, setCurrentPlayerIndex, GameMode, MatchController, currentPlayerHasLegalMove, dealFirstRound, dealSubsequentRound, endTurnWithNoPlay (+11 more)

### Community 40 - "Root Docs"
Cohesion: 0.12
Nodes (15): Identifiable, ModeCard, ModeOption, Bool, Int, String, Void, AILevel (+7 more)

### Community 41 - "Environment"
Cohesion: 0.18
Nodes (9): EnvironmentClock, FixedEnvironmentClock, Date, SystemEnvironmentClock, RandomWeatherService, Double, Int, String (+1 more)

### Community 42 - "Appearance"
Cohesion: 0.23
Nodes (9): ColorEditorRow, DominoAppearanceSection, HueSlider, SettingsDrawer, Bool, CGFloat, Double, String (+1 more)

### Community 43 - "Include"
Cohesion: 0.17
Nodes (12): Boneyard::Boneyard(), Boneyard::drawNext(), Boneyard::lockedTiles(), Boneyard::undoDraw(), vector, Boneyard, drawNext, lockedTiles (+4 more)

### Community 44 - "Isolynengine"
Cohesion: 0.18
Nodes (15): GameMode, PlacementKind, uint64_t, vector, GameState::drawTile(), GameState::GameState(), GameState::hash(), GameState::playTile() (+7 more)

### Community 45 - "Include"
Cohesion: 0.10
Nodes (28): BeliefState::applyOpponentDraw(), BeliefState::totalProbabilityMass(), applyOpponentDraw, isTracked, markTileKnown, probability, totalProbabilityMass, fromKnownState (+20 more)

### Community 46 - "Include"
Cohesion: 0.12
Nodes (19): advanceToNextPlayer, checkForClose, AppliedMove, kind, move, playerIndex, Move, PlacementKind (+11 more)

### Community 47 - "Isolynenginebridge"
Cohesion: 0.16
Nodes (24): AnalysisHandle, MatchHandle, bridge_analysis_request_cancel(), bridge_analysis_snapshot_create(), bridge_analysis_snapshot_destroy(), bridge_get_snapshot(), bridge_match_begin(), bridge_match_close() (+16 more)

### Community 48 - "Root Docs"
Cohesion: 0.22
Nodes (6): MatchCoordinator, Bool, Int, isolyn, MatchFormat, MatchFormat

### Community 49 - "Game"
Cohesion: 0.29
Nodes (6): HandRackView, Bool, CGFloat, Move, Set, Void

### Community 50 - "Include"
Cohesion: 0.05
Nodes (41): FIX‑01 — Swift test target could not build at all, FIX‑02 — Engine/bridge scripts failed to link on macOS, FIX‑03 — Bridge test harness assumed GNU coreutils, FIX‑04 — SmokeTest deal-randomness flake, part A (blocked-player assumption), FIX‑05 — SmokeTest flake part B (helper spun forever in boneyard-less modes), FIX‑06 — libFuzzer runtime absent from Xcode 26 toolchain (infrastructure), FIX‑07 — Terminal-round guard (audit F‑03): play could continue past a finished round, FIX‑08 — ScoreSystem lacked participant-count accessor (additive) (+33 more)

### Community 51 - "Isolynenginebridge"
Cohesion: 0.21
Nodes (10): Impl, mutex, shared_ptr, bridge_analysis_run(), size_t, unordered_map, HandleTable, m_entries (+2 more)

### Community 52 - "Isolynengine"
Cohesion: 0.06
Nodes (34): 1a. F‑04 — EnvironmentManager / LiveWeatherService race closure, 1b. F‑10 — Cancel-on-abandon for analyses, 1c. F‑11 — BeliefState divide-by-zero guard (ENGINE CHANGE — test-first, house rule #5), 2a. F‑07 — Truthful failure for unknown analysis handles, 2b. F‑08 — Observable divergence on unknown DTO enums, 2c. F‑12 — HandleTable comment truthing, 3a. CI pipeline, 3b. Full sanitizer baseline (post-fix code) (+26 more)

### Community 53 - "Root Docs"
Cohesion: 0.07
Nodes (27): 1a. Darwin RSS reader, 1b. Make "couldn't measure" loud instead of silently green, 1c. Verify the measurement is REAL before trusting it, 2a. Extract pure layout metrics (testability first), 2b. Auto-fit scale (uniform ⇒ the 2:1 law survives), 2c. Content-aware camera bounds, 2d. The GameSnapshot TEST SEAM (shared infrastructure with Phase 3), 3a. Fix the math to match the claim (or the claim to match the math — math wins) (+19 more)

### Community 54 - "Game"
Cohesion: 0.43
Nodes (5): RevealRow, RoundEndOverlay, Bool, Int, String

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
Cohesion: 0.33
Nodes (5): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles()

### Community 59 - "Environment"
Cohesion: 0.06
Nodes (36): Backend, capabilities, evaluate, BatchView, featureCount, features, playerCount, positionCount (+28 more)

### Community 60 - "Root Docs"
Cohesion: 0.09
Nodes (22): kKillerSlots, kMaxHistoryPlayers, kMoveCodeCount, array, atomic, uint64_t, unordered_map, SearchContext (+14 more)

### Community 61 - "Include"
Cohesion: 0.20
Nodes (10): EvaluationBreakdown, blocking, closingOpportunity, expectedValue, mobility, pipControl, teamSupport, tempo (+2 more)

### Community 62 - "Components"
Cohesion: 0.11
Nodes (17): 0. HOW TO READ THE PERCENTAGES, 1a. Version control + verification harness repair *(small, blocking everything)*, 1b. Terminal-round guard (F‑03) — the highest-severity unfixed bug, 1c. Match orchestration — the keystone design *(bulk of the phase)*, DEPENDENCY GRAPH (why this order and no other), EFFORT SUMMARY TABLE, FIRST THREE ACTIONS WHEN WORK BEGINS, ISOLYN IMPLEMENTATION ROADMAP (+9 more)

### Community 63 - "Components"
Cohesion: 0.60
Nodes (3): DateFormatter, EnvironmentTimeLabel, String

### Community 64 - "Views"
Cohesion: 0.12
Nodes (16): 1. WHAT THIS PROJECT IS (plain words), 2. CURRENT STATE — SCOREBOARD (all verified — §6 re-proves everything), 3. FOLDER MAP (every item, one line each), 4. THE LAST BIG SESSION — WHAT / WHY / HOW / WHERE, 5.1 Governing documents (authority order — still binding), 5.2 The sandbox-loss lesson (why "commit often" is house law), 5.3 The twelve ambiguity resolutions (numbering = load-bearing), 5.4 Engine rigor status (stated plainly — do NOT "fix" these) (+8 more)

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
Cohesion: 0.13
Nodes (15): EvaluationBatch, componentCount, features, playerCount, positionCount, size_t, GameMode, vector (+7 more)

### Community 80 - "ISOLYN RELEASE CHECKLIST"
Cohesion: 0.20
Nodes (9): 1. App shell, 2. Privacy manifest (`PrivacyInfo.xcprivacy`), 3. Usage-description strings (Info.plist), 4. Capabilities & entitlements, 5. Icon & assets, 6. Build, sign, notarize, 7. Pre-flight functional checks on the packaged app, Explicitly out of scope until after UI revival (+1 more)

### Community 81 - "Dealer::deal"
Cohesion: 0.20
Nodes (9): Ambition, Architecture, Build and run, Correctness gates, Files, Isolyn Metal Accelerator, Measured throughput, Non-goals (+1 more)

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
Cohesion: 0.25
Nodes (15): ofstream, ostream, GameMode, string, string_view, uint64_t, main(), modeName() (+7 more)

### Community 89 - "3. DOMINO TILE SPECIFICATION"
Cohesion: 0.40
Nodes (5): 3. DOMINO TILE SPECIFICATION, Base tile, Center divider, Pips, Tile silhouette

### Community 90 - "DealResult"
Cohesion: 0.12
Nodes (29): EvalParams, componentCount, playerCount, positionCount, EvalPositionParams, playerCount, positionCount, handValue() (+21 more)

### Community 91 - "RoundOutcome"
Cohesion: 0.28
Nodes (14): Any, Counter, build_html(), full_view(), load_graph(), load_json(), main(), node_id() (+6 more)

### Community 96 - "README.md"
Cohesion: 0.33
Nodes (5): Architecture, Decisions, Isolyn, Run, Status

### Community 97 - "StandaloneFuzzDriver.cpp"
Cohesion: 0.22
Nodes (13): Int, HoverChain, HoverChainEntry, HoverChainNodeKind, baseUninformed, complete, historicalInformed, lockedOff (+5 more)

### Community 145 - "Isolyn Offline Lab (scaffold)"
Cohesion: 0.25
Nodes (7): Boundary, Isolyn Offline Lab, Layout, Non-goals, Planned milestones, Quick start, Related decisions

### Community 146 - "Isolyn — Open Decisions & Architecture Records"
Cohesion: 0.29
Nodes (6): ADR-001 — Product languages: C++20 + Swift; Python offline only, ADR-002 — Offline lab and trainer, ADR-003 — Metal accelerator is a first-class backend, ADR-004 — One source of game truth, Isolyn — Open Decisions & Architecture Records, Open questions

### Community 147 - "SimulationEngine::sampleDeterminizedState"
Cohesion: 0.19
Nodes (9): BoardCamera, CGFloat, CGPoint, CGSize, Double, Never, Task, Void (+1 more)

### Community 148 - "CommandResultDTO"
Cohesion: 0.21
Nodes (6): HoverChainController, Int, Never, Task, UInt64, Void

### Community 149 - "Isolyn Self-Play Harness (scaffold)"
Cohesion: 0.33
Nodes (5): Build and run, CSV fields, Isolyn Self-Play Generator, Modes, What it deliberately does not do yet

### Community 150 - "ComingSoonView"
Cohesion: 0.14
Nodes (14): RoundOutcomeKind, GameSummary, aDepth, aDeterminizations, bDepth, bDeterminizations, decidingPlayer, decisions (+6 more)

### Community 151 - "Boneyard.cpp"
Cohesion: 0.21
Nodes (9): GestureArbiter, GestureOwner, boardPan, dominoDrag, idle, pending, Bool, CGFloat (+1 more)

### Community 152 - "Move"
Cohesion: 0.20
Nodes (7): AIProfile, MatchFormat, OpponentMode, computer, human, Bool, Int32

### Community 153 - "build_parser"
Cohesion: 0.10
Nodes (29): ArgumentParser, analyze(), CalibrationReport, elo_from_score(), elo_interval(), participant_label(), ParticipantStats, _rank() (+21 more)

### Community 154 - "DominoTile.cpp"
Cohesion: 0.18
Nodes (11): MoveRow, depthReached, evaluation, exactEndgame, moveIndex, nodes, player, side (+3 more)

### Community 155 - "__init__.py"
Cohesion: 0.20
Nodes (4): AppKit, CoreLocation, Foundation, WeatherKit

### Community 158 - "MetalAccelerator.mm"
Cohesion: 0.22
Nodes (9): DifficultyModel, kMaxStrength, kMinStrength, kProfiles, DifficultyProfile, determinizationCount, maxDepthPlies, strength (+1 more)

### Community 160 - "Options"
Cohesion: 0.20
Nodes (10): Options, depth, determinizations, games, mode, opponentDepth, opponentDeterminizations, output (+2 more)

### Community 161 - "EntropySource.cpp"
Cohesion: 0.25
Nodes (8): size_t, uint64_t, EntropySource::fillSecureRandomBytes(), EntropySource::nextUint64(), EntropySource::uniformIndexBelow(), fillSecureRandomBytes, nextUint64, uint8_t

### Community 162 - "EvaluationWeights"
Cohesion: 0.22
Nodes (9): EvaluationWeights, blocking, closingOpportunity, expectedValue, mobility, pipControl, teamSupport, tempo (+1 more)

### Community 163 - "Dealer.cpp"
Cohesion: 0.48
Nodes (6): GameMode, vector, Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode()

### Community 164 - "TTEntry"
Cohesion: 0.29
Nodes (7): TTEntry, bestCode, depth, flag, raw, score, TTFlag

### Community 166 - "Determinizer::sample"
Cohesion: 0.33
Nodes (5): map, mt19937_64, pair, vector, Determinizer::sample()

### Community 167 - ".makeBody"
Cohesion: 0.40
Nodes (3): ButtonStyle, Configuration, PrimaryCapsuleButtonStyle

### Community 169 - "shuffle"
Cohesion: 0.50
Nodes (4): uniformIndexBelow, vector, shuffle(), T

### Community 170 - "RoundOutcome"
Cohesion: 0.50
Nodes (4): RoundOutcomeKind, RoundOutcome, decidingPlayerIndex, kind

## Knowledge Gaps
- **661 isolated node(s):** `build.sh script`, `features`, `positionCount`, `featureCount`, `values` (+656 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **69 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameState` connect `Isolynengine` to `Isolynengine`, `Include`, `Include`, `Include`, `Include`, `Isolynenginebridgetests`, `Isolynenginebridge`, `Include`, `Include`, `Isolynengine`, `Include`, `Include`, `Include`, `Isolynenginebridge`, `Include`, `Include`, `Include`, `Isolynenginetests`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Why does `DominoTile` connect `Include` to `Isolynengine`, `Isolynengine`, `Dealer.cpp`, `Include`, `Determinizer::sample`, `Include`, `Isolynenginebridge`, `Include`, `Include`, `Isolynengine`, `Include`, `Isolynenginebridge`, `Isolynengine`, `Include`, `Include`, `Root Docs`, `Include`, `Isolynenginetests`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **Why does `MatchController` connect `Include` to `Isolynengine`, `Include`, `Include`, `Isolynenginebridge`, `Isolynenginebridge`, `Include`, `Include`, `Isolynenginebridge`, `Isolynengine`, `EnvironmentTests.swift`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `GameState` (e.g. with `bridge_match_record_round()` and `buildSnapshot()`) actually correct?**
  _`GameState` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `GameViewModel` (e.g. with `.test_computer_plays_its_own_turn_without_human_input()` and `.test_computer_plays_two_v_two_partner_turn_without_stalling()`) actually correct?**
  _`GameViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `build.sh script`, `features`, `positionCount` to the rest of the system?**
  _661 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Appearance` be split into smaller, more focused modules?**
  _Cohesion score 0.07581453634085213 - nodes in this community are weakly interconnected._