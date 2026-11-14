# IsolynV2.0 Project Inventory

> **Status: living inventory (tier 3).** All figures measured 2026-11-13. They
> move with every commit — re-measure before quoting and update the date above
> the table.

**Identity:** `IsolynV2.0` is the package, product, window, and app-bundle
display name. The Swift targets (`IsolynEngine`, `IsolynEngineBridge`,
`IsolynApp`) and the C++ `isolyn` namespace are intentionally unchanged: dots
are not legal in those identifiers, and keeping them stable preserves the
bridge ABI, imports, and test paths. The bundle identifier remains
`com.isolyn.app` so existing app identity and local data are not silently
migrated by a display-name change.

## Components and LOC

Physical lines in tracked files, excluding generated graphs, build products,
and local lab data. Counts include comments and blank lines; they are a layout
inventory, not a code-golf target.

**Measured 2026-11-14** with `git ls-files <dir> | xargs cat | wc -l`. The
previous table was measured 2026-11-13 and understated the app by 9 files /
2,659 lines; that drift is exactly why the number is re-measured rather than
carried forward.

| Surface | Tracked files | Physical LOC |
|---|---:|---:|
| `Sources/IsolynEngine` | 50 | 4,312 |
| `Sources/IsolynEngineBridge` | 2 | 1,222 |
| `Sources/IsolynApp` | 65 | 10,393 |
| `Tests` | 40 | 6,113 |
| `Accelerator` | 13 | 1,702 |
| `tools` | 5 | 859 |
| `lab` | 10 | 1,391 |
| `scripts` | 14 | 3,512 |
| **Total** | **199** | **29,504** |

Re-measure before quoting these; they move with every commit. Do not add
`graphify-out/` or `lab/data/` to this table — both are generated and would
dominate it.

## Repository layout

The tree encodes the architecture: each top level is one kind of artefact, and
each subdirectory is one responsibility. Generated output never shares a
directory with maintained source.

```text
.
├── Package.swift            SwiftPM manifest: 3 targets + 2 test targets
├── README.md                entry point
├── run.sh                   the one supported launch command (shell aliases target it)
├── Sources/
│   ├── IsolynEngine/        C++20 domain: rules, chain, belief, search, evaluation
│   │   └── include/         public headers (flat namespace by design)
│   ├── IsolynEngineBridge/  POD C boundary; include/IsolynBridge.hpp IS the contract
│   └── IsolynApp/           SwiftUI client
│       ├── Application/     @main, AppState, RootView
│       ├── Engine/          actor session, DTO projections, match coordinator
│       ├── Game/            GameViewModel + Opponent (orchestration)
│       │   ├── Board/       chain, board, tile, round overlay
│       │   ├── Hand/        racks, drag resolution, tap routing
│       │   ├── Boneyard/    boneyard view, draw flight
│       │   └── Camera/ Appearance/ HoverChain/ Inspection/
│       ├── Components/      reusable presentation pieces
│       ├── Environment/     time phase, weather, sky
│       ├── Theme/           palette, typography, responsive layout
│       ├── Views/           entry, mode selection, placeholders
│       └── Resources/       Info.plist for the future app shell
├── Tests/                   1:1 mirrors of the three targets
├── Accelerator/             standalone Metal evaluator (include/src/shaders/tests)
├── tools/                   bench/, selfplay/ — C++ developer binaries
├── lab/                     Python offline analysis (src/isolyn_lab, configs, data, tests)
├── scripts/
│   ├── ci/                  test_engine, test_bridge, sanitize, fuzz_bridge
│   ├── dev/                 clean
│   ├── docs_audit.py        documentation gate (runs in CI)
│   ├── build-graph-3d.py    graph viewer build
│   └── iso                  alias entry point; executes run.sh
├── docs/                    see docs/README.md for the authority model
├── Assets/                  app icon source render + .icns ladder
└── graphify-out/            generated code graph — never hand-edited
```

### Where new code belongs

| Adding… | Goes in | Never in |
|---|---|---|
| A rule, scoring formula, legality check | `Sources/IsolynEngine/` | Swift, bridge, lab |
| Data crossing to Swift | `Sources/IsolynEngineBridge/` (POD DTO + accessor) | engine headers exposed to the app |
| A new screen or journey | `Sources/IsolynApp/Views/` | `Game/` |
| A table element (chain, tile, hand, boneyard) | the matching `Game/` subdomain | `Components/` |
| A reusable visual atom | `Sources/IsolynApp/Components/` | a feature folder |
| A CI check | `scripts/ci/` | repository root |
| A developer helper | `scripts/dev/` | repository root |
| Offline analysis or calibration | `lab/src/isolyn_lab/` | the shipped app |
| A generated artefact | `graphify-out/` or `build/` | `docs/` or `Sources/` |

## Relevant callers

```text
@main IsolynApp
  -> RootView / GameViewModel
  -> Opponent (AI move selection)
  -> EngineSession
  -> isolyn::bridge session/analysis commands
  -> MatchController (round flow and scoring)
  -> SearchEngine::chooseBestMove
  -> searchZeroSum / searchMulti
  -> EvaluationEngine::evaluateAll (batched leaf totals)

MatchCoordinator
  -> EngineSession
  -> bridge_match_* (running match score and next-round setup)

tools/selfplay/main.cpp
  -> MatchController + SearchEngine directly (offline calibration)

lab/src/isolyn_lab
  -> reads self-play CSV output only; no engine linkage

Accelerator/src/MetalAccelerator.mm
  -> standalone CPU-parity evaluator; not linked into SearchEngine
```

The key caller files, with line counts measured 2026-11-13:
`Sources/IsolynApp/Game/GameViewModel.swift` (636),
`Sources/IsolynApp/Engine/EngineSession.swift` (276),
`Sources/IsolynEngineBridge/IsolynBridge.cpp` (647),
`Sources/IsolynEngine/SearchEngine.cpp` (609),
`Sources/IsolynEngine/EvaluationEngine.cpp` (349), and
`tools/selfplay/main.cpp` (475).

## Naming boundary

- Change display, package, product, and documentation names to
  `IsolynV2.0`.
- Keep `IsolynEngine`, `IsolynEngineBridge`, `IsolynApp`, and `isolyn` as
  stable technical identifiers.
- Keep the bundle identifier stable unless a deliberate data migration is
  planned.
- Do not rename source directories or Swift targets as part of a cosmetic
  version-name change.
