# Graph Report - Isolyn-current_4  (2026-11-15)

## Corpus Check
- 250 files · ~293,697 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3435 nodes · 6791 edges · 202 communities (174 shown, 28 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 428 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7a77f172`
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
- ._run
- benchmarkMode
- IsolynV2.0 — Open Decisions & Architecture Records
- _make_run
- OPS-34 — Closeout Initiative (2026-11-14: local sweep, docs drift, graph refresh)
- cli.py
- run_tier
- Isolyn Offline Lab (scaffold)
- Search Performance: Compact Transposition Table
- DatasetTests
- ._run
- Isolyn Self-Play Harness (scaffold)
- ComingSoonView
- DrawFlightView
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
- Phase
- CalibrationTests
- Determinizer::sample
- IsolynApp
- GestureArbiter
- OPS-40 — Private Kaggle bridge, stable RNG and portable self-play (2026-11-14)
- buildAllTiles
- build.sh
- .automaticMove
- Dealer
- BuildScriptTests
- buildSnapshot
- compare.py
- GestureArbiter
- build.sh
- CenteredContent
- ComingSoonView
- BlockingHeuristic::score
- OPS-47 — Fix the live Kaggle handoff (2026-11-15)
- OPS-38 — Offline lab streaming fold and merge optimization (2026-11-14)
- RoundOutcome
- OPS-39 — Offline lab quality-of-life pass (2026-11-14)
- OPS-35 — Phase 1–2: bounded search, secret locked pair, sets and One Domino (2026-11-14)
- DrawFlightView
- CommandOutcome
- Move
- OPS-41 — Verify the Kaggle code snapshot on both sides (2026-11-14)
- OPS-42 — Validate cloud CSV plan fields and reject symlinks (2026-11-14)
- OPS-43 — Plain-language reports beside every run (2026-11-15)
- OPS-44 — Visual report and raw-file map (2026-11-15)
- OPS-45 — Staged cloud source and the first 10K app path (2026-11-15)
- OPS-46 — Make the cloud next action unambiguous (2026-11-15)
- OPS-36 — R-17 private locked-pair look (2026-11-14)
- OPS-37 — R-22 1v1v1 elimination and the carried-points duel (2026-11-14)
- _winner
- depth_probe.sh
- rules_soak.sh

## God Nodes (most connected - your core abstractions)
1. `GameState` - 84 edges
2. `DominoTile` - 69 edges
3. `SESSION: ENGINE/SEARCH/EVALUATION OVERHAUL + METAL BATCH EVALUATOR (2026-11-11)` - 66 edges
4. `GameViewModel` - 60 edges
5. `Tile` - 56 edges
6. `LabService` - 54 edges
7. `SwiftUI` - 42 edges
8. `SearchContext` - 37 edges
9. `Color` - 35 edges
10. `InteractiveGameBoardView` - 35 edges

## Surprising Connections (you probably didn't know these)
- `bridge_match_record_round()` --calls--> `handValue()`  [INFERRED]
  Sources/IsolynEngineBridge/IsolynBridge.cpp → Accelerator/shaders/evaluation.metal
- `HandTapRouterTests` --calls--> `Tile`  [INFERRED]
  Tests/IsolynAppTests/HandTapRouterTests.swift → Sources/IsolynApp/Engine/EngineTypes.swift
- `main()` --calls--> `markTileKnown`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `applyOpponentDraw`  [INFERRED]
  Tests/IsolynEngineTests/BeliefStateTests.cpp → Sources/IsolynEngine/include/BeliefState.hpp
- `main()` --calls--> `lockedTiles`  [INFERRED]
  Tests/IsolynEngineTests/BoneyardTests.cpp → Sources/IsolynEngine/include/Boneyard.hpp

## Import Cycles
- 1-file cycle: `lab/src/isolyn_lab/cloud.py -> lab/src/isolyn_lab/cloud.py`

## Communities (202 total, 28 thin omitted)

### Community 0 - "Appearance"
Cohesion: 0.04
Nodes (48): 0. Design correction — Offsuit-minimal (2026-11-12), 10. Implementation phases, 11. Acceptance criteria, 12. Risks and boundaries, 13. Immediate next slice, 1. Verdict, 2. What exists today, 3. Product direction: The Table (+40 more)

### Community 2 - "Root Docs"
Cohesion: 0.11
Nodes (20): Darwin, pid_t, Process, Handle, LabLaunching, LabProcessHandle, LabService, ProcessLabLauncher (+12 more)

### Community 3 - "Hoverchain"
Cohesion: 0.06
Nodes (34): 1a. F‑04 — EnvironmentManager / LiveWeatherService race closure, 1b. F‑10 — Cancel-on-abandon for analyses, 1c. F‑11 — BeliefState divide-by-zero guard (ENGINE CHANGE — test-first, house rule #5), 2a. F‑07 — Truthful failure for unknown analysis handles, 2b. F‑08 — Observable divergence on unknown DTO enums, 2c. F‑12 — HandleTable comment truthing, 3a. CI pipeline, 3b. Full sanitizer baseline (post-fix code) (+26 more)

### Community 4 - "Include"
Cohesion: 0.10
Nodes (21): Alignment, Binding, Font, PrimaryCapsuleButtonStyle, CGFloat, Configuration, View, LabRunDetailView (+13 more)

### Community 5 - "Isolynapptests"
Cohesion: 0.08
Nodes (24): kKillerSlots, kMaxHistoryPlayers, kMoveCodeCount, atomic, SearchContext, aborted, cancelRequested, deadline (+16 more)

### Community 6 - "Include"
Cohesion: 0.15
Nodes (5): vector, array, map, deque, main()

### Community 7 - "Root Docs"
Cohesion: 0.10
Nodes (19): GraphicsContext, RandomNumberGenerator, StarFieldView, Int, UInt64, CGSize, Double, WeatherEffectView (+11 more)

### Community 8 - "Isolynenginebridge"
Cohesion: 0.14
Nodes (31): CommandResultDTO, decidingPlayerIndex, diagnosticMessage, newStateVersion, roundOutcome, status, RoundOutcomeDTO, advanceStateVersion() (+23 more)

### Community 9 - "Game"
Cohesion: 0.10
Nodes (16): ObjectIdentifier, DrawEvent, GameViewModel, Bool, Int, MatchFormat, Move, Never (+8 more)

### Community 10 - "Environment"
Cohesion: 0.14
Nodes (13): CLLocation, CoreLocation, Sendable, LiveWeatherService, SkyCondition, clear, cloudy, fog (+5 more)

### Community 11 - "Isolynenginebridge"
Cohesion: 0.06
Nodes (36): AnalysisSnapshotImpl, belief, believerPlayerIndex, cancelRequested, mode, stateVersionAnalyzed, world, atomic (+28 more)

### Community 12 - "Include"
Cohesion: 0.09
Nodes (54): _atomic_json(), build_parser(), _check_run_id(), _clean(), _command(), _count_rows(), _csv_complete(), _default_run_id() (+46 more)

### Community 13 - "Isolynapptests"
Cohesion: 0.17
Nodes (5): Calendar, EnvironmentManagerTests, Int, String, TimePhaseTests

### Community 14 - "Game"
Cohesion: 0.11
Nodes (15): GeometryProxy, BoardFrameKey, HandDragModel, HandDragPreview, InteractiveGameBoardView, SeatItem, Bool, CGFloat (+7 more)

### Community 15 - "Include"
Cohesion: 0.05
Nodes (41): int8_t, BeliefState::BeliefState(), BeliefState::isTracked(), BeliefState::markTileKnown(), BeliefState::probability(), map, vector, Chain::fromKnownState() (+33 more)

### Community 16 - "Isolynengine"
Cohesion: 0.07
Nodes (31): GameState, enforceOneDominoRule, hash, m_boneyard, m_chain, m_currentPlayerIndex, m_hands, m_mode (+23 more)

### Community 17 - "Include"
Cohesion: 0.09
Nodes (65): _allowlisted_files(), assemble(), _atomic_json(), build_parser(), _build_sessions(), _build_shards(), _code_digest(), _code_manifest() (+57 more)

### Community 18 - "Engine"
Cohesion: 0.12
Nodes (37): MoveExecutor, apply, undo, array, GameMode, Move, mt19937_64, uint8_t (+29 more)

### Community 19 - "Include"
Cohesion: 0.08
Nodes (37): BeliefState::applyOpponentDraw(), BeliefState::totalProbabilityMass(), BeliefState, applyOpponentDraw, isTracked, kBoneyardLocation, m_distributions, m_tracked (+29 more)

### Community 20 - "Include"
Cohesion: 0.10
Nodes (21): GameModeDTO, SnapshotDTO, boneyardDrawableCount, boneyardLockedCount, boneyardLockedTiles, chain, currentPlayerIndex, decidingPlayerIndex (+13 more)

### Community 21 - "Include"
Cohesion: 0.17
Nodes (14): GameSnapshot, Tile, CGPoint, CGRect, Move, HandTileFramesKey, CGRect, Bool (+6 more)

### Community 22 - "Engine"
Cohesion: 0.12
Nodes (18): Element, os, AnalysisOutcome, MatchFormat, MatchOutcome, Move, RoundOutcome, closed (+10 more)

### Community 23 - "Include"
Cohesion: 0.09
Nodes (23): MatchResultDTO, activeParticipantCount, activePerParticipant, eliminatedPerParticipant, lastEliminatedParticipantIndex, matchEnded, nextRoundIsSurvivor, nextRoundStarterIndex (+15 more)

### Community 24 - "Root Docs"
Cohesion: 0.33
Nodes (6): size_t, vector, PositionBatch, playerCount, rows, PositionRow

### Community 25 - "Components"
Cohesion: 0.06
Nodes (37): ChainSide, left, right, BoardDropTargetFrames, ChainAndZonesView, EndEdgeHighlight, EndTarget, GameSurfaceCoordinateSpace (+29 more)

### Community 26 - "Hoverchain"
Cohesion: 0.07
Nodes (41): Decodable, Entry, File, LabCloudLedger, LabCloudPlan, LabCloudService, LabCloudSource, Phase (+33 more)

### Community 27 - "Include"
Cohesion: 0.12
Nodes (18): GameMode, vector, ScoreSystem, applyRoundScores, applyRoundScoresForParticipants, hasMatchEnded, m_mode, m_oneVsOneTarget (+10 more)

### Community 28 - "Include"
Cohesion: 0.18
Nodes (15): Chain, m_leftEnd, m_leftEndHistory, m_rightEnd, m_rightEndHistory, m_tiles, placeLeft, placeOpening (+7 more)

### Community 29 - "Isolynenginetests"
Cohesion: 0.18
Nodes (11): DominoSet, shuffledTiles, approxEqual(), main(), main(), main(), main(), main() (+3 more)

### Community 30 - "Environment"
Cohesion: 0.12
Nodes (19): Hashable, NSObjectProtocol, previewManager(), Int, EnvironmentClock, EnvironmentManager, Calendar, Int (+11 more)

### Community 31 - "Isolynapp"
Cohesion: 0.07
Nodes (27): 1a. Darwin RSS reader, 1b. Make "couldn't measure" loud instead of silently green, 1c. Verify the measurement is REAL before trusting it, 2a. Extract pure layout metrics (testability first), 2b. Auto-fit scale (uniform ⇒ the 2:1 law survives), 2c. Content-aware camera bounds, 2d. The GameSnapshot TEST SEAM (shared infrastructure with Phase 3), 3a. Fix the math to match the claim (or the claim to match the math — math wins) (+19 more)

### Community 32 - "Engine"
Cohesion: 0.15
Nodes (13): _args(), CollectTests, _csv(), FetchTests, _make_workspace(), _make_workspace_files(), PlanTests, PrepareTests (+5 more)

### Community 33 - "Isolynengine"
Cohesion: 0.29
Nodes (6): AppearanceKeyframe, EnvironmentAppearance, EnvironmentAppearanceCurve, EnvironmentColor, Double, EnvironmentAppearanceCurveTests

### Community 34 - "Isolynengine"
Cohesion: 0.14
Nodes (14): OpeningDecision, openingPlayerIndex, openingTile, matchLossThreshold, GameMode, pair, vector, RulesEngine::computeRoundScores() (+6 more)

### Community 35 - "Include"
Cohesion: 0.13
Nodes (14): AnyObject, Notification, NSApplication, NSApplicationDelegate, NSObject, IsolynAppDelegate, NSWindow, RestorableWindow (+6 more)

### Community 36 - "Engine"
Cohesion: 0.14
Nodes (13): Error, BridgeError, boneyardEmpty, bridgeFailure, engineFailure, invalidMove, invalidRequest, noLegalMove (+5 more)

### Community 37 - "Isolynenginebridgetests"
Cohesion: 0.30
Nodes (13): FuzzedDataProvider, consumeMode(), consumeMove(), consumePlayerIndex(), consumeSessionHandleGuess(), consumeSide(), consumeTile(), consumeVersion() (+5 more)

### Community 38 - "Environment"
Cohesion: 0.15
Nodes (11): EnvironmentState, Date, Double, String, Double, TimePhase, afternoon, morning (+3 more)

### Community 39 - "Include"
Cohesion: 0.15
Nodes (29): playTile, setCurrentPlayerIndex, GameMode, MatchController, canVoluntaryDraw, currentPlayerHasLegalMove, dealFirstRound, dealSubsequentRound (+21 more)

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
Cohesion: 0.14
Nodes (13): LabAnalysisService, Date, Int32, String, TimeInterval, URL, UUID, FakeLauncher (+5 more)

### Community 46 - "Include"
Cohesion: 0.08
Nodes (24): 10. HAND ORDER AND VISUAL CONSISTENCY, 11. TOP HEADER, 12. SCORE DISPLAY, 13. "DRAW" AND "ANALYZE", 14. INSTRUCTIONS, 15. REMOVE DEBUG-STYLE VISUAL LANGUAGE, 16. SPACING SYSTEM, 17. RESPONSIVE BEHAVIOR (+16 more)

### Community 47 - "SamplePool"
Cohesion: 0.12
Nodes (16): condition_variable, function, kMaxWorkers, mutex, unique_ptr, SamplePool, m_done, m_generation (+8 more)

### Community 48 - "Root Docs"
Cohesion: 0.23
Nodes (6): HoverChainController, Int, Never, Task, UInt64, Void

### Community 49 - "Game"
Cohesion: 0.06
Nodes (30): 1. Authority model, 2. Verdict register, 3. Contradiction register, 4. Per-document findings, 5. Numeric claim verification, 6. What changed in this pass, 7. Residual risks, A10. `design/UI_CHARTER.md` (was `UI_UX_OVERHAUL.md`) (+22 more)

### Community 50 - "Include"
Cohesion: 0.10
Nodes (19): 1. EXECUTIVE SUMMARY, 2. ARCHITECTURE MAP, 3. DEAD CODE REPORT, 4. FINDINGS TABLE, 5. SCALABILITY VERDICT, 6. PRIORITIZED REMEDIATION PLAN, 7. WHAT'S GOOD, 8. SINGLE HIGHEST-LEVERAGE NEXT ACTION (+11 more)

### Community 51 - "Isolynenginebridge"
Cohesion: 0.10
Nodes (19): 1v1 Strategy — Look-Ahead Depth and Tile-Counting Reasoning, 1v1 Strategy — Skill Gap, Boneyard Draining, Score-Driven Playstyle, and Elite Tactics, 2v2 Strategy — Partner Communication and Coordination, Both decisions are estimation-driven, not rule-driven, Claimed look-ahead depth at high-level play, Closing is sometimes chosen over a visible Domino path, Definition: "missing a set", Draining the entire boneyard: a real, high-variance, high-skill tactic (+11 more)

### Community 52 - "Isolynengine"
Cohesion: 0.05
Nodes (41): FIX‑01 — Swift test target could not build at all, FIX‑02 — Engine/bridge scripts failed to link on macOS, FIX‑03 — Bridge test harness assumed GNU coreutils, FIX‑04 — SmokeTest deal-randomness flake, part A (blocked-player assumption), FIX‑05 — SmokeTest flake part B (helper spun forever in boneyard-less modes), FIX‑06 — libFuzzer runtime absent from Xcode 26 toolchain (infrastructure), FIX‑07 — Terminal-round guard (audit F‑03): play could continue past a finished round, FIX‑08 — ScoreSystem lacked participant-count accessor (additive) (+33 more)

### Community 53 - "Root Docs"
Cohesion: 0.10
Nodes (24): AppearanceManager, Double, String, Color, DominoAppearance, EdgeHighlightMode, none, standard (+16 more)

### Community 54 - "EnvironmentClock"
Cohesion: 0.21
Nodes (7): DateFormatter, EnvironmentTimeLabel, String, FixedEnvironmentClock, Date, SystemEnvironmentClock, TimeZone

### Community 55 - "Include"
Cohesion: 0.10
Nodes (21): int16_t, size_t, uint64_t, mixTTKey(), startTableIfNeeded(), TranspositionTable, m_bucketCount, m_bucketMask (+13 more)

### Community 56 - "Include"
Cohesion: 0.17
Nodes (28): bridge_analysis_snapshot_create(), bridge_analysis_snapshot_destroy(), bridge_get_snapshot(), bridge_match_begin(), bridge_match_begin_with_format(), bridge_match_begin_with_format_and_target(), bridge_match_close(), bridge_match_create_next_round() (+20 more)

### Community 57 - "Include"
Cohesion: 0.12
Nodes (16): 1. WHAT THIS PROJECT IS (plain words), 2. SCOREBOARD — 2026-08 SNAPSHOT (§6 re-proves the 2026-08 gates), 3. FOLDER MAP (every item, one line each), 4. THE LAST BIG SESSION — WHAT / WHY / HOW / WHERE, 5.1 Governing documents (authority order — still binding), 5.2 The sandbox-loss lesson (why "commit often" is house law), 5.3 The twelve ambiguity resolutions (numbering = load-bearing), 5.4 Engine rigor status (stated plainly — do NOT "fix" these) (+8 more)

### Community 58 - "Root Docs"
Cohesion: 0.10
Nodes (25): CodingKey, Decoder, CodingKeys, config, createdAt, resumedAt, runId, shards (+17 more)

### Community 59 - "Environment"
Cohesion: 0.06
Nodes (36): Backend, capabilities, evaluate, BatchView, featureCount, features, playerCount, positionCount (+28 more)

### Community 60 - "ISOLYN IMPLEMENTATION ROADMAP"
Cohesion: 0.12
Nodes (17): 0. HOW TO READ THE PERCENTAGES, 1a. Version control + verification harness repair *(small, blocking everything)*, 1b. Terminal-round guard (F‑03) — the highest-severity unfixed bug, 1c. Match orchestration — the keystone design *(bulk of the phase)*, DEPENDENCY GRAPH (why this order and no other), EFFORT SUMMARY TABLE, FIRST THREE ACTIONS WHEN WORK BEGINS, ISOLYN IMPLEMENTATION ROADMAP (+9 more)

### Community 61 - "Include"
Cohesion: 0.09
Nodes (24): HoverChain, HoverChainEntry, HoverChainNodeKind, baseUninformed, complete, historicalInformed, lockedOff, predictive (+16 more)

### Community 62 - "Components"
Cohesion: 0.12
Nodes (16): 10. Documentation claims verification, 11. Security and reliability assessment, 14. Technical debt and architectural weaknesses, 15. Implemented strengths, 16. Missing, incomplete and broken functionality, 18. Development history and timeline, 1. Executive summary, 20. Critical priorities and recommended actions (+8 more)

### Community 64 - "Views"
Cohesion: 0.23
Nodes (10): HandRackView, Bool, CGFloat, CGPoint, CGSize, Gesture, Move, Set (+2 more)

### Community 65 - "Isolynengine"
Cohesion: 0.16
Nodes (8): FakeHandle, FakeLauncher, LabServiceTests, Int, Int32, String, URL, Void

### Community 66 - "Include"
Cohesion: 0.14
Nodes (31): _atomic_json(), _atomic_text(), build_parser(), _check(), _checks(), _column_key(), _empty_participant(), generate() (+23 more)

### Community 67 - "Root Docs"
Cohesion: 0.15
Nodes (12): Architecture, Backend rules, Build and run, Contracts, Correctness gates, Decision, Files, Integration plan (+4 more)

### Community 68 - "Root Docs"
Cohesion: 0.14
Nodes (14): App integration (2026-11-14), Boundary, Cloud batch bridge (2026-11-14), Components, Data contracts, `lab/` — Python lab, Measured baseline (2026-11-11), Milestones (+6 more)

### Community 70 - "Isolynengine"
Cohesion: 0.06
Nodes (29): ButtonStyle, PreferenceKey, AtmosphericBackgroundView, EnvironmentView, LegibilityScrim, BoneyardAnchorKey, BoneyardFaceDownTile, BoneyardPressStyle (+21 more)

### Community 71 - "Include"
Cohesion: 0.09
Nodes (21): config, depth, determinizations, games, games_per_shard, mode, opponent_depth, opponent_determinizations (+13 more)

### Community 72 - "Isolynenginebridgetests"
Cohesion: 0.15
Nodes (16): LabCard, LabLink, LabSectionTitle, LabStatusPill, Bool, Content, String, View (+8 more)

### Community 73 - "Root Docs"
Cohesion: 0.14
Nodes (14): Bridge Architecture, Cancellation, Error model, Explicitly out of scope, Latency budget, Match orchestration (added Phase 1), Ownership: handles, not pointers, Snapshot model — hidden information (+6 more)

### Community 74 - "Root Docs"
Cohesion: 0.18
Nodes (8): ModeCard, ModeOption, Bool, String, Void, ModeSelectorView, CGFloat, String

### Community 77 - "Root Docs"
Cohesion: 0.18
Nodes (11): 0. Provenance, 1. How a rule binds, 2. Vocabulary, 3. The rules, A. Winning a hand and scoring it, B. Dealing and opening, C. Drawing, D. Scoring a hand (+3 more)

### Community 78 - "Root Docs"
Cohesion: 0.13
Nodes (26): atomic_json(), collect_shard(), main(), Path, Popen, require(), run(), shard_command() (+18 more)

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
Cohesion: 0.10
Nodes (22): Equatable, MatchFormat, oneVOne, oneVOneVOne, twoVTwo, Screen, comingSoon, entry (+14 more)

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
Cohesion: 0.12
Nodes (17): map, mt19937_64, pair, vector, Determinizer::sample(), Determinizer, sample, mt19937_64 (+9 more)

### Community 87 - "30. ACCEPTANCE CRITERIA"
Cohesion: 0.25
Nodes (7): Correct-move handling, Cross-cutting implications worth flagging now, Feature Specifications — Training Mode and Sandbox Mode, Sandbox Mode, Training Mode, Visual design, Wrong-move handling

### Community 88 - "EnvironmentTests.swift"
Cohesion: 0.22
Nodes (18): ofstream, ostream, RootAggregation, applyWeightList(), GameMode, string, string_view, uint64_t (+10 more)

### Community 89 - "3. DOMINO TILE SPECIFICATION"
Cohesion: 0.11
Nodes (18): 1. Executive scorecard, 2. Findings that matter, 3. Verification actually executed on `347a5b8`, 4. What the repository genuinely supports, 5. What is missing or not production-ready, 6. Priority order, 7. Verdict, CRITICAL — mode-mismatched round recording crashed the process (+10 more)

### Community 90 - "DealResult"
Cohesion: 0.11
Nodes (28): EvalParams, componentCount, playerCount, positionCount, EvalPositionParams, playerCount, positionCount, handValue() (+20 more)

### Community 91 - "RoundOutcome"
Cohesion: 0.11
Nodes (21): CaseIterable, Int, AILevel, casual, club, elite, expert, legendary (+13 more)

### Community 92 - "4. BOARD MUST LOOK LIKE A DOMINO BOARD"
Cohesion: 0.25
Nodes (8): Benchmark Baseline (VOID), Environment, ⛔ Everything above this line is VOID, Game shape, Measured 1v1 ladder (seed 42, alternating seats, no time cap), Other modes (seed 42, 500 games each, 2/8 vs 5/40), Reference configurations, Timing

### Community 93 - "9. PLAYER HAND"
Cohesion: 0.29
Nodes (6): Components and LOC, IsolynV2.0 Project Inventory, Naming boundary, Relevant callers, Repository layout, Where new code belongs

### Community 94 - "DOMINOES UI FIX --- NON-NEGOTIABLE REBUILD MANDATE"
Cohesion: 0.25
Nodes (7): Bridge Testing, Current verification matrix, Environment, Historical findings, Not covered, What the bridge suite covers, Whole-game conformance soak

### Community 96 - "README.md"
Cohesion: 0.28
Nodes (14): build_html(), full_view(), load_graph(), load_json(), main(), node_id(), Any, Counter (+6 more)

### Community 97 - "IsolynV2.0 — Open Decisions & Architecture Records"
Cohesion: 0.16
Nodes (6): Architecture, Documentation, IsolynV2.0, Project identity, Run, Status

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
Cohesion: 0.20
Nodes (12): AnalysisHandle, Impl, shared_ptr, bridge_analysis_request_cancel(), bridge_analysis_run(), bridge_analysis_run_with_budget(), size_t, HandleTable (+4 more)

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
Cohesion: 0.48
Nodes (4): GestureArbiter, Bool, CGFloat, CGPoint

### Community 109 - "Blocked-Current-Player Analysis UB (Fuzz-Found)"
Cohesion: 0.31
Nodes (4): FileManager, LabPaths, Bool, URL

### Community 110 - "Bridge Testing (Verification Record)"
Cohesion: 0.37
Nodes (12): _columns(), _field(), _fixed_ints(), _int(), iter_games(), load_games(), _optional_int(), Path (+4 more)

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
Cohesion: 0.30
Nodes (6): HorizontalAlignment, LabAnalysisView, Int, Set, String, URL

### Community 118 - "Closing vs Domino-Run Decision (Estimation-Driven)"
Cohesion: 0.67
Nodes (3): 12.1 Measured, 12.2 Structural issues, 12. Performance and scalability assessment

### Community 119 - "Strategy Notes (Domain Knowledge for Engine Contributors)"
Cohesion: 0.67
Nodes (3): 8.1 What exists, 8.2 Findings, 8. Frontend and UI/UX assessment

### Community 121 - "1v1 Look-Ahead Depth (5–7 Moves)"
Cohesion: 0.20
Nodes (10): Alternatives, for when Kaggle is the wrong shape, Blockers addressed in code (2026-11-14), First step — one session, one day, Kaggle Bridge — Free Cloud Compute for the Offline Lab, Risks worth stating plainly, Session contract, The arithmetic, The bridge, in five pieces (+2 more)

### Community 128 - "EvaluationBreakdown"
Cohesion: 0.20
Nodes (10): EvaluationBreakdown, blocking, closingOpportunity, expectedValue, mobility, pipControl, teamSupport, tempo (+2 more)

### Community 129 - "STRENGTH_BASELINE.md"
Cohesion: 0.33
Nodes (6): Measured search depth under the 15-second budgets (not a strength claim), Protocol for any number recorded here, Results, Strength Baseline — the only home for playing-strength claims, The tomorrow run — plan before games, What changed, and why the old numbers do not transfer

### Community 130 - ".record"
Cohesion: 0.29
Nodes (5): LayoutProbe, Bool, CGFloat, CGSize, Int

### Community 131 - "rules_audit.py"
Cohesion: 0.47
Nodes (5): anchor_of(), cells(), main(), Split a markdown table row into its cells., Interpret `path :: section` as (path, section).

### Community 132 - "OPS-27 — Analyses in the app, and the opponent default they exposed"
Cohesion: 0.40
Nodes (5): Analyses, Evidence (literal), OPS-27 — Analyses in the app, and the opponent default they exposed, Technical but friendly, The finding

### Community 134 - "createFirstRound"
Cohesion: 0.22
Nodes (7): Isolyn cloud bridge, Limits and deliberate exclusions, One-time setup, Session contract, Small first run, Verification locally, What is safe by construction

### Community 135 - "lab"
Cohesion: 0.50
Nodes (3): lab script, PYTHONDONTWRITEBYTECODE, PYTHONPATH

### Community 138 - "._run"
Cohesion: 0.49
Nodes (5): CompletedProcess, _make_root(), Path, _spec(), WorkerTests

### Community 139 - "benchmarkMode"
Cohesion: 0.31
Nodes (10): Fn, benchmarkMode(), array, GameMode, size_t, main(), makeFixture(), median() (+2 more)

### Community 140 - "IsolynV2.0 — Open Decisions & Architecture Records"
Cohesion: 0.22
Nodes (8): ADR-001 — Product languages: C++20 + Swift; Python offline only, ADR-002 — Offline lab and trainer, ADR-003 — Metal accelerator is a first-class backend, ADR-004 — One source of game truth, ADR-005 — Every production search has a wall-clock cap, ADR-006 — The locked pair is never publicly revealed, IsolynV2.0 — Open Decisions & Architecture Records, Open questions

### Community 141 - "_make_run"
Cohesion: 0.47
Nodes (4): _make_run(), _manifest(), Path, ReportTests

### Community 142 - "OPS-34 — Closeout Initiative (2026-11-14: local sweep, docs drift, graph refresh)"
Cohesion: 0.25
Nodes (8): CI, Cleanup (allowlist only), Commits analysed (`1352063..4a1af04`), Documentation updated, Graphs refreshed (both artifacts), Not done, deliberately, OPS-34 — Closeout Initiative (2026-11-14: local sweep, docs drift, graph refresh), Verification sweep (literal output, local only)

### Community 143 - "cli.py"
Cohesion: 0.32
Nodes (6): build_parser(), _evaluate(), main(), ArgumentParser, Namespace, Offline lab for Isolyn.  CSV loading and calibration reports are implemented. Tr

### Community 144 - "run_tier"
Cohesion: 0.57
Nodes (7): count_rows(), main(), parse_time_record(), Path, run_tier(), start_shard(), sum_csv_columns()

### Community 145 - "Isolyn Offline Lab (scaffold)"
Cohesion: 0.20
Nodes (10): Boundary, Cloud batch runs, IsolynV2.0 Offline Lab, Large runs (resumable), Layout, Non-goals, Planned milestones, Quality-of-life checks (+2 more)

### Community 146 - "Search Performance: Compact Transposition Table"
Cohesion: 0.29
Nodes (6): Limits, Method, Output parity check, Results, Search Performance: Compact Transposition Table, What changed

### Community 148 - "._run"
Cohesion: 0.48
Nodes (3): MergeTests, Path, Build a manifest with (index, seed, games) shards, each with 2 rows/game.

### Community 149 - "Isolyn Self-Play Harness (scaffold)"
Cohesion: 0.33
Nodes (5): Build and run, CSV fields, IsolynV2.0 Self-Play Generator, Modes, What it deliberately does not do yet

### Community 150 - "ComingSoonView"
Cohesion: 0.13
Nodes (15): RoundOutcomeKind, vector, GameSummary, aDepth, aDeterminizations, bDepth, bDeterminizations, decidingPlayer (+7 more)

### Community 151 - "DrawFlightView"
Cohesion: 0.38
Nodes (6): DrawFlightView, FlyingFaceDownTile, Bool, CGFloat, CGPoint, Double

### Community 152 - "Move"
Cohesion: 0.11
Nodes (18): Options, aggregation, depth, determinizations, games, mode, opponentAggregation, opponentDepth (+10 more)

### Community 153 - "build_parser"
Cohesion: 0.11
Nodes (28): analyze(), CalibrationReport, elo_from_score(), elo_interval(), participant_label(), ParticipantStats, Counter, _rank() (+20 more)

### Community 154 - "DominoTile.cpp"
Cohesion: 0.18
Nodes (11): MoveRow, depthReached, evaluation, exactEndgame, moveIndex, nodes, player, side (+3 more)

### Community 155 - "benchmarkMode"
Cohesion: 0.10
Nodes (23): EvaluationBatch, componentCount, features, playerCount, positionCount, size_t, GameMode, vector (+15 more)

### Community 158 - "MetalAccelerator.mm"
Cohesion: 0.18
Nodes (10): DifficultyModel, kMaxStrength, kMaxTileConsumingActions, kMinStrength, kProfiles, DifficultyProfile, determinizationCount, maxDepthPlies (+2 more)

### Community 160 - "Options"
Cohesion: 0.09
Nodes (33): GameMode, vector, Dealer::deal(), Dealer::excludedTilesForMode(), Dealer::handSizeForMode(), Dealer::isMisdeal(), Dealer::playerCountForMode(), Dealer (+25 more)

### Community 161 - "XCTestCase"
Cohesion: 0.12
Nodes (18): Codable, ColorEditorRow, DominoAppearanceSection, HueSlider, InspectionSection, SettingsDrawer, Bool, CGFloat (+10 more)

### Community 162 - "EvaluationWeights"
Cohesion: 0.08
Nodes (49): GameMode, vector, encodePositionBatch(), GameMode, optional, evaluateAllImpl(), EvaluationEngine::evaluate(), EvaluationEngine::evaluateAll() (+41 more)

### Community 163 - "Dealer.cpp"
Cohesion: 0.20
Nodes (5): BoneyardRulesTests, MatchFormat, ResponsiveLayoutTests, RoundRevealTests, XCTestCase

### Community 164 - "Phase"
Cohesion: 0.29
Nodes (7): Phase, failed, finished, idle, launching, running, stopped

### Community 166 - "Determinizer::sample"
Cohesion: 0.25
Nodes (8): size_t, uint64_t, uint8_t, EntropySource::fillSecureRandomBytes(), EntropySource::nextUint64(), EntropySource::uniformIndexBelow(), fillSecureRandomBytes, nextUint64

### Community 167 - "IsolynApp"
Cohesion: 0.33
Nodes (4): App, Scene, AppState, IsolynApp

### Community 168 - "GestureArbiter"
Cohesion: 0.18
Nodes (6): MatchCoordinator, Bool, Int, isolyn, MatchFormat, AIOpponentTests

### Community 169 - "OPS-40 — Private Kaggle bridge, stable RNG and portable self-play (2026-11-14)"
Cohesion: 0.33
Nodes (6): Code and tests, Hosted CI (receipt commit), Limits, stated plainly, OPS-40 — Private Kaggle bridge, stable RNG and portable self-play (2026-11-14), Safety evidence, Verification (literal)

### Community 170 - "buildAllTiles"
Cohesion: 0.33
Nodes (5): index_sequence, buildAllTiles(), array, vector, DominoSet::shuffledTiles()

### Community 172 - ".automaticMove"
Cohesion: 0.25
Nodes (4): HandTapRouter, Bool, Move, HandTapRouterTests

### Community 173 - "Dealer"
Cohesion: 0.44
Nodes (9): Identifiable, LabAnalysisReport, LabEloReport, LabParticipantReport, LabSearchConfig, LabSpearmanReport, Bool, Double (+1 more)

### Community 175 - "buildSnapshot"
Cohesion: 0.06
Nodes (36): AnalysisResultDTO, completed, expectedValuePerPlayer, isDraw, playerCount, recommendedMove, samplesCompleted, samplesConfigured (+28 more)

### Community 176 - "compare.py"
Cohesion: 0.53
Nodes (5): load(), main(), mib(), pct(), Path

### Community 177 - "GestureArbiter"
Cohesion: 0.07
Nodes (17): AppKit, CoreGraphics, Foundation, IsolynApp, IsolynEngineBridge, Observation, RootView, EnvironmentSettingsView (+9 more)

### Community 179 - "CenteredContent"
Cohesion: 0.39
Nodes (4): CenteredContent, IsolynLayout, CGFloat, Content

### Community 180 - "ComingSoonView"
Cohesion: 0.10
Nodes (24): BlockingHeuristic::score(), hasImmediateDominoWin(), Move, size_t, MoveGenerator, countLegalMoves, generate, generateInto (+16 more)

### Community 181 - "BlockingHeuristic::score"
Cohesion: 0.15
Nodes (16): advanceToNextPlayer, checkForClose, AppliedMove, kind, move, playerIndex, PlacementKind, MoveValidator (+8 more)

### Community 182 - "OPS-47 — Fix the live Kaggle handoff (2026-11-15)"
Cohesion: 0.40
Nodes (5): Change, Live state at close, OPS-47 — Fix the live Kaggle handoff (2026-11-15), Verification (literal), What the live run found

### Community 183 - "OPS-38 — Offline lab streaming fold and merge optimization (2026-11-14)"
Cohesion: 0.40
Nodes (5): Hosted CI, Limits, OPS-38 — Offline lab streaming fold and merge optimization (2026-11-14), Verification (literal), What changed

### Community 184 - "RoundOutcome"
Cohesion: 0.50
Nodes (4): RoundOutcomeKind, RoundOutcome, decidingPlayerIndex, kind

### Community 185 - "OPS-39 — Offline lab quality-of-life pass (2026-11-14)"
Cohesion: 0.40
Nodes (5): Hosted CI, Limits, OPS-39 — Offline lab quality-of-life pass (2026-11-14), Verification (literal), What changed

### Community 186 - "OPS-35 — Phase 1–2: bounded search, secret locked pair, sets and One Domino (2026-11-14)"
Cohesion: 0.40
Nodes (5): OPS-35 — Phase 1–2: bounded search, secret locked pair, sets and One Domino (2026-11-14), Phase 1 — correctness before features, Phase 2 — sets, games and the 1v1 endgame, Remaining gaps and limits, Verification (literal)

### Community 187 - "DrawFlightView"
Cohesion: 0.38
Nodes (6): RevealRow, RoundEndOverlay, Bool, Int, String, Void

### Community 188 - "CommandOutcome"
Cohesion: 0.14
Nodes (12): AnalysisTask, EngineSession, Error, Int, Int32, isolyn, MatchFormat, Move (+4 more)

### Community 189 - "Move"
Cohesion: 0.40
Nodes (4): Move, describe, side, tile

### Community 190 - "OPS-41 — Verify the Kaggle code snapshot on both sides (2026-11-14)"
Cohesion: 0.50
Nodes (4): Change, Limits, stated plainly, OPS-41 — Verify the Kaggle code snapshot on both sides (2026-11-14), Verification (literal)

### Community 191 - "OPS-42 — Validate cloud CSV plan fields and reject symlinks (2026-11-14)"
Cohesion: 0.50
Nodes (4): Change, Limits, OPS-42 — Validate cloud CSV plan fields and reject symlinks (2026-11-14), Verification (literal)

### Community 192 - "OPS-43 — Plain-language reports beside every run (2026-11-15)"
Cohesion: 0.50
Nodes (4): Change, Limits, OPS-43 — Plain-language reports beside every run (2026-11-15), Verification (literal)

### Community 193 - "OPS-44 — Visual report and raw-file map (2026-11-15)"
Cohesion: 0.50
Nodes (4): Change, Limits, OPS-44 — Visual report and raw-file map (2026-11-15), Verification (literal)

### Community 194 - "OPS-45 — Staged cloud source and the first 10K app path (2026-11-15)"
Cohesion: 0.50
Nodes (4): Change, Limits, OPS-45 — Staged cloud source and the first 10K app path (2026-11-15), Verification (literal)

### Community 195 - "OPS-46 — Make the cloud next action unambiguous (2026-11-15)"
Cohesion: 0.50
Nodes (4): Change, Limits, OPS-46 — Make the cloud next action unambiguous (2026-11-15), Verification (literal)

### Community 196 - "OPS-36 — R-17 private locked-pair look (2026-11-14)"
Cohesion: 0.50
Nodes (4): Limits, OPS-36 — R-17 private locked-pair look (2026-11-14), Verification (literal), What changed

### Community 197 - "OPS-37 — R-22 1v1v1 elimination and the carried-points duel (2026-11-14)"
Cohesion: 0.50
Nodes (4): Limits, OPS-37 — R-22 1v1v1 elimination and the carried-points duel (2026-11-14), Verification (literal), What changed

## Knowledge Gaps
- **1105 isolated node(s):** `version`, `run_id`, `created_at`, `started_at`, `updated_at` (+1100 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **28 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameState` connect `Isolynengine` to `Options`, `EvaluationWeights`, `Include`, `Include`, `Isolynenginebridge`, `Include`, `Isolynenginebridge`, `benchmarkMode`, `Include`, `Engine`, `Include`, `ComingSoonView`, `BlockingHeuristic::score`, `THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.`, `Include`, `benchmarkMode`, `Include`?**
  _High betweenness centrality (0.032) - this node is a cross-community bridge._
- **Why does `DominoTile` connect `Include` to `Options`, `Isolynengine`, `Include`, `Include`, `Isolynenginebridge`, `buildAllTiles`, `Include`, `Isolynengine`, `Engine`, `Include`, `ComingSoonView`, `Isolynenginetests`, `THIS IS THE MOST IMPORTANT REQUIREMENT IN THIS DOCUMENT.`, `Include`, `Include`, `Move`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Why does `GameViewModel` connect `Game` to `Engine`, `GestureArbiter`, `RoundOutcome`, `Game`, `GestureArbiter`, `29. IMPLEMENTATION ORDER`, `Include`, `Engine`, `DrawFlightView`, `DrawFlightView`, `CommandOutcome`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `GameState` (e.g. with `bridge_match_record_round()` and `buildSnapshot()`) actually correct?**
  _`GameState` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `DominoTile` (e.g. with `main()` and `main()`) actually correct?**
  _`DominoTile` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `GameViewModel` (e.g. with `.test_computer_plays_its_own_turn_without_human_input()` and `.test_computer_plays_two_v_two_partner_turn_without_stalling()`) actually correct?**
  _`GameViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `version`, `run_id`, `created_at` to the rest of the system?**
  _1105 weakly-connected nodes found - possible documentation gaps or missing edges._