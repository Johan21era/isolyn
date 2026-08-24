# Graph Report - /Users/johanrembeci/Desktop/Isolyn-current_4  (2026-08-24)

## Corpus Check
- 130 files · ~224,279 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1077 nodes · 2172 edges · 80 communities (64 shown, 16 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 191 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

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

## God Nodes (most connected - your core abstractions)
1. `DominoTile` - 61 edges
2. `GameState` - 51 edges
3. `Chain` - 29 edges
4. `EnvironmentManager` - 27 edges
5. `SnapshotDTO` - 26 edges
6. `MatchController` - 25 edges
7. `ValueWitnessTable` - 23 edges
8. `BeliefState` - 23 edges
9. `EvaluationEngine::evaluate()` - 21 edges
10. `SearchEngine::chooseBestMove()` - 21 edges

## Surprising Connections (you probably didn't know these)
- `Missing-A-Set Threshold` --references--> `ProbabilityEngine::probabilityHoldsAtLeast()`  [INFERRED]
  docs/STRATEGY_NOTES.md → Sources/IsolynEngine/ProbabilityEngine.cpp
- `main()` --calls--> `isTracked`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `probability`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `totalProbabilityMass`  [INFERRED]
  Tests/IsolynEngineTests/ProbabilityEngineTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `markTileKnown`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Determinized Search Pipeline** — sources_isolynengine_determinizer, sources_isolynengine_simulationengine, sources_isolynengine_searchengine, sources_isolynengine_beliefstate, sources_isolynengine_probabilityengine [EXTRACTED 1.00]
- **Bridge Safety Mechanism Stack** — docs_bridge_architecture_handle_table_design, docs_bridge_architecture_state_versioning, docs_bridge_architecture_per_session_mutex, docs_bridge_architecture_pod_only_boundary, docs_bridge_architecture_snapshot_hidden_info [EXTRACTED 1.00]
- **Hidden Information System** — sources_isolynengine_beliefstate, sources_isolynengine_probabilityengine, docs_bridge_architecture_snapshot_hidden_info, docs_strategy_notes_lockdown_double [INFERRED 0.95]

## Communities (80 total, 16 thin omitted)

### Community 0 - "Bridge Analysis Pipeline"
Cohesion: 0.06
Nodes (49): Two-Phase Analysis Design, Element, Equatable, Error, Cxx Interop Uncertainties, IsolynEngineBridge, Sendable, AnalysisTask (+41 more)

### Community 1 - "Dealer & Tile Accounting"
Cohesion: 0.05
Nodes (49): Twelve Documented Rules Ambiguity Resolutions, GameMode, vector, Dealer::deal(), Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode() (+41 more)

### Community 2 - "Environment Clock System"
Cohesion: 0.11
Nodes (11): IsolynApp, FixedEnvironmentClock, Date, SystemEnvironmentClock, Calendar, EnvironmentManagerTests, Int, String (+3 more)

### Community 3 - "Snapshot DTO Contract"
Cohesion: 0.07
Nodes (34): ChainDTO, count, leftEnd, rightEnd, tiles, ChainSideDTO, GameModeDTO, LegalMovesDTO (+26 more)

### Community 4 - "Star Field Rendering"
Cohesion: 0.10
Nodes (19): CGSize, GraphicsContext, RandomNumberGenerator, StarFieldView, Int, UInt64, Double, WeatherEffectView (+11 more)

### Community 5 - "Move Legality Gate"
Cohesion: 0.13
Nodes (27): MoveValidator, isLegal, Move, MoveExecutor::apply(), CommandResultDTO, decidingPlayerIndex, diagnosticMessage, newStateVersion (+19 more)

### Community 6 - "Swift Runtime Metadata (generated)"
Cohesion: 0.11
Nodes (13): TypeMetadataTrait<bool>, TypeMetadataTrait<float>, TypeMetadataTrait<int16_t>, TypeMetadataTrait<int32_t>, TypeMetadataTrait<int64_t>, TypeMetadataTrait<int8_t>, TypeMetadataTrait<swift::Int>, TypeMetadataTrait<uint16_t> (+5 more)

### Community 7 - "Expected Value Heuristic"
Cohesion: 0.10
Nodes (21): ExpectedValueHeuristic::score(), GameState, drawTile, m_boneyard, m_chain, m_currentPlayerIndex, m_hands, m_mode (+13 more)

### Community 8 - "XCTest Infrastructure (generated)"
Cohesion: 0.19
Nodes (15): XCTestCase, SwiftPMXCTestObserver, TestBundleEventRecord, TestCaseEventRecord, TestEvent, finish, start, TestEventRecord (+7 more)

### Community 9 - "Engine Core Containers"
Cohesion: 0.20
Nodes (4): array, map, deque, vector

### Community 10 - "Swift Testing Library (generated)"
Cohesion: 0.19
Nodes (22): Bool, String, UInt64, TestAttachment, TestBundle, TestCase, TestCaseFailureRecord, TestErrorInfo (+14 more)

### Community 11 - "Evaluation Engine Weights"
Cohesion: 0.15
Nodes (22): Config, EvaluationEngine, evaluate, kBlockingWeight, kClosingOpportunityWeight, kExpectedValueWeight, kMobilityWeight, setCurrentPlayerIndex (+14 more)

### Community 12 - "Simulation & Shuffle Tests"
Cohesion: 0.16
Nodes (13): DominoSet, shuffledTiles, SimulationEngine, sampleDeterminizedState, main(), main(), main(), freshOneVsOnePosition() (+5 more)

### Community 13 - "Swift Value Witness Tables (generated)"
Cohesion: 0.09
Nodes (21): ValueWitnessTable, assignWithCopy, assignWithTake, destroy, extraInhabitantCount, flags, getEnumTagSinglePayload, initializeBufferWithCopyOfBuffer (+13 more)

### Community 14 - "Bridge Safety & Verification"
Cohesion: 0.17
Nodes (20): Handle Tables Instead Of Raw Pointers, Per-Session Mutex Defense In Depth, Player-Scoped Snapshot Model, State-Version Staleness Rejection, Bridge Smoke Suite 33 Checks, bridge_get_snapshot(), bridge_session_create_first_round(), bridge_session_create_subsequent_round() (+12 more)

### Community 15 - "Sandbox Mode Requirements"
Cohesion: 0.14
Nodes (16): PositionConstructor Requirement, Sandbox Mode Free Construction, GameMode, EvaluationEngine::evaluate(), handValueOf(), BlockingHeuristic, score, ClosingOpportunityHeuristic (+8 more)

### Community 16 - "Belief State Probability Core"
Cohesion: 0.13
Nodes (19): Missing-A-Set Threshold, BeliefState::applyOpponentDraw(), BeliefState::totalProbabilityMass(), BeliefState, applyOpponentDraw, isTracked, kBoneyardLocation, m_distributions (+11 more)

### Community 17 - "Round Outcome & Blocking"
Cohesion: 0.15
Nodes (16): RoundOutcome, BlockingHeuristic::score(), advanceToNextPlayer, checkForClose, MoveGenerator, hasAnyLegalMove, isPositionClosed, Move (+8 more)

### Community 18 - "Score System (Unwired)"
Cohesion: 0.12
Nodes (16): Explicitly Out Of Scope Items, GameMode, vector, ScoreSystem, applyRoundScores, hasMatchEnded, m_mode, m_scores (+8 more)

### Community 19 - "Appearance Curve Interpolation"
Cohesion: 0.25
Nodes (8): AppearanceKeyframe, EnvironmentAppearance, EnvironmentAppearanceCurve, EnvironmentColor, Color, Double, EnvironmentAppearanceCurveTests, XCTestCase

### Community 20 - "Chain Layout & Undo"
Cohesion: 0.18
Nodes (15): Chain, fromKnownState, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles, placeLeft (+7 more)

### Community 21 - "Weather Condition Enum"
Cohesion: 0.14
Nodes (16): CaseIterable, Hashable, previewManager(), Int, SkyCondition, clear, cloudy, fog (+8 more)

### Community 22 - "DominoTile Identity"
Cohesion: 0.12
Nodes (11): int8_t, string, DominoTile::describe(), DominoTile, describe, kMaxPips, kMinPips, m_high (+3 more)

### Community 23 - "RulesEngine Decisions"
Cohesion: 0.18
Nodes (18): RulesEngine, combineTeamValue, computeRoundScores, determineCloser, determineNextRoundStarter, determineOpeningPlay, hasReachedMatchLossThreshold, kOneVsOneMatchLossThreshold (+10 more)

### Community 24 - "Boneyard Draw Mechanics"
Cohesion: 0.17
Nodes (12): Boneyard::Boneyard(), Boneyard::drawNext(), Boneyard::lockedTiles(), Boneyard::undoDraw(), vector, Boneyard, drawNext, lockedTiles (+4 more)

### Community 25 - "Analysis Snapshot Internals"
Cohesion: 0.13
Nodes (15): AnalysisSnapshotImpl, belief, believerPlayerIndex, cancelRequested, mode, stateVersionAnalyzed, world, atomic (+7 more)

### Community 26 - "App Navigation State"
Cohesion: 0.15
Nodes (14): App, Scene, AppState, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, Screen (+6 more)

### Community 27 - "GameState Mutation & Undo"
Cohesion: 0.17
Nodes (14): undoDrawTile Order Dependency Bug, Engine Has Zero Internal Concurrency Support, GameMode, PlacementKind, vector, GameState::drawTile(), GameState::GameState(), GameState::playTile() (+6 more)

### Community 28 - "Environment Manager Lifecycle"
Cohesion: 0.28
Nodes (7): Never, NSObjectProtocol, EnvironmentManager, Calendar, Int, Task, Void

### Community 29 - "Search Decision Output"
Cohesion: 0.16
Nodes (15): SearchEngine, chooseBestMove, decisionCriterion, AnalysisResultDTO, completed, expectedValuePerPlayer, playerCount, recommendedMove (+7 more)

### Community 30 - "Fuzz Harness Input Model"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 31 - "Environment UI Components"
Cohesion: 0.20
Nodes (9): AtmosphericBackgroundView, EnvironmentSettingsView, EnvironmentTimeLabel, String, EnvironmentView, LegibilityScrim, RootView, SwiftUI (+1 more)

### Community 32 - "Generated Initializers (noise)"
Cohesion: 0.15
Nodes (4): XCTAttachment, XCTSourceCodeContext, XCTSourceCodeFrame, XCTSourceCodeLocation

### Community 33 - "Match Controller Turn Flow"
Cohesion: 0.26
Nodes (12): GameMode, MatchController, currentPlayerHasLegalMove, dealFirstRound, dealSubsequentRound, endTurnWithNoPlay, m_mode, m_state (+4 more)

### Community 34 - "Handle Table Operations"
Cohesion: 0.26
Nodes (9): AnalysisHandle, bridge_analysis_request_cancel(), bridge_analysis_snapshot_destroy(), bridge_session_close(), firstIllegalMove(), main(), currentRssKb(), main() (+1 more)

### Community 35 - "Swift Testing Runner (generated)"
Cohesion: 0.18
Nodes (9): Android, Runner, CRT, Darwin.C, Glibc, Musl, Testing, WASILibc (+1 more)

### Community 36 - "Environment Data Models"
Cohesion: 0.17
Nodes (7): AppKit, Foundation, Observation, EnvironmentState, Date, Double, String

### Community 37 - "Test Issue Reporting (generated)"
Cohesion: 0.17
Nodes (10): Int, TestIssueType, assertionFailure, performanceRegression, system, thrownError, uncaughtException, unknown (+2 more)

### Community 38 - "Move Executor Applied-Move"
Cohesion: 0.17
Nodes (10): Assert-Only Legality Precondition, AppliedMove, kind, move, playerIndex, Move, PlacementKind, string (+2 more)

### Community 39 - "Generated File Lock Utility"
Cohesion: 0.24
Nodes (5): FileLock, T, CInt, HANDLE, URL

### Community 40 - "IsolynTheme Design Tokens"
Cohesion: 0.29
Nodes (5): Configuration, Font, View, IsolynTheme, CGFloat

### Community 41 - "HandleTable Implementation"
Cohesion: 0.22
Nodes (9): Impl, shared_ptr, size_t, mutex, HandleTable, m_entries, m_mutex, m_nextId (+1 more)

### Community 42 - "ProbabilityEngine Queries"
Cohesion: 0.31
Nodes (10): ProbabilityEngine, constructFromGameState, expectedRemainingValue, observeDraw, observePlay, probabilityHoldsAtLeast, probabilityHoldsTile, bridge_analysis_snapshot_create() (+2 more)

### Community 43 - "Live WeatherKit Service"
Cohesion: 0.22
Nodes (6): CLLocation, CoreLocation, LiveWeatherService, WeatherCondition, WeatherKit, WeatherService

### Community 44 - "Hidden-Info Strategy & Bugs"
Cohesion: 0.20
Nodes (9): OneVsOneVsOne BeliefState Accounting Crash, Boneyard Full-Drain Line, Locking Down An Inferred Double, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map (+1 more)

### Community 45 - "Chain Placement Ops"
Cohesion: 0.20
Nodes (6): Playing For Your Partner, Chain::fromKnownState(), Chain::placeLeft(), Chain::placeOpening(), Chain::placeRight(), deque

### Community 46 - "Determinizer Sampling Internals"
Cohesion: 0.20
Nodes (6): map, mt19937_64, pair, vector, Determinizer::sample(), ProbabilityEngine::expectedRemainingValue()

### Community 47 - "Mode Card Component"
Cohesion: 0.25
Nodes (8): Identifiable, ModeCard, ModeOption, Bool, Color, Int, String, Void

### Community 48 - "Swift Enum Metadata (generated)"
Cohesion: 0.25
Nodes (8): EnumValueWitnessTable, destructiveInjectEnumTag, destructiveProjectEnumData, getEnumTag, vwTable, EnumValueWitnessDestructiveInjectEnumTagTy, EnumValueWitnessDestructiveProjectEnumDataTy, EnumValueWitnessGetEnumTagTy

### Community 49 - "TimePhase Classification"
Cohesion: 0.29
Nodes (7): Double, TimePhase, afternoon, morning, morningToAfternoonTransition, night, primeDay

### Community 50 - "Determinization Test Pair"
Cohesion: 0.38
Nodes (5): Determinizer, sample, mt19937_64, SimulationEngine::sampleDeterminizedState(), main()

### Community 51 - "Search Decision Struct"
Cohesion: 0.29
Nodes (7): Move, vector, SearchDecision, completed, expectedValuePerPlayer, move, samplesCompleted

### Community 52 - "Future Work & Known Bugs"
Cohesion: 0.33
Nodes (5): Blocked Current Player UB Found By Fuzzing, ExplanationEngine Requirement, Training Mode Puzzle Loop, Five-To-Seven Ply Lookahead Calibration Target, DifficultyModel Awaiting User Confirmation

### Community 53 - "DominoSet Construction"
Cohesion: 0.33
Nodes (5): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles()

### Community 54 - "Random Weather Source"
Cohesion: 0.60
Nodes (3): EnvironmentClock, RandomWeatherService, Double

### Community 55 - "Evaluation Breakdown Struct"
Cohesion: 0.33
Nodes (6): EvaluationBreakdown, blocking, closingOpportunity, expectedValue, mobility, total

### Community 56 - "Closing Opportunity Heuristic"
Cohesion: 0.40
Nodes (4): Closing Vs Domino Tradeoff, Score-Proximity Playstyle Shift, ClosingOpportunityHeuristic::score(), vector

### Community 57 - "Pip Glyph Signature"
Cohesion: 0.40
Nodes (4): PipGlyph, CGFloat, Color, Int

### Community 58 - "Coming Soon Placeholder"
Cohesion: 0.40
Nodes (3): ComingSoonView, String, Void

### Community 59 - "Entry Screen"
Cohesion: 0.40
Nodes (3): EntryView, String, Void

### Community 60 - "Move Value Type"
Cohesion: 0.40
Nodes (4): Move, describe, side, tile

### Community 61 - "Game Placeholder Screen"
Cohesion: 0.50
Nodes (3): GamePlaceholderView, MatchFormat, String

### Community 63 - "Round Outcome Kind"
Cohesion: 0.50
Nodes (4): RoundOutcomeKind, RoundOutcome, decidingPlayerIndex, kind

### Community 64 - "Runtime Metadata Fragments (noise)"
Cohesion: 0.67
Nodes (3): MetadataResponseTy, _1, _Null_unspecified

## Knowledge Gaps
- **210 isolated node(s):** `_Null_unspecified`, `_1`, `initializeBufferWithCopyOfBuffer`, `destroy`, `initializeWithCopy` (+205 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Two-Phase Analysis Design` connect `Bridge Analysis Pipeline` to `Future Work & Known Bugs`?**
  _High betweenness centrality (0.460) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Environment Data Models` to `Bridge Analysis Pipeline`, `Environment Clock System`, `Swift Testing Runner (generated)`, `Star Field Rendering`, `Live WeatherKit Service`, `Appearance Curve Interpolation`, `Weather Condition Enum`?**
  _High betweenness centrality (0.366) - this node is a cross-community bridge._
- **Why does `GameState` connect `Expected Value Heuristic` to `Dealer & Tile Accounting`, `Move Legality Gate`, `Engine Core Containers`, `Evaluation Engine Weights`, `Simulation & Shuffle Tests`, `Bridge Safety & Verification`, `Sandbox Mode Requirements`, `Belief State Probability Core`, `Round Outcome & Blocking`, `Chain Layout & Undo`, `DominoTile Identity`, `RulesEngine Decisions`, `Boneyard Draw Mechanics`, `Analysis Snapshot Internals`, `GameState Mutation & Undo`, `Match Controller Turn Flow`, `Move Executor Applied-Move`, `ProbabilityEngine Queries`, `Determinization Test Pair`?**
  _High betweenness centrality (0.278) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `GameState` (e.g. with `buildSnapshot()` and `main()`) actually correct?**
  _`GameState` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Chain` (e.g. with `SimulationEngine::sampleDeterminizedState()` and `main()`) actually correct?**
  _`Chain` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `EnvironmentManager` (e.g. with `IsolynApp` and `.test_init_capturesTimeOfDayMinutes()`) actually correct?**
  _`EnvironmentManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `_Null_unspecified`, `_1`, `initializeBufferWithCopyOfBuffer` to the rest of the system?**
  _210 weakly-connected nodes found - possible documentation gaps or missing edges._