# IsolynV2.0 Project Inventory

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

| Surface | Tracked files | Physical LOC |
|---|---:|---:|
| `Sources/IsolynEngine` | 50 | 3,766 |
| `Sources/IsolynEngineBridge` | 2 | 1,054 |
| `Sources/IsolynApp` | 47 | 5,869 |
| `Tests` | 29 | 4,056 |
| `Accelerator` | 13 | 1,640 |
| `tools` | 5 | 735 |
| `lab` | 9 | 651 |
| `scripts` (including vendored graph viewer) | 5 | 2,513 |
| **Total** | **160** | **20,284** |

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

The key caller files are `Sources/IsolynApp/Game/GameViewModel.swift` (539
lines), `Sources/IsolynApp/Engine/EngineSession.swift` (276),
`Sources/IsolynEngineBridge/IsolynBridge.cpp` (633),
`Sources/IsolynEngine/SearchEngine.cpp` (593),
`Sources/IsolynEngine/EvaluationEngine.cpp` (299), and
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
