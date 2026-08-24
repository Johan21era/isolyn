# Isolyn — File Tree

```
.
├── .github
│   └── workflows
│       └── ci.yml
├── .swiftpm
│   ├── configuration
│   └── xcode
│       ├── package.xcworkspace
│       │   ├── xcuserdata
│       │   │   └── johanrembeci.xcuserdatad
│       │   └── contents.xcworkspacedata
│       ├── xcshareddata
│       │   └── xcschemes
│       │       └── IsolynApp.xcscheme
│       └── xcuserdata
│           └── johanrembeci.xcuserdatad
│               └── xcschemes
│                   └── xcschememanagement.plist
├── docs
│   ├── BRIDGE_ARCHITECTURE.md
│   ├── BRIDGE_TESTING.md
│   ├── FEATURE_SPECS.md
│   ├── RELEASE_CHECKLIST.md
│   └── STRATEGY_NOTES.md
├── graphify-out
│   ├── 2026-08-24
│   │   ├── .graphify_labels.json
│   │   ├── cost.json
│   │   ├── GRAPH_REPORT.md
│   │   ├── graph.json
│   │   └── manifest.json
│   ├── cache/  (regenerable AST cache — gitignored)
│   ├── .graphify_incremental.json
│   ├── .graphify_labels.json
│   ├── .graphify_old.json
│   ├── .graphify_python
│   ├── .graphify_root
│   ├── cost.json
│   ├── graph 2.json
│   ├── GRAPH_REPORT.md
│   ├── graph.html
│   ├── graph.json
│   └── manifest.json
├── Sources
│   ├── IsolynApp
│   │   ├── Components
│   │   │   ├── AtmosphericBackgroundView.swift
│   │   │   ├── EnvironmentSettingsView.swift
│   │   │   ├── EnvironmentTimeLabel.swift
│   │   │   ├── EnvironmentView.swift
│   │   │   ├── ModeCard.swift
│   │   │   ├── PipGlyph.swift
│   │   │   ├── PrimaryCapsuleButtonStyle.swift
│   │   │   ├── StarFieldView.swift
│   │   │   └── WeatherEffectView.swift
│   │   ├── Engine
│   │   │   ├── EngineSession.swift
│   │   │   ├── EngineTypes.swift
│   │   │   └── MatchCoordinator.swift
│   │   ├── Environment
│   │   │   ├── EnvironmentClock.swift
│   │   │   ├── EnvironmentManager.swift
│   │   │   ├── EnvironmentState.swift
│   │   │   ├── EnvironmentTransition.swift
│   │   │   ├── LiveWeatherService.swift
│   │   │   ├── RandomWeatherService.swift
│   │   │   ├── SkyCondition.swift
│   │   │   ├── StarField.swift
│   │   │   ├── TimePhase.swift
│   │   │   ├── WeatherField.swift
│   │   │   └── WeatherSource.swift
│   │   ├── Game
│   │   │   ├── Appearance
│   │   │   │   ├── AppearanceManager.swift
│   │   │   │   ├── DominoAppearance.swift
│   │   │   │   └── SettingsDrawer.swift
│   │   │   ├── Camera
│   │   │   │   ├── BoardCamera.swift
│   │   │   │   └── GestureArbiter.swift
│   │   │   ├── HoverChain
│   │   │   │   ├── HoverChainController.swift
│   │   │   │   ├── HoverChainModel.swift
│   │   │   │   ├── HoverChainOverlay.swift
│   │   │   │   └── TileKnowledgeResolver.swift
│   │   │   ├── ChainAndZonesView.swift
│   │   │   ├── GameViewModel.swift
│   │   │   ├── HandRackView.swift
│   │   │   ├── InteractiveGameBoardView.swift
│   │   │   ├── IsolynDominoTile.swift
│   │   │   └── RoundEndOverlay.swift
│   │   ├── Theme
│   │   │   └── IsolynTheme.swift
│   │   ├── Views
│   │   │   ├── ComingSoonView.swift
│   │   │   ├── EntryView.swift
│   │   │   └── ModeSelectorView.swift
│   │   ├── AppState.swift
│   │   ├── Info.plist
│   │   ├── IsolynApp.swift
│   │   └── RootView.swift
│   ├── IsolynEngine
│   │   ├── include
│   │   │   ├── BeliefState.hpp
│   │   │   ├── BlockingHeuristic.hpp
│   │   │   ├── Boneyard.hpp
│   │   │   ├── Chain.hpp
│   │   │   ├── ClosingOpportunityHeuristic.hpp
│   │   │   ├── Dealer.hpp
│   │   │   ├── Determinizer.hpp
│   │   │   ├── DominoSet.hpp
│   │   │   ├── DominoTile.hpp
│   │   │   ├── EntropySource.hpp
│   │   │   ├── EvaluationEngine.hpp
│   │   │   ├── ExpectedValueHeuristic.hpp
│   │   │   ├── GameMode.hpp
│   │   │   ├── GameState.hpp
│   │   │   ├── MatchController.hpp
│   │   │   ├── MobilityHeuristic.hpp
│   │   │   ├── Move.hpp
│   │   │   ├── MoveExecutor.hpp
│   │   │   ├── MoveGenerator.hpp
│   │   │   ├── MoveValidator.hpp
│   │   │   ├── ProbabilityEngine.hpp
│   │   │   ├── RulesEngine.hpp
│   │   │   ├── ScoreSystem.hpp
│   │   │   ├── SearchEngine.hpp
│   │   │   └── SimulationEngine.hpp
│   │   ├── BeliefState.cpp
│   │   ├── BlockingHeuristic.cpp
│   │   ├── Boneyard.cpp
│   │   ├── Chain.cpp
│   │   ├── ClosingOpportunityHeuristic.cpp
│   │   ├── Dealer.cpp
│   │   ├── Determinizer.cpp
│   │   ├── DominoSet.cpp
│   │   ├── DominoTile.cpp
│   │   ├── EntropySource.cpp
│   │   ├── EvaluationEngine.cpp
│   │   ├── ExpectedValueHeuristic.cpp
│   │   ├── GameState.cpp
│   │   ├── MatchController.cpp
│   │   ├── MobilityHeuristic.cpp
│   │   ├── Move.cpp
│   │   ├── MoveExecutor.cpp
│   │   ├── MoveGenerator.cpp
│   │   ├── MoveValidator.cpp
│   │   ├── ProbabilityEngine.cpp
│   │   ├── RulesEngine.cpp
│   │   ├── ScoreSystem.cpp
│   │   ├── SearchEngine.cpp
│   │   └── SimulationEngine.cpp
│   └── IsolynEngineBridge
│       ├── include
│       │   └── IsolynBridge.hpp
│       └── IsolynBridge.cpp
├── Tests
│   ├── IsolynAppTests
│   │   ├── ColorMathTests.swift
│   │   ├── EnvironmentTests.swift
│   │   └── GameViewModelTests.swift
│   ├── IsolynEngineBridgeTests
│   │   ├── FuzzBridge.cpp
│   │   ├── SmokeTest.cpp
│   │   ├── SoakTest.cpp
│   │   └── StandaloneFuzzDriver.cpp
│   └── IsolynEngineTests
│       ├── BeliefStateTests.cpp
│       ├── BoneyardTests.cpp
│       ├── ChainTests.cpp
│       ├── DealerTests.cpp
│       ├── DeterminizerTests.cpp
│       ├── DominoSetTests.cpp
│       ├── DominoTileTests.cpp
│       ├── EntropySourceTests.cpp
│       ├── EvaluationEngineTests.cpp
│       ├── GameStateTests.cpp
│       ├── MatchControllerTests.cpp
│       ├── MoveSystemTests.cpp
│       ├── ProbabilityEngineTests.cpp
│       ├── RulesEngineTests.cpp
│       ├── ScoreSystemTests.cpp
│       ├── SearchEngineCancellationTests.cpp
│       ├── SearchEngineTests.cpp
│       ├── SimulationEngineTests.cpp
│       └── TestHarness.hpp
├── .gitignore
├── clean.sh
├── core hardening roadmap.md
├── dominoes_ui_fix_non_negotiable.md
├── fix-log.md
├── isolyn current audit.md
├── isolyn current audit.pdf
├── isolyn roadmap.md
├── legacy handoff.md
├── Package.swift
├── README.md
├── run_bridge_fuzz.sh
├── run_bridge_tests.sh
├── run_sanitize.sh
├── run_tests.sh
├── run.sh
└── tree.md

39 directories, 354 files
```

**36 directories, 165 files** excluding the regenerable graphify AST cache (collapsed above) — regenerated 2026-08-24 after the UI rebuild per `dominoes_ui_fix_non_negotiable.md` (UI-01…03). Build dirs omitted per house rule #7.
