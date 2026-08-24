# Graph Report - /Users/johanrembeci/Desktop/Isolyn-current_4  (2026-08-24)

## Corpus Check
- 27 files · ~70,160 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 946 nodes · 1858 edges · 100 communities (48 shown, 52 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 185 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99

## God Nodes (most connected - your core abstractions)
1. `DominoTile` - 61 edges
2. `GameState` - 51 edges
3. `Chain` - 29 edges
4. `EnvironmentManager` - 27 edges
5. `SnapshotDTO` - 26 edges
6. `MatchController` - 25 edges
7. `BeliefState` - 23 edges
8. `EvaluationEngine::evaluate()` - 21 edges
9. `SearchEngine::chooseBestMove()` - 21 edges
10. `SkyCondition` - 20 edges

## Surprising Connections (you probably didn't know these)
- `Missing-A-Set Threshold` --references--> `ProbabilityEngine::probabilityHoldsAtLeast()`  [INFERRED]
  docs/STRATEGY_NOTES.md → Sources/IsolynEngine/ProbabilityEngine.cpp
- `main()` --calls--> `markTileKnown`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `applyOpponentDraw`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `lockedTiles`  [INFERRED]
  Tests/IsolynEngineTests/BoneyardTests.cpp → Sources/IsolynEngine/include/Boneyard.hpp
- `main()` --calls--> `placeLeft`  [INFERRED]
  Tests/IsolynEngineTests/ChainTests.cpp → Sources/IsolynEngine/include/Chain.hpp

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Determinized Search Pipeline** — sources_isolynengine_determinizer, sources_isolynengine_simulationengine, sources_isolynengine_searchengine, sources_isolynengine_beliefstate, sources_isolynengine_probabilityengine [EXTRACTED 1.00]
- **Bridge Safety Mechanism Stack** — docs_bridge_architecture_handle_table_design, docs_bridge_architecture_state_versioning, docs_bridge_architecture_per_session_mutex, docs_bridge_architecture_pod_only_boundary, docs_bridge_architecture_snapshot_hidden_info [EXTRACTED 1.00]
- **Hidden Information System** — sources_isolynengine_beliefstate, sources_isolynengine_probabilityengine, docs_bridge_architecture_snapshot_hidden_info, docs_strategy_notes_lockdown_double [INFERRED 0.95]

## Communities (100 total, 52 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.05
Nodes (50): CLLocation, Two-Phase Analysis Design, Element, Error, IsolynEngineBridge, Sendable, AnalysisTask, EngineSession (+42 more)

### Community 1 - "Community 1"
Cohesion: 0.06
Nodes (37): array, map, Boneyard, drawNext, lockedTiles, m_tiles, undoDraw, deque (+29 more)

### Community 2 - "Community 2"
Cohesion: 0.07
Nodes (27): CGSize, Equatable, GraphicsContext, RandomNumberGenerator, StarFieldView, Int, UInt64, Double (+19 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (44): Explicitly Out Of Scope Items, PositionConstructor Requirement, Sandbox Mode Free Construction, GameMode, EvaluationEngine::evaluate(), handValueOf(), BlockingHeuristic, score (+36 more)

### Community 4 - "Community 4"
Cohesion: 0.06
Nodes (39): ExpectedValueHeuristic::score(), Chain, fromKnownState, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles (+31 more)

### Community 5 - "Community 5"
Cohesion: 0.07
Nodes (35): Missing-A-Set Threshold, BeliefState::applyOpponentDraw(), BeliefState::totalProbabilityMass(), map, mt19937_64, pair, vector, Determinizer::sample() (+27 more)

### Community 6 - "Community 6"
Cohesion: 0.07
Nodes (38): GameMode, vector, Dealer::deal(), Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode(), size_t (+30 more)

### Community 7 - "Community 7"
Cohesion: 0.10
Nodes (12): IsolynApp, FixedEnvironmentClock, Date, SystemEnvironmentClock, Calendar, EnvironmentManagerTests, Int, String (+4 more)

### Community 8 - "Community 8"
Cohesion: 0.11
Nodes (20): ChainDTO, count, leftEnd, rightEnd, tiles, ChainSideDTO, LegalMovesDTO, count (+12 more)

### Community 9 - "Community 9"
Cohesion: 0.12
Nodes (17): CaseIterable, Hashable, previewManager(), Int, SkyCondition, clear, cloudy, fog (+9 more)

### Community 10 - "Community 10"
Cohesion: 0.11
Nodes (21): GameModeDTO, SnapshotDTO, boneyardDrawableCount, boneyardLockedCount, boneyardLockedTiles, chain, currentPlayerIndex, decidingPlayerIndex (+13 more)

### Community 11 - "Community 11"
Cohesion: 0.23
Nodes (19): CommandResultDTO, decidingPlayerIndex, diagnosticMessage, newStateVersion, roundOutcome, status, RoundOutcomeDTO, bridge_end_turn_with_no_play() (+11 more)

### Community 12 - "Community 12"
Cohesion: 0.12
Nodes (16): AnalysisSnapshotImpl, belief, believerPlayerIndex, cancelRequested, mode, stateVersionAnalyzed, world, atomic (+8 more)

### Community 13 - "Community 13"
Cohesion: 0.15
Nodes (14): App, Scene, AppState, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, Screen (+6 more)

### Community 14 - "Community 14"
Cohesion: 0.20
Nodes (15): Handle Tables Instead Of Raw Pointers, Per-Session Mutex Defense In Depth, Player-Scoped Snapshot Model, State-Version Staleness Rejection, Bridge Smoke Suite 33 Checks, advanceStateVersion(), bridge_session_create_first_round(), bridge_session_create_subsequent_round() (+7 more)

### Community 15 - "Community 15"
Cohesion: 0.28
Nodes (7): Never, NSObjectProtocol, EnvironmentManager, Calendar, Int, Task, Void

### Community 16 - "Community 16"
Cohesion: 0.14
Nodes (9): int8_t, DominoTile, describe, kMaxPips, kMinPips, m_high, m_low, hash<isolyn::DominoTile> (+1 more)

### Community 17 - "Community 17"
Cohesion: 0.27
Nodes (13): BlockingHeuristic::score(), MoveExecutor, apply, undo, MoveGenerator, generate, hasAnyLegalMove, isPositionClosed (+5 more)

### Community 18 - "Community 18"
Cohesion: 0.20
Nodes (13): GameMode, MatchController, currentPlayerHasLegalMove, dealSubsequentRound, endTurnWithNoPlay, m_mode, m_state, playTurn (+5 more)

### Community 19 - "Community 19"
Cohesion: 0.16
Nodes (11): OpeningDecision, openingPlayerIndex, openingTile, GameMode, pair, vector, RulesEngine::computeRoundScores(), RulesEngine::determineCloser() (+3 more)

### Community 20 - "Community 20"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 21 - "Community 21"
Cohesion: 0.20
Nodes (9): AtmosphericBackgroundView, EnvironmentSettingsView, EnvironmentTimeLabel, String, EnvironmentView, LegibilityScrim, RootView, SwiftUI (+1 more)

### Community 22 - "Community 22"
Cohesion: 0.18
Nodes (13): Config, EvaluationEngine, evaluate, kBlockingWeight, kClosingOpportunityWeight, kExpectedValueWeight, kMobilityWeight, SimulationEngine (+5 more)

### Community 23 - "Community 23"
Cohesion: 0.17
Nodes (11): EnvironmentState, Date, Double, String, Double, TimePhase, afternoon, morning (+3 more)

### Community 24 - "Community 24"
Cohesion: 0.30
Nodes (10): AnalysisHandle, bridge_analysis_request_cancel(), bridge_analysis_run(), bridge_analysis_snapshot_create(), bridge_analysis_snapshot_destroy(), bridge_session_close(), main(), currentRssKb() (+2 more)

### Community 25 - "Community 25"
Cohesion: 0.26
Nodes (10): undoDrawTile Order Dependency Bug, GameMode, PlacementKind, vector, GameState::drawTile(), GameState::GameState(), GameState::playTile(), GameState::setCurrentPlayerIndex() (+2 more)

### Community 26 - "Community 26"
Cohesion: 0.17
Nodes (12): AnalysisResultDTO, completed, expectedValuePerPlayer, playerCount, recommendedMove, samplesCompleted, samplesConfigured, stateVersionAnalyzed (+4 more)

### Community 27 - "Community 27"
Cohesion: 0.29
Nodes (5): Configuration, Font, View, IsolynTheme, CGFloat

### Community 28 - "Community 28"
Cohesion: 0.20
Nodes (9): Impl, shared_ptr, size_t, HandleTable, m_entries, m_mutex, m_nextId, unique_ptr (+1 more)

### Community 29 - "Community 29"
Cohesion: 0.22
Nodes (10): AppliedMove, kind, move, playerIndex, PlacementKind, MoveValidator, isLegal, Move (+2 more)

### Community 30 - "Community 30"
Cohesion: 0.20
Nodes (5): AppKit, CoreLocation, Foundation, Observation, WeatherKit

### Community 31 - "Community 31"
Cohesion: 0.20
Nodes (9): OneVsOneVsOne BeliefState Accounting Crash, Boneyard Full-Drain Line, Locking Down An Inferred Double, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map (+1 more)

### Community 32 - "Community 32"
Cohesion: 0.20
Nodes (6): Playing For Your Partner, Chain::fromKnownState(), Chain::placeLeft(), Chain::placeOpening(), Chain::placeRight(), deque

### Community 33 - "Community 33"
Cohesion: 0.25
Nodes (8): Identifiable, ModeCard, ModeOption, Bool, Color, Int, String, Void

### Community 34 - "Community 34"
Cohesion: 0.31
Nodes (7): RoundOutcome, advanceToNextPlayer, checkForClose, Move, MatchController::endTurnWithNoPlay(), MatchController::playTurn(), MatchController::voluntaryDraw()

### Community 35 - "Community 35"
Cohesion: 0.25
Nodes (7): Move, string, Move::describe(), containsMove(), Move, vector, sameHandContents()

### Community 36 - "Community 36"
Cohesion: 0.31
Nodes (7): SearchEngine, chooseBestMove, decisionCriterion, searchNode, freshOneVsOnePosition(), main(), main()

### Community 37 - "Community 37"
Cohesion: 0.29
Nodes (7): Move, vector, SearchDecision, completed, expectedValuePerPlayer, move, samplesCompleted

### Community 38 - "Community 38"
Cohesion: 0.33
Nodes (5): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles()

### Community 39 - "Community 39"
Cohesion: 0.60
Nodes (3): EnvironmentClock, RandomWeatherService, Double

### Community 40 - "Community 40"
Cohesion: 0.40
Nodes (5): Boneyard::Boneyard(), Boneyard::drawNext(), Boneyard::lockedTiles(), Boneyard::undoDraw(), vector

### Community 41 - "Community 41"
Cohesion: 0.40
Nodes (4): Blocked Current Player UB Found By Fuzzing, ExplanationEngine Requirement, Training Mode Puzzle Loop, Five-To-Seven Ply Lookahead Calibration Target

### Community 42 - "Community 42"
Cohesion: 0.40
Nodes (4): Closing Vs Domino Tradeoff, Score-Proximity Playstyle Shift, ClosingOpportunityHeuristic::score(), vector

### Community 43 - "Community 43"
Cohesion: 0.40
Nodes (4): PipGlyph, CGFloat, Color, Int

### Community 44 - "Community 44"
Cohesion: 0.40
Nodes (3): ComingSoonView, String, Void

### Community 45 - "Community 45"
Cohesion: 0.40
Nodes (3): EntryView, String, Void

### Community 46 - "Community 46"
Cohesion: 0.40
Nodes (4): Move, describe, side, tile

### Community 50 - "Community 50"
Cohesion: 0.67
Nodes (3): PlayRecord, playerIndex, tile

## Knowledge Gaps
- **171 isolated node(s):** `XCTest`, `PackageDescription`, `oneVOne`, `oneVOneVOne`, `twoVTwo` (+166 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **52 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Two-Phase Analysis Design` connect `Community 0` to `Community 41`?**
  _High betweenness centrality (0.399) - this node is a cross-community bridge._
- **Why does `GameState` connect `Community 4` to `Community 1`, `Community 3`, `Community 35`, `Community 5`, `Community 6`, `Community 36`, `Community 10`, `Community 12`, `Community 16`, `Community 17`, `Community 50`, `Community 18`, `Community 22`, `Community 25`, `Community 29`?**
  _High betweenness centrality (0.281) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Community 30` to `Community 0`, `Community 2`, `Community 7`, `Community 9`, `Community 23`?**
  _High betweenness centrality (0.265) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `GameState` (e.g. with `buildSnapshot()` and `main()`) actually correct?**
  _`GameState` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Chain` (e.g. with `SimulationEngine::sampleDeterminizedState()` and `main()`) actually correct?**
  _`Chain` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `EnvironmentManager` (e.g. with `IsolynApp` and `.test_init_capturesTimeOfDayMinutes()`) actually correct?**
  _`EnvironmentManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `XCTest`, `PackageDescription`, `oneVOne` to the rest of the system?**
  _171 weakly-connected nodes found - possible documentation gaps or missing edges._