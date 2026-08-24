# Graph Report - Isolyn-current_4  (2026-08-24)

## Corpus Check
- 142 files · ~92,851 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1463 nodes · 2793 edges · 122 communities (82 shown, 40 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 233 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `30f11eee`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Bridge Analysis Pipeline
- Dealer & Tile Accounting
- Environment Clock System
- Snapshot DTO Contract
- Star Field Rendering
- Move Legality Gate
- Swift Runtime Metadata (generated)
- Expected Value Heuristic
- XCTest Infrastructure (generated)
- Engine Core Containers
- Swift Testing Library (generated)
- Evaluation Engine Weights
- Simulation & Shuffle Tests
- Swift Value Witness Tables (generated)
- Bridge Safety & Verification
- Sandbox Mode Requirements
- Belief State Probability Core
- Round Outcome & Blocking
- Score System (Unwired)
- Appearance Curve Interpolation
- Chain Layout & Undo
- Weather Condition Enum
- DominoTile Identity
- RulesEngine Decisions
- Boneyard Draw Mechanics
- Analysis Snapshot Internals
- App Navigation State
- GameState Mutation & Undo
- Environment Manager Lifecycle
- Search Decision Output
- Fuzz Harness Input Model
- Environment UI Components
- Generated Initializers (noise)
- Match Controller Turn Flow
- Handle Table Operations
- Swift Testing Runner (generated)
- Environment Data Models
- Test Issue Reporting (generated)
- Move Executor Applied-Move
- Generated File Lock Utility
- IsolynTheme Design Tokens
- HandleTable Implementation
- ProbabilityEngine Queries
- Live WeatherKit Service
- Hidden-Info Strategy & Bugs
- Chain Placement Ops
- Determinizer Sampling Internals
- Mode Card Component
- Swift Enum Metadata (generated)
- TimePhase Classification
- Determinization Test Pair
- Search Decision Struct
- Future Work & Known Bugs
- DominoSet Construction
- Random Weather Source
- Evaluation Breakdown Struct
- Closing Opportunity Heuristic
- Pip Glyph Signature
- Coming Soon Placeholder
- Entry Screen
- Move Value Type
- Game Placeholder Screen
- Mode Selector Screen
- Round Outcome Kind
- Runtime Metadata Fragments (noise)
- Primary Capsule Button Style
- TypeMetadataTrait Double (noise)
- TypeMetadataTrait UInt (noise)
- Sandbox Loss Protocol
- Package Manifest
- Fuzz Script
- Bridge Test Script
- Engine Test Script
- POD Boundary Principle
- Engine Baseline Result
- Fuzz Campaign Result
- Sanitizer Result
- Soak Test Result
- Match-Level Objective
- Repository Tree Snapshot
- AnalysisSnapshotImpl
- Isolyn Repository Layout Snapshot
- HandRackView
- SimulationEngine::sampleDeterminizedState
- RoundEndOverlay
- Determinizer::sample
- EnvironmentTimeLabel
- EnvironmentTests.swift
- run_sanitize.sh
- .operator()
- OpeningDecision
- clean.sh
- README.md
- run.sh
- tree.md
- Handle Tables Instead Of Raw Pointers
- Explicitly Out Of Scope Items
- Per-Session Mutex Defense In Depth
- Player-Scoped Snapshot Model
- Two-Phase Analysis Design
- Blocked Current Player UB Found By Fuzzing
- Bridge Smoke Suite 33 Checks
- undoDrawTile Order Dependency Bug
- ExplanationEngine Requirement
- PositionConstructor Requirement
- Closing Vs Domino Tradeoff
- Boneyard Full-Drain Line
- Locking Down An Inferred Double
- Five-To-Seven Ply Lookahead Calibration Target
- Missing-A-Set Threshold
- Playing For Your Partner
- Score-Proximity Playstyle Shift
- 26. EXACT INFORMATION HIERARCHY
- THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.
- 30. ACCEPTANCE CRITERIA
- EvaluationBreakdown
- WeatherMode
- 3. DOMINO TILE SPECIFICATION
- DealResult
- 4. BOARD MUST LOOK LIKE A DOMINO BOARD
- 9. PLAYER HAND
- DOMINOES UI FIX --- NON-NEGOTIABLE REBUILD MANDATE

## God Nodes (most connected - your core abstractions)
1. `DominoTile` - 61 edges
2. `GameState` - 52 edges
3. `View` - 38 edges
4. `GameViewModel` - 37 edges
5. `SwiftUI` - 30 edges
6. `Chain` - 29 edges
7. `Tile` - 27 edges
8. `EnvironmentManager` - 27 edges
9. `SnapshotDTO` - 27 edges
10. `MatchController` - 25 edges

## Surprising Connections (you probably didn't know these)
- `main()` --calls--> `isTracked`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `probability`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `totalProbabilityMass`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `markTileKnown`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `applyOpponentDraw`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Determinized Search Pipeline** — sources_isolynengine_determinizer, sources_isolynengine_simulationengine, sources_isolynengine_searchengine, sources_isolynengine_beliefstate, sources_isolynengine_probabilityengine [EXTRACTED 1.00]
- **Bridge Safety Mechanism Stack** — docs_bridge_architecture_handle_table_design, docs_bridge_architecture_state_versioning, docs_bridge_architecture_per_session_mutex, docs_bridge_architecture_pod_only_boundary, docs_bridge_architecture_snapshot_hidden_info [EXTRACTED 1.00]
- **Hidden Information System** — sources_isolynengine_beliefstate, sources_isolynengine_probabilityengine, docs_bridge_architecture_snapshot_hidden_info, docs_strategy_notes_lockdown_double [INFERRED 0.95]

## Communities (122 total, 40 thin omitted)

### Community 0 - "Bridge Analysis Pipeline"
Cohesion: 0.12
Nodes (19): Element, Hashable, os, Sendable, ChainSide, left, right, MatchFormat (+11 more)

### Community 1 - "Dealer & Tile Accounting"
Cohesion: 0.09
Nodes (19): map, deque, vector, uniformIndexBelow, vector, shuffle(), RoundOutcomeKind, RoundOutcome (+11 more)

### Community 2 - "Environment Clock System"
Cohesion: 0.10
Nodes (19): GraphicsContext, RandomNumberGenerator, StarFieldView, Int, UInt64, CGSize, Double, WeatherEffectView (+11 more)

### Community 3 - "Snapshot DTO Contract"
Cohesion: 0.16
Nodes (14): GameMode, EvaluationEngine::evaluate(), handValueOf(), BlockingHeuristic, score, ClosingOpportunityHeuristic, kNextRoundStartBonus, score (+6 more)

### Community 4 - "Star Field Rendering"
Cohesion: 0.19
Nodes (14): Chain, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles, placeLeft, placeOpening (+6 more)

### Community 5 - "Move Legality Gate"
Cohesion: 0.10
Nodes (24): BeliefState::applyOpponentDraw(), BeliefState::totalProbabilityMass(), map, mt19937_64, pair, vector, Determinizer::sample(), BeliefState (+16 more)

### Community 6 - "Swift Runtime Metadata (generated)"
Cohesion: 0.22
Nodes (9): size_t, EntropySource::fillSecureRandomBytes(), EntropySource::nextUint64(), EntropySource::uniformIndexBelow(), EntropySource, fillSecureRandomBytes, nextUint64, uint64_t (+1 more)

### Community 7 - "Expected Value Heuristic"
Cohesion: 0.21
Nodes (4): Calendar, Int, String, TimePhaseTests

### Community 8 - "XCTest Infrastructure (generated)"
Cohesion: 0.09
Nodes (24): AnalysisResultDTO, completed, expectedValuePerPlayer, playerCount, recommendedMove, samplesCompleted, samplesConfigured, stateVersionAnalyzed (+16 more)

### Community 9 - "Engine Core Containers"
Cohesion: 0.15
Nodes (14): CLLocation, previewManager(), Int, LiveWeatherService, SkyCondition, clear, cloudy, fog (+6 more)

### Community 10 - "Swift Testing Library (generated)"
Cohesion: 0.11
Nodes (19): GameModeDTO, SnapshotDTO, boneyardDrawableCount, boneyardLockedCount, boneyardLockedTiles, chain, currentPlayerIndex, decidingPlayerIndex (+11 more)

### Community 11 - "Evaluation Engine Weights"
Cohesion: 0.19
Nodes (24): CommandResultDTO, decidingPlayerIndex, diagnosticMessage, newStateVersion, roundOutcome, status, RoundOutcomeDTO, advanceStateVersion() (+16 more)

### Community 12 - "Simulation & Shuffle Tests"
Cohesion: 0.08
Nodes (27): mutex, playerCountForMode, AnalysisSnapshotImpl, belief, believerPlayerIndex, cancelRequested, mode, stateVersionAnalyzed (+19 more)

### Community 13 - "Swift Value Witness Tables (generated)"
Cohesion: 0.13
Nodes (16): Equatable, AppearanceKeyframe, EnvironmentAppearance, EnvironmentAppearanceCurve, EnvironmentColor, Double, GestureArbiter, GestureOwner (+8 more)

### Community 14 - "Bridge Safety & Verification"
Cohesion: 0.33
Nodes (10): bridge_match_begin(), bridge_session_create_first_round(), bridge_session_create_subsequent_round(), ChainSideDTO, GameModeDTO, Move, isValidMode(), toEngine() (+2 more)

### Community 15 - "Sandbox Mode Requirements"
Cohesion: 0.20
Nodes (8): NSObjectProtocol, EnvironmentManager, Calendar, Int, Never, Task, Void, EnvironmentManagerTests

### Community 16 - "Belief State Probability Core"
Cohesion: 0.10
Nodes (15): int8_t, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map, vector, DominoTile (+7 more)

### Community 17 - "Round Outcome & Blocking"
Cohesion: 0.18
Nodes (19): Config, BlockingHeuristic::score(), setCurrentPlayerIndex, MoveExecutor, apply, undo, MoveGenerator, generate (+11 more)

### Community 18 - "Score System (Unwired)"
Cohesion: 0.23
Nodes (12): GameMode, MatchController, currentPlayerHasLegalMove, dealFirstRound, dealSubsequentRound, endTurnWithNoPlay, m_mode, m_state (+4 more)

### Community 19 - "Appearance Curve Interpolation"
Cohesion: 0.13
Nodes (14): OpeningDecision, openingPlayerIndex, openingTile, PlayRecord, playerIndex, tile, GameMode, pair (+6 more)

### Community 20 - "Chain Layout & Undo"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 21 - "Weather Condition Enum"
Cohesion: 0.12
Nodes (12): AtmosphericBackgroundView, EnvironmentSettingsView, EnvironmentView, LegibilityScrim, PipGlyph, CGFloat, Int, View (+4 more)

### Community 22 - "DominoTile Identity"
Cohesion: 0.33
Nodes (6): EvaluationEngine, evaluate, kBlockingWeight, kClosingOpportunityWeight, kExpectedValueWeight, kMobilityWeight

### Community 23 - "RulesEngine Decisions"
Cohesion: 0.09
Nodes (15): AppKit, CoreLocation, Foundation, EnvironmentState, Date, Double, String, Double (+7 more)

### Community 24 - "Boneyard Draw Mechanics"
Cohesion: 0.22
Nodes (13): AnalysisHandle, bridge_analysis_request_cancel(), bridge_analysis_snapshot_create(), bridge_analysis_snapshot_destroy(), bridge_get_snapshot(), bridge_session_close(), SessionHandle, ensureCurrentPlayerCanMove() (+5 more)

### Community 25 - "Analysis Snapshot Internals"
Cohesion: 0.29
Nodes (9): GameMode, PlacementKind, vector, GameState::drawTile(), GameState::GameState(), GameState::playTile(), GameState::setCurrentPlayerIndex(), GameState::undoDrawTile() (+1 more)

### Community 26 - "App Navigation State"
Cohesion: 0.18
Nodes (12): MatchHandle, BridgeStatus, MatchResultDTO, matchEnded, nextRoundStarterIndex, participantCount, scoresPerParticipant, status (+4 more)

### Community 27 - "GameState Mutation & Undo"
Cohesion: 0.15
Nodes (12): ButtonStyle, Configuration, Font, PrimaryCapsuleButtonStyle, InteractiveGameBoardView, Bool, Int, MatchFormat (+4 more)

### Community 28 - "Environment Manager Lifecycle"
Cohesion: 0.06
Nodes (34): 1a. F‑04 — EnvironmentManager / LiveWeatherService race closure, 1b. F‑10 — Cancel-on-abandon for analyses, 1c. F‑11 — BeliefState divide-by-zero guard (ENGINE CHANGE — test-first, house rule #5), 2a. F‑07 — Truthful failure for unknown analysis handles, 2b. F‑08 — Observable divergence on unknown DTO enums, 2c. F‑12 — HandleTable comment truthing, 3a. CI pipeline, 3b. Full sanitizer baseline (post-fix code) (+26 more)

### Community 29 - "Search Decision Output"
Cohesion: 0.22
Nodes (10): AppliedMove, kind, move, playerIndex, PlacementKind, MoveValidator, isLegal, Move (+2 more)

### Community 30 - "Fuzz Harness Input Model"
Cohesion: 0.18
Nodes (7): App, IsolynEngineBridge, Observation, Scene, AppState, IsolynApp, SwiftUI

### Community 32 - "Generated Initializers (noise)"
Cohesion: 0.22
Nodes (5): Chain::fromKnownState(), Chain::placeLeft(), Chain::placeOpening(), Chain::placeRight(), deque

### Community 33 - "Match Controller Turn Flow"
Cohesion: 0.20
Nodes (8): ModeCard, ModeOption, Bool, Int, String, Void, ModeSelectorView, String

### Community 34 - "Handle Table Operations"
Cohesion: 0.31
Nodes (7): advanceToNextPlayer, checkForClose, Move, RoundOutcome, MatchController::endTurnWithNoPlay(), MatchController::playTurn(), MatchController::voluntaryDraw()

### Community 35 - "Swift Testing Runner (generated)"
Cohesion: 0.25
Nodes (7): Move, string, Move::describe(), containsMove(), Move, vector, sameHandContents()

### Community 36 - "Environment Data Models"
Cohesion: 0.23
Nodes (12): ProbabilityEngine, constructFromGameState, expectedRemainingValue, observeDraw, observePlay, probabilityHoldsAtLeast, probabilityHoldsTile, SimulationEngine (+4 more)

### Community 37 - "Test Issue Reporting (generated)"
Cohesion: 0.05
Nodes (37): FIX‑01 — Swift test target could not build at all, FIX‑02 — Engine/bridge scripts failed to link on macOS, FIX‑03 — Bridge test harness assumed GNU coreutils, FIX‑04 — SmokeTest deal-randomness flake, part A (blocked-player assumption), FIX‑05 — SmokeTest flake part B (helper spun forever in boneyard-less modes), FIX‑06 — libFuzzer runtime absent from Xcode 26 toolchain (infrastructure), FIX‑07 — Terminal-round guard (audit F‑03): play could continue past a finished round, FIX‑08 — ScoreSystem lacked participant-count accessor (additive) (+29 more)

### Community 38 - "Move Executor Applied-Move"
Cohesion: 0.33
Nodes (5): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles()

### Community 39 - "Generated File Lock Utility"
Cohesion: 0.23
Nodes (7): EnvironmentClock, FixedEnvironmentClock, Date, SystemEnvironmentClock, RandomWeatherService, Double, TimeZone

### Community 40 - "IsolynTheme Design Tokens"
Cohesion: 0.50
Nodes (4): Boneyard::Boneyard(), Boneyard::lockedTiles(), Boneyard::undoDraw(), vector

### Community 41 - "HandleTable Implementation"
Cohesion: 0.25
Nodes (7): Correct-move handling, Cross-cutting implications worth flagging now, Feature Specifications — Training Mode and Sandbox Mode, Sandbox Mode, Training Mode, Visual design, Wrong-move handling

### Community 43 - "Live WeatherKit Service"
Cohesion: 0.07
Nodes (31): Int, HoverChainController, Int, Never, Task, UInt64, Void, HoverChain (+23 more)

### Community 44 - "Hidden-Info Strategy & Bugs"
Cohesion: 0.40
Nodes (3): ComingSoonView, String, Void

### Community 45 - "Chain Placement Ops"
Cohesion: 0.11
Nodes (15): ObjectIdentifier, GameViewModel, Phase, loading, matchOver, playing, roundOver, Bool (+7 more)

### Community 46 - "Determinizer Sampling Internals"
Cohesion: 0.40
Nodes (4): Move, describe, side, tile

### Community 47 - "Mode Card Component"
Cohesion: 0.25
Nodes (14): Gesture, ChainAndZonesView, EndMarker, OrientedTile, Placed, SnakeChainBoard, Bool, CGFloat (+6 more)

### Community 48 - "Swift Enum Metadata (generated)"
Cohesion: 0.19
Nodes (6): EngineSession, Int, Int32, Move, UInt64, CommandOutcome

### Community 50 - "Determinization Test Pair"
Cohesion: 0.10
Nodes (19): 1v1 Strategy — Look-Ahead Depth and Tile-Counting Reasoning, 1v1 Strategy — Skill Gap, Boneyard Draining, Score-Driven Playstyle, and Elite Tactics, 2v2 Strategy — Partner Communication and Coordination, Both decisions are estimation-driven, not rule-driven, Claimed look-ahead depth at high-level play, Closing is sometimes chosen over a visible Domino path, Definition: "missing a set", Draining the entire boneyard: a real, high-variance, high-skill tactic (+11 more)

### Community 55 - "Evaluation Breakdown Struct"
Cohesion: 0.10
Nodes (19): 1. EXECUTIVE SUMMARY, 2. ARCHITECTURE MAP, 3. DEAD CODE REPORT, 4. FINDINGS TABLE, 5. SCALABILITY VERDICT, 6. PRIORITIZED REMEDIATION PLAN, 7. WHAT'S GOOD, 8. SINGLE HIGHEST-LEVERAGE NEXT ACTION (+11 more)

### Community 56 - "Closing Opportunity Heuristic"
Cohesion: 0.36
Nodes (6): GameSnapshot, Tile, Bool, Double, Int, TileKnowledgeResolver

### Community 57 - "Pip Glyph Signature"
Cohesion: 0.10
Nodes (21): ExpectedValueHeuristic::score(), GameState, drawTile, m_boneyard, m_chain, m_currentPlayerIndex, m_hands, m_mode (+13 more)

### Community 58 - "Coming Soon Placeholder"
Cohesion: 0.13
Nodes (15): GameMode, vector, ScoreSystem, applyRoundScores, hasMatchEnded, m_mode, m_scores, score (+7 more)

### Community 59 - "Entry Screen"
Cohesion: 0.30
Nodes (9): array, DominoSet, shuffledTiles, main(), main(), main(), check(), string (+1 more)

### Community 60 - "Move Value Type"
Cohesion: 0.12
Nodes (16): 0. HOW TO READ THE PERCENTAGES, 1a. Version control + verification harness repair *(small, blocking everything)*, 1b. Terminal-round guard (F‑03) — the highest-severity unfixed bug, 1c. Match orchestration — the keystone design *(bulk of the phase)*, DEPENDENCY GRAPH (why this order and no other), EFFORT SUMMARY TABLE, FIRST THREE ACTIONS WHEN WORK BEGINS, ISOLYN IMPLEMENTATION ROADMAP (+8 more)

### Community 61 - "Game Placeholder Screen"
Cohesion: 0.12
Nodes (16): 1. WHAT THIS PROJECT IS (plain words), 2. CURRENT STATE — SCOREBOARD (all verified — §6 re-proves everything), 3. FOLDER MAP (every item, one line each), 4. THE LAST BIG SESSION — WHAT / WHY / HOW / WHERE, 5.1 Governing documents (authority order — still binding), 5.2 The sandbox-loss lesson (why "commit often" is house law), 5.3 The twelve ambiguity resolutions (numbering = load-bearing), 5.4 Engine rigor status (stated plainly — do NOT "fix" these) (+8 more)

### Community 62 - "Mode Selector Screen"
Cohesion: 0.16
Nodes (19): RulesEngine, combineTeamValue, computeRoundScores, determineCloser, determineNextRoundStarter, determineOpeningPlay, hasReachedMatchLossThreshold, kOneVsOneMatchLossThreshold (+11 more)

### Community 63 - "Round Outcome Kind"
Cohesion: 0.07
Nodes (29): Codable, AppearanceManager, Double, String, Color, DominoAppearance, EdgeHighlightMode, none (+21 more)

### Community 64 - "Runtime Metadata Fragments (noise)"
Cohesion: 0.15
Nodes (13): Error, BridgeError, boneyardEmpty, bridgeFailure, engineFailure, invalidMove, invalidRequest, noLegalMove (+5 more)

### Community 65 - "Primary Capsule Button Style"
Cohesion: 0.19
Nodes (9): BoardCamera, CGFloat, CGPoint, CGSize, Double, Never, Task, Void (+1 more)

### Community 72 - "Engine Test Script"
Cohesion: 0.15
Nodes (12): Bridge Architecture, Cancellation, Error model, Explicitly out of scope, Match orchestration (added Phase 1), Ownership: handles, not pointers, Snapshot model — hidden information, State versioning (+4 more)

### Community 73 - "POD Boundary Principle"
Cohesion: 0.08
Nodes (24): 10. HAND ORDER AND VISUAL CONSISTENCY, 11. TOP HEADER, 12. SCORE DISPLAY, 13. "DRAW" AND "ANALYZE", 14. INSTRUCTIONS, 15. REMOVE DEBUG-STYLE VISUAL LANGUAGE, 16. SPACING SYSTEM, 17. RESPONSIVE BEHAVIOR (+16 more)

### Community 74 - "Engine Baseline Result"
Cohesion: 0.16
Nodes (7): MatchFormat, MatchCoordinator, Bool, Int, isolyn, MatchFormat, MatchFormat

### Community 75 - "Fuzz Campaign Result"
Cohesion: 0.18
Nodes (10): Bridge bugs found and fixed this pass, Bridge test suite, Bridge Testing, Engine baseline (unchanged scope, reverified after every bridge-related engine change), Engine bugs found and fixed this pass, Environment, Fuzzing, Sanitizers (+2 more)

### Community 76 - "Sanitizer Result"
Cohesion: 0.20
Nodes (9): 1. App shell, 2. Privacy manifest (`PrivacyInfo.xcprivacy`), 3. Usage-description strings (Info.plist), 4. Capabilities & entitlements, 5. Icon & assets, 6. Build, sign, notarize, 7. Pre-flight functional checks on the packaged app, Explicitly out of scope until after UI revival (+1 more)

### Community 77 - "Soak Test Result"
Cohesion: 0.25
Nodes (8): AnalysisTask, Error, isolyn, Task, AnalysisOutcome, Bool, Double, UInt64

### Community 78 - "Match-Level Objective"
Cohesion: 0.23
Nodes (9): ColorEditorRow, DominoAppearanceSection, HueSlider, SettingsDrawer, Bool, CGFloat, Double, String (+1 more)

### Community 79 - "Repository Tree Snapshot"
Cohesion: 0.17
Nodes (19): GameMode, vector, Dealer::deal(), Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode(), Dealer (+11 more)

### Community 80 - "AnalysisSnapshotImpl"
Cohesion: 0.17
Nodes (14): Impl, shared_ptr, bridge_analysis_run(), buildSnapshot(), BridgeStatus, size_t, failedAnalysis(), failedSnapshot() (+6 more)

### Community 82 - "HandRackView"
Cohesion: 0.33
Nodes (6): HandRackView, Bool, CGFloat, Move, Set, Void

### Community 83 - "SimulationEngine::sampleDeterminizedState"
Cohesion: 0.17
Nodes (13): fromKnownState, Determinizer, sample, SearchEngine, chooseBestMove, decisionCriterion, searchNode, mt19937_64 (+5 more)

### Community 84 - "RoundEndOverlay"
Cohesion: 0.43
Nodes (5): RevealRow, RoundEndOverlay, Bool, Int, String

### Community 85 - "Determinizer::sample"
Cohesion: 0.24
Nodes (8): Boneyard::drawNext(), Boneyard, drawNext, lockedTiles, m_tiles, undoDraw, size_t, main()

### Community 86 - "EnvironmentTimeLabel"
Cohesion: 0.60
Nodes (3): DateFormatter, EnvironmentTimeLabel, String

### Community 89 - ".operator()"
Cohesion: 0.20
Nodes (10): Identifiable, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, Screen, comingSoon, entry (+2 more)

### Community 90 - "OpeningDecision"
Cohesion: 0.22
Nodes (9): 29. IMPLEMENTATION ORDER, Step 1 --- Replace the domino renderer, Step 2 --- Rebuild board layout, Step 3 --- Rebuild player hand, Step 4 --- Rebuild header/status, Step 5 --- Rebuild action area, Step 6 --- Responsive pass, Step 7 --- Interaction pass (+1 more)

### Community 112 - "26. EXACT INFORMATION HIERARCHY"
Cohesion: 0.33
Nodes (6): 26. EXACT INFORMATION HIERARCHY, Priority 1, Priority 2, Priority 3, Priority 4, Priority 5

### Community 113 - "THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT."
Cohesion: 0.33
Nodes (6): 2. ABSOLUTE RULE: DOMINOES ARE SINGLE RECTANGLES, Acceptance test, Forbidden implementation, Required geometry, Required implementation model, THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.

### Community 114 - "30. ACCEPTANCE CRITERIA"
Cohesion: 0.33
Nodes (6): 30. ACCEPTANCE CRITERIA, Board, Domino construction, Hand, Layout, Quality

### Community 115 - "EvaluationBreakdown"
Cohesion: 0.33
Nodes (6): EvaluationBreakdown, blocking, closingOpportunity, expectedValue, mobility, total

### Community 116 - "WeatherMode"
Cohesion: 0.40
Nodes (5): CaseIterable, WeatherMode, live, off, randomized

### Community 117 - "3. DOMINO TILE SPECIFICATION"
Cohesion: 0.40
Nodes (5): 3. DOMINO TILE SPECIFICATION, Base tile, Center divider, Pips, Tile silhouette

### Community 118 - "DealResult"
Cohesion: 0.50
Nodes (4): DealResult, boneyard, hands, vector

## Knowledge Gaps
- **426 isolated node(s):** `PackageDescription`, `oneVOne`, `oneVOneVOne`, `twoVTwo`, `entry` (+421 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **40 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `DominoTile` connect `Belief State Probability Core` to `Dealer & Tile Accounting`, `Star Field Rendering`, `Move Legality Gate`, `Evaluation Engine Weights`, `Bridge Safety & Verification`, `Round Outcome & Blocking`, `Score System (Unwired)`, `Appearance Curve Interpolation`, `Analysis Snapshot Internals`, `Generated Initializers (noise)`, `Handle Table Operations`, `Swift Testing Runner (generated)`, `Move Executor Applied-Move`, `IsolynTheme Design Tokens`, `Determinizer Sampling Internals`, `TimePhase Classification`, `Pip Glyph Signature`, `Entry Screen`, `Repository Tree Snapshot`, `Determinizer::sample`, `DealResult`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Why does `GameState` connect `Pip Glyph Signature` to `Dealer & Tile Accounting`, `Snapshot DTO Contract`, `Star Field Rendering`, `Move Legality Gate`, `Simulation & Shuffle Tests`, `Belief State Probability Core`, `Round Outcome & Blocking`, `Score System (Unwired)`, `Appearance Curve Interpolation`, `Analysis Snapshot Internals`, `App Navigation State`, `Search Decision Output`, `Swift Testing Runner (generated)`, `Environment Data Models`, `Mode Selector Screen`, `Repository Tree Snapshot`, `AnalysisSnapshotImpl`, `SimulationEngine::sampleDeterminizedState`, `Determinizer::sample`?**
  _High betweenness centrality (0.036) - this node is a cross-community bridge._
- **Why does `View` connect `Weather Condition Enum` to `Match Controller Turn Flow`, `Environment Clock System`, `Live WeatherKit Service`, `Hidden-Info Strategy & Bugs`, `Match-Level Objective`, `Mode Card Component`, `HandRackView`, `RoundEndOverlay`, `EnvironmentTimeLabel`, `GameState Mutation & Undo`, `Round Outcome Kind`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `GameState` (e.g. with `bridge_match_record_round()` and `buildSnapshot()`) actually correct?**
  _`GameState` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `oneVOne`, `oneVOneVOne` to the rest of the system?**
  _426 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Bridge Analysis Pipeline` be split into smaller, more focused modules?**
  _Cohesion score 0.12258064516129032 - nodes in this community are weakly interconnected._
- **Should `Dealer & Tile Accounting` be split into smaller, more focused modules?**
  _Cohesion score 0.09146341463414634 - nodes in this community are weakly interconnected._