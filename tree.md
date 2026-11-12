# IsolynV2.0 — File Tree

```
.
|-- .github
|   `-- workflows
|       `-- ci.yml
|-- .swiftpm
|   |-- configuration
|   `-- xcode
|       |-- package.xcworkspace
|       |   |-- xcuserdata
|       |   |   `-- johanrembeci.xcuserdatad
|       |   |       `-- UserInterfaceState.xcuserstate
|       |   `-- contents.xcworkspacedata
|       |-- xcshareddata
|       |   `-- xcschemes
|       |       `-- IsolynApp.xcscheme
|       `-- xcuserdata
|           `-- johanrembeci.xcuserdatad
|               `-- xcschemes
|                   `-- xcschememanagement.plist
|-- Accelerator
|   |-- include
|   |   |-- IsolynAccelerator.hpp
|   |   |-- IsolynEvaluationBatch.hpp
|   |   `-- IsolynPositionBatch.hpp
|   |-- shaders
|   |   `-- evaluation.metal
|   |-- src
|   |   |-- BatchValidation.hpp
|   |   |-- CpuBackend.cpp
|   |   |-- EvaluationBatch.cpp
|   |   |-- EvaluationShaderSource.hpp
|   |   |-- MetalAccelerator.mm
|   |   `-- PositionBatch.cpp
|   |-- tests
|   |   `-- AcceleratorTests.mm
|   |-- README.md
|   `-- build.sh
|-- Sources
|   |-- IsolynApp
|   |   |-- Components
|   |   |   |-- AtmosphericBackgroundView.swift
|   |   |   |-- EnvironmentSettingsView.swift
|   |   |   |-- EnvironmentTimeLabel.swift
|   |   |   |-- EnvironmentView.swift
|   |   |   |-- ModeCard.swift
|   |   |   |-- PipGlyph.swift
|   |   |   |-- PrimaryCapsuleButtonStyle.swift
|   |   |   |-- StarFieldView.swift
|   |   |   `-- WeatherEffectView.swift
|   |   |-- Engine
|   |   |   |-- EngineSession.swift
|   |   |   |-- EngineTypes.swift
|   |   |   `-- MatchCoordinator.swift
|   |   |-- Environment
|   |   |   |-- EnvironmentClock.swift
|   |   |   |-- EnvironmentManager.swift
|   |   |   |-- EnvironmentState.swift
|   |   |   |-- EnvironmentTransition.swift
|   |   |   |-- LiveWeatherService.swift
|   |   |   |-- RandomWeatherService.swift
|   |   |   |-- SkyCondition.swift
|   |   |   |-- StarField.swift
|   |   |   |-- TimePhase.swift
|   |   |   |-- WeatherField.swift
|   |   |   `-- WeatherSource.swift
|   |   |-- Game
|   |   |   |-- Appearance
|   |   |   |   |-- AppearanceManager.swift
|   |   |   |   |-- DominoAppearance.swift
|   |   |   |   `-- SettingsDrawer.swift
|   |   |   |-- Camera
|   |   |   |   |-- BoardCamera.swift
|   |   |   |   `-- GestureArbiter.swift
|   |   |   |-- HoverChain
|   |   |   |   |-- HoverChainController.swift
|   |   |   |   |-- HoverChainModel.swift
|   |   |   |   |-- HoverChainOverlay.swift
|   |   |   |   `-- TileKnowledgeResolver.swift
|   |   |   |-- ChainAndZonesView.swift
|   |   |   |-- GameViewModel.swift
|   |   |   |-- HandRackView.swift
|   |   |   |-- InteractiveGameBoardView.swift
|   |   |   |-- IsolynDominoTile.swift
|   |   |   |-- Opponent.swift
|   |   |   `-- RoundEndOverlay.swift
|   |   |-- Theme
|   |   |   `-- IsolynTheme.swift
|   |   |-- Views
|   |   |   |-- ComingSoonView.swift
|   |   |   |-- EntryView.swift
|   |   |   `-- ModeSelectorView.swift
|   |   |-- AppState.swift
|   |   |-- Info.plist
|   |   |-- IsolynApp.swift
|   |   `-- RootView.swift
|   |-- IsolynEngine
|   |   |-- include
|   |   |   |-- BeliefState.hpp
|   |   |   |-- BlockingHeuristic.hpp
|   |   |   |-- Boneyard.hpp
|   |   |   |-- Chain.hpp
|   |   |   |-- ClosingOpportunityHeuristic.hpp
|   |   |   |-- Dealer.hpp
|   |   |   |-- Determinizer.hpp
|   |   |   |-- DifficultyModel.hpp
|   |   |   |-- DominoSet.hpp
|   |   |   |-- DominoTile.hpp
|   |   |   |-- EntropySource.hpp
|   |   |   |-- EvaluationEngine.hpp
|   |   |   |-- ExpectedValueHeuristic.hpp
|   |   |   |-- GameMode.hpp
|   |   |   |-- GameState.hpp
|   |   |   |-- MatchController.hpp
|   |   |   |-- MobilityHeuristic.hpp
|   |   |   |-- Move.hpp
|   |   |   |-- MoveExecutor.hpp
|   |   |   |-- MoveGenerator.hpp
|   |   |   |-- MoveValidator.hpp
|   |   |   |-- ProbabilityEngine.hpp
|   |   |   |-- RulesEngine.hpp
|   |   |   |-- ScoreSystem.hpp
|   |   |   |-- SearchEngine.hpp
|   |   |   `-- SimulationEngine.hpp
|   |   |-- BeliefState.cpp
|   |   |-- BlockingHeuristic.cpp
|   |   |-- Boneyard.cpp
|   |   |-- Chain.cpp
|   |   |-- ClosingOpportunityHeuristic.cpp
|   |   |-- Dealer.cpp
|   |   |-- Determinizer.cpp
|   |   |-- DominoSet.cpp
|   |   |-- DominoTile.cpp
|   |   |-- EntropySource.cpp
|   |   |-- EvaluationEngine.cpp
|   |   |-- ExpectedValueHeuristic.cpp
|   |   |-- GameState.cpp
|   |   |-- MatchController.cpp
|   |   |-- MobilityHeuristic.cpp
|   |   |-- Move.cpp
|   |   |-- MoveExecutor.cpp
|   |   |-- MoveGenerator.cpp
|   |   |-- MoveValidator.cpp
|   |   |-- ProbabilityEngine.cpp
|   |   |-- RulesEngine.cpp
|   |   |-- ScoreSystem.cpp
|   |   |-- SearchEngine.cpp
|   |   `-- SimulationEngine.cpp
|   `-- IsolynEngineBridge
|       |-- include
|       |   `-- IsolynBridge.hpp
|       `-- IsolynBridge.cpp
|-- Tests
|   |-- IsolynAppTests
|   |   |-- AIOpponentTests.swift
|   |   |-- BoardLayoutTests.swift
|   |   |-- ColorMathTests.swift
|   |   |-- EnvironmentTests.swift
|   |   `-- GameViewModelTests.swift
|   |-- IsolynEngineBridgeTests
|   |   |-- FuzzBridge.cpp
|   |   |-- SmokeTest.cpp
|   |   |-- SoakTest.cpp
|   |   `-- StandaloneFuzzDriver.cpp
|   `-- IsolynEngineTests
|       |-- BeliefStateTests.cpp
|       |-- BoneyardTests.cpp
|       |-- ChainTests.cpp
|       |-- DealerTests.cpp
|       |-- DeterminizerTests.cpp
|       |-- DifficultyModelTests.cpp
|       |-- DominoSetTests.cpp
|       |-- DominoTileTests.cpp
|       |-- EntropySourceTests.cpp
|       |-- EvaluationEngineTests.cpp
|       |-- GameStateTests.cpp
|       |-- MatchControllerTests.cpp
|       |-- MoveSystemTests.cpp
|       |-- ProbabilityEngineTests.cpp
|       |-- RulesEngineTests.cpp
|       |-- ScoreSystemTests.cpp
|       |-- SearchEngineCancellationTests.cpp
|       |-- SearchEngineTests.cpp
|       |-- SimulationEngineTests.cpp
|       `-- TestHarness.hpp
|-- docs
|   |-- ACCELERATOR.md
|   |-- BRIDGE_ARCHITECTURE.md
|   |-- BRIDGE_TESTING.md
|   |-- FEATURE_SPECS.md
|   |-- LAB.md
|   |-- OPEN_DECISIONS.md
|   |-- PROJECT_INVENTORY.md
|   |-- RELEASE_CHECKLIST.md
|   `-- STRATEGY_NOTES.md
|-- graphify-out
|   |-- 2026-08-24
|   |   |-- .graphify_labels.json
|   |   |-- GRAPH_REPORT.md
|   |   |-- cost.json
|   |   |-- graph.json
|   |   `-- manifest.json
|   |-- 2026-11-10
|   |   |-- .graphify_labels.json
|   |   |-- GRAPH_REPORT.md
|   |   |-- cost.json
|   |   |-- graph.json
|   |   `-- manifest.json
|   |-- 2026-11-11
|   |   |-- .graphify_labels.json
|   |   |-- GRAPH_REPORT.md
|   |   |-- cost.json
|   |   |-- graph.json
|   |   `-- manifest.json
|   |-- .graphify_incremental.json
|   |-- .graphify_labels.json
|   |-- .graphify_old.json
|   |-- .graphify_python
|   |-- .graphify_root
|   |-- GRAPH_REPORT.md
|   |-- cost.json
|   |-- graph\ 2.json
|   |-- graph\ 3.json
|   |-- graph-3d-full.html
|   |-- graph.html
|   |-- graph.json
|   `-- manifest.json
|-- lab
|   |-- configs
|   |   `-- selfplay.example.toml
|   |-- src
|   |   `-- isolyn_lab
|   |       |-- __init__.py
|   |       |-- calibration.py
|   |       |-- cli.py
|   |       `-- dataset.py
|   |-- tests
|   |   `-- test_calibration.py
|   |-- README.md
|   `-- pyproject.toml
|-- scripts
|   |-- vendor
|   |   |-- 3d-force-graph-1.80.2.LICENSE
|   |   `-- 3d-force-graph-1.80.2.min.js
|   |-- build-graph-3d.py
|   |-- graph3d-template.html
|   `-- iso
|-- tools
|   `-- selfplay
|       |-- README.md
|       |-- build.sh
|       `-- main.cpp
|-- .gitignore
|-- .graphifyignore
|-- Package.swift
|-- README.md
|-- audit\ remediation\ roadmap.md
|-- clean.sh
|-- core\ hardening\ roadmap.md
|-- dominoes_ui_fix_non_negotiable.md
|-- fix-log.md
|-- isolyn\ current\ audit.md
|-- isolyn\ current\ audit.pdf
|-- isolyn\ roadmap.md
|-- legacy\ handoff.md
|-- run.sh
|-- run_bridge_fuzz.sh
|-- run_bridge_tests.sh
|-- run_sanitize.sh
|-- run_tests.sh
`-- tree.md

52 directories, 218 files
```

**52 directories, 218 files** excluding build dirs, caches, and local lab data (house rule #7) — regenerated 2026-11-11 for the closeout sweep.
