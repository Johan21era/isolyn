.
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
│   │   │   └── EngineTypes.swift
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
│   │   ├── Theme
│   │   │   └── IsolynTheme.swift
│   │   ├── Views
│   │   │   ├── ComingSoonView.swift
│   │   │   ├── EntryView.swift
│   │   │   ├── GamePlaceholderView.swift
│   │   │   └── ModeSelectorView.swift
│   │   ├── AppState.swift
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
│   │   └── EnvironmentTests.swift
│   ├── IsolynEngineBridgeTests
│   │   ├── FuzzBridge.cpp
│   │   ├── SmokeTest.cpp
│   │   └── SoakTest.cpp
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
├── docs
│   ├── BRIDGE_ARCHITECTURE.md
│   ├── BRIDGE_TESTING.md
│   ├── FEATURE_SPECS.md
│   └── STRATEGY_NOTES.md
├── HANDOFF.md
├── Package.swift
├── run_bridge_fuzz.sh
├── run_bridge_tests.sh
├── run_tests.sh
└── tree.md

17 directories, 114 files
