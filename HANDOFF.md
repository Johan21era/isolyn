# STATUS UPDATE — Real Xcode build attempt: missing `import IsolynEngineBridge` found and fixed (41 reported issues, effectively 1 root cause)

The person opened `Isolyn-current_3` in actual Xcode and sent screenshots of a failed build: 41 issues, all under `EngineSession.swift`/`EngineTypes.swift`. Diagnosed from the screenshots alone (no Xcode access here, same as always): **`EngineTypes.swift` and `EngineSession.swift` never had `import IsolynEngineBridge`** — a real, avoidable miss, not an environment limitation. Every reported error was a direct or cascading consequence of that one omission:

- `Cannot find type 'isolyn' in scope` / `Cannot find 'isolyn' in scope` — the literal, direct consequence of the module never being imported.
- `Cannot infer contextual base in reference to member 'Ok'` — downstream: `dto.status`'s type (`isolyn.bridge.BridgeStatus`) couldn't resolve, so `.Ok` had nothing to infer against.
- `Missing arguments for parameters 'tile', 'side' in call` / `Extra argument 'dto' in call` at `Move(dto:)` call sites — downstream: the `fileprivate init(dto: isolyn.bridge.MoveDTO)` overload became invalid once its parameter type failed to resolve, so overload resolution fell back to matching the call against `init(tile:side:)` instead, producing a confusing arity mismatch rather than pointing at the real cause.

Fixed: added `import IsolynEngineBridge` to both files. Re-audited both completely after the fix, specifically checking for anything the cascade of 41 errors could have been masking (inconsistent DTO-construction patterns, namespace-spelling typos, duplicate imports) — found nothing further. `isolyn.bridge.*` is spelled identically at all ~50 call sites across both files (confirmed by grep), so if that specific spelling still turns out to be wrong once this is rebuilt, it remains a one-pattern fix, not a scattered one — but the missing import was very likely the whole story, given the exact error text (`Cannot find type 'isolyn'` — the outermost identifier itself unrecognized — is what a missing import produces, not what a namespace-spelling mismatch inside a present import would produce).

C++ side untouched by this — re-confirmed 356/356 engine checks, 34/34 bridge checks (including the soak test, now part of the regular bridge suite) immediately after the fix, both clean.

**Next step for whoever picks this up:** rebuild in Xcode. If it's still not clean, the remaining errors (if any) are the real, final signal on the namespace-spelling question neither this session nor any prior one has been able to verify directly.

---



This session executed `Isolyn_secure_swift_cpp_bridge_prompt.md` (a from-scratch bridge design-and-build spec) against the codebase this file otherwise describes. Full detail lives in `docs/BRIDGE_ARCHITECTURE.md` (design rationale) and `docs/BRIDGE_TESTING.md` (every real test run and its actual result) — this entry is the summary a future session or the next AI/human needs to start from immediately, per this file's own stated purpose below.

**What this was:** greenfield work. A repo-wide search before starting confirmed zero prior bridge/adapter/interop artifacts of any kind — `Package.swift` itself said as much ("no Swift/C++ interop is wired up here... future work").

## Two facts about the engine the whole design rests on

Found by reading the actual `.cpp` files, not assumed from headers:

1. **`MatchController::playTurn`/`MoveExecutor::apply`'s legality precondition is `assert`-only** — a no-op under `NDEBUG`, which Xcode Release defines by default. Calling either with an illegal move in Release is undefined behavior in the engine itself, not a safe rejection. The bridge is the actual enforcement point (`MoveValidator::isLegal` checked explicitly in `bridge_submit_move`, before any engine call, independent of build config).
2. **The engine has zero internal concurrency support** — a full grep for `mutex`/`atomic`/`std::thread`/`lock_guard`/`condition_variable`/`thread_local` across every engine `.cpp`/`.hpp` returns nothing real. All serialization is the bridge's responsibility.

## The bridge itself

`Sources/IsolynEngineBridge/` — new SPM target, POD-only public header (`include/IsolynBridge.hpp`), `uint64_t` handle tokens (not raw pointers — see `BRIDGE_ARCHITECTURE.md` for why), typed `BridgeStatus` errors, state-versioned commands, and a deliberately two-phase analysis design (cheap actor-isolated snapshot, expensive fully-independent search) so a multi-second analysis run never blocks anything else on a session.

**Provenance note, stated plainly:** partway through this session, the person dropped in their own independently-written draft of this same bridge (as an RTF file — multiply-corrupted by copy-paste round-trips, needed a custom unwrapping pass to even read faithfully). It was reviewed with the same rigor as anything else in this file: read in full, checked against the real engine API line by line, then actually compiled and tested. Verdict: adopted as the official implementation. It included two genuine improvements over the in-progress version it was compared against — a per-session mutex (real defense-in-depth this project has no way to verify is unnecessary, given no Swift toolchain has ever been available to confirm actor discipline is followed correctly) and a cached round-outcome mechanism (fixes a real gap where a snapshot taken after a round had already closed wouldn't correctly re-report `decidingPlayerIndex`). Two compile bugs were found and fixed in it (a `GameState` local assuming a default constructor that doesn't exist; a missing namespace-closing brace that — if merely silenced rather than fixed — would have quietly given every public `bridge_*` function internal linkage instead of external, breaking the link the moment anything tried to call them). Full writeup of the review in the conversation this file can't directly capture, but every finding is reflected in the actual committed code and in `docs/BRIDGE_TESTING.md`.

## Verified (real commands, real results — see docs/BRIDGE_TESTING.md for the exact commands)

- **Engine baseline: 18 executables, 356/356 checks**, zero compile/runtime failures (`./run_tests.sh`).
- **Bridge suite: 33/33 checks** (`./run_bridge_tests.sh`) — lifecycle/idempotent close, hidden-information isolation between players, the legality gate rejecting an illegal move with state unchanged, state-version staleness rejection, analysis correctness + cancellation, and a real cross-thread test (background thread hammering snapshots — several million completed — while foreground runs a full analysis on the same session, confirming analysis genuinely doesn't block queries).
- **Sanitizers: zero findings** across every engine test binary and the bridge suite under ASan+UBSan, and separately under ThreadSanitizer for anything touching real threads.
- **Fuzzing (`./run_bridge_fuzz.sh`): a 5-second smoke run found a real crash within ~18,000 executions** (see below) — after the fix, **120 seconds / 75,451 executions, zero findings.**
- **Soak test: 12,000 full session lifecycles, 8 KB total RSS growth over 11,800 post-warmup cycles** (0.7 bytes/cycle — allocator noise, not a leak).

## Real bugs found and fixed this session

**Bridge-level (found by fuzzing):** `bridge_analysis_snapshot_create` never checked that the session's current player actually had a legal move before handing a snapshot to `SearchEngine::chooseBestMove`, which documents that exact precondition and trusts the caller to have satisfied it. Reachable through the bridge's ordinary command surface (any session where the current player is blocked and hasn't called `resolveForcedDraw` yet). Asserted in debug; would have been silent UB (`candidates[0]` on an empty vector) under Release. Fixed, regression-tested directly, covered going forward by the fuzz harness.

**Engine-level (pre-existing, unrelated to the bridge's own code, surfaced because bridge-level testing was the first thing to exercise these paths against realistic — not hand-crafted — game states):**

1. `GameState::undoDrawTile` assumed the drawn tile stayed at `hand.back()`; `playTile`/`undoPlayTile`'s find-then-erase/push_back pattern doesn't preserve hand order, so any search recursion that draws then evaluates an unrelated candidate could silently break the assumption. Fixed: locate-and-remove by identity instead, matching how `playTile` already worked.
2. `OneVsOneVsOne` analysis crashed on every single real 3-player game. `Dealer` correctly removes the 0-0 tile from play for this mode; `ProbabilityEngine`/`BeliefState` didn't know about that exclusion and assumed all 28 canonical tiles were always accounted for. Reproduced with zero bridge code involved. Fixed with a new `Dealer::excludedTilesForMode` (single source of truth `deal()` itself now also uses) threaded into `BeliefState`'s constructor as an `excludedTiles` parameter.

Also added this session, independent of the above: cooperative cancellation for `SearchEngine::chooseBestMove` (`Sources/IsolynEngine/include/SearchEngine.hpp` — additive, `nullptr`-default, every existing call site's behavior unchanged; checked once before each determinization sample begins). This is what `bridge_analysis_request_cancel` ultimately wires into.

Full 356-check baseline reconfirmed clean after every one of the above changes, individually, not just at the end.

## Swift side — written, unverified, exactly like every previous Swift batch in this file

`Sources/IsolynApp/Engine/EngineTypes.swift` (DTO ↔ Swift-native type conversions, including a `withTupleAsArray` helper for the fact that fixed C arrays import as tuples under Cxx interop) and `EngineSession.swift` (the actor wrapper — phase-1-on-actor / phase-2-on-`Task.detached` analysis split mirroring the C++ design exactly). `Package.swift` updated: new `IsolynEngineBridge` target, `IsolynApp` now depends on it with `.interoperabilityMode(.Cxx)` enabled.

**Never compiled — no session working on this codebase has ever had a Swift toolchain available.** Hand-reviewed carefully against the real `IsolynBridge.hpp` signatures. Two specific, flagged uncertainties (documented in both files' own header comments, not buried): the exact Cxx-interop namespace-access spelling for `isolyn::bridge::*` (written as `isolyn.bridge.foo`, with an explicit fallback noted if that's wrong), and reliance on the well-documented-but-unverified-in-this-instance "fixed C array imports as tuple with identical memory layout" behavior.

## Explicitly not done this session

- Match-level score accumulation across rounds (`ScoreSystem` isn't wired into the bridge — needs a real round-orchestration design first, see `BRIDGE_ARCHITECTURE.md`).
- Sandbox Mode's arbitrary starting positions (no engine-side `PositionConstructor` exists yet to bridge to).
- Any Swift-side testing of any kind (no toolchain, as above).
- A formal, separately-enumerated red-team pass (fuzzing + soak cover a meaningful real slice of that spirit, not run as their own checklist pass).
- Real-hardware performance characterization (this sandbox is single-core Linux, not representative of the eventual macOS/Xcode target).

## For the next session/AI/human

Start by opening this in Xcode and fixing whatever the two flagged Cxx-interop uncertainties above turn out to be — everything else Swift-side is written against the real bridge contract and should need at most mechanical fixes, not a redesign. The C++ side (`IsolynEngineBridge`) does not need to be touched to get a first build working. `docs/BRIDGE_TESTING.md`'s "What has not been done" section is the honest starting point for what's actually still open.

---



Added since the rest of this file was written, in the exact order and
with the exact code Section 4 specified:

- Step 1: `Chain::fromKnownState` — done, tested.
- Step 2: `GameState`'s extended constructor — done, tested.
- Step 3: `Determinizer` (new files) — done, tested.
- Step 4: `SimulationEngine` (new files) — done, tested.
- Step 5: `SearchEngine` (new files) — done, tested, including the
  hand-verified "avoid handing the opponent an immediate Domino win"
  puzzle in `SearchEngineTests.cpp`, which passed exactly as designed
  (correctly chose 4-1 over 4-6).

**Verified state: 17 test executables, 313/313 checks passing**, compiled
clean under `g++ -std=c++20 -Wall -Wextra -Wpedantic` with zero warnings,
zero compile failures, zero runtime failures. Compiled and re-verified
after EACH step individually (not just at the end), per this file's own
Section 5 instructions — `ChainTests` and `GameStateTests` were
specifically reverified after being directly modified, not assumed to
still pass. A `run_tests.sh` script now sits at the repo root, capturing
the exact verified build/run command for future sessions.

Per-executable check counts: BeliefState 26, Boneyard 18, Chain 23,
Dealer 21, Determinizer 9, DominoSet 6, DominoTile 12, EntropySource 2,
EvaluationEngine 11, GameState 46, MatchController 40, MoveSystem 35,
ProbabilityEngine 23, RulesEngine 18, ScoreSystem 9, SearchEngine 3,
SimulationEngine 11.

Zero neural networks, zero placeholder implementations, zero silently-
invented rules were introduced. Every ambiguity resolution and design
decision in Sections 1-3 below was left untouched and unre-litigated, as
instructed.

**Not started, per this file's own Section 5 item 7: `DifficultyModel`.**
This file is explicit that module needs user confirmation before
starting, the same way every other major module in this project has
been confirmed first. That confirmation has not happened yet — do not
start it without asking.

## UI/UX pass (Swift/SwiftUI) — started, separate from the engine work above

At the user's direction, work paused on the C++ engine (Section 4's
`DifficultyModel` is still un-started, still pending confirmation as
described above) to begin the Swift/SwiftUI app layer instead. This is
genuinely new: zero Swift/UI code existed before this pass.

Added: a new `IsolynApp` executable target in `Package.swift`, and
`Sources/IsolynApp/` containing the app entry point, a navigation model
(`AppState`), the entry/launch screen, the mode selector screen, a
shared `IsolynTheme` design-token file, a reusable `PipGlyph` component
(the app's graphic signature -- domino pip patterns used to represent
player/team counts instead of generic icons), and an honest
`ComingSoonView` placeholder used wherever navigation leads somewhere
not yet built (Training, Sandbox, the actual game board).

**Deliberately NOT done in this pass:** `IsolynApp` does not depend on
`IsolynEngine` and has no Swift/C++ interop wired up. `MatchFormat`
(the UI layer's mode enum) is a separate, pure-Swift type, not yet
mapped to the real `isolyn::GameMode`. This was a deliberate choice to
keep the UI pass self-contained, not an oversight -- wiring the two
together is exactly the kind of "technical aspect" work meant to
resume later, and is a small, well-scoped step once it does.

**Important limitation for whoever continues this:** this code was
written without access to a macOS/Xcode environment or a Swift
compiler, unlike every claim above about the C++ engine, which was
compiled and run for real. It has been carefully hand-reviewed (brace/
paren balance checked, every cross-file symbol reference traced by
hand) but is UNVERIFIED by actual compilation. Open it in Xcode and
confirm it builds before trusting it the way Sections 1-6 below can be
trusted.

The actual game board (tile rendering, the chain, drag-and-drop play)
has not been started. `GamePlaceholderView` exists so the full
entry -> mode select -> game navigation path is real and clickable
today, without pretending the board itself exists yet.

### Environment system — batch 1 (time engine) of a larger UI/UX prompt

The user supplied a much larger, formally-specified execution prompt
(`DesignProtocolCRITICAL.md`, 47 sections) for turning this early shell
into a full time-of-day/weather environmental system behind the game.
Per that prompt's own Implementation Order (its section 34), work is
proceeding in batches, each hand-reviewed and delivered before the next
begins, rather than all ~20 files at once.

**Batch 1 (steps 4-6 of that order) is done** — the time/phase engine,
added at `Sources/IsolynApp/Environment/`:
- `EnvironmentClock.swift` — injectable clock protocol
  (`SystemEnvironmentClock` for real use, `FixedEnvironmentClock` for
  tests), so nothing depends on the wall clock.
- `TimePhase.swift` — the five phases (`night`, `morning`,
  `morningToAfternoonTransition`, `afternoon`, `primeDay`) and the pure
  classification function, using real `Calendar` component extraction
  (DST-safe) rather than manual UTC-offset math.
- `EnvironmentState.swift` — the resolved, testable value type.
- `EnvironmentManager.swift` — the `@Observable` owner, wired into
  `IsolynApp.swift` via `.environment(environmentManager)` exactly like
  `appState`. Refreshes on a timer and immediately on a system timezone
  change (`NSSystemTimeZoneDidChange`, including the required
  `TimeZone.resetSystemTimeZone()` call before re-reading `.current`).
- `Tests/IsolynAppTests/EnvironmentTests.swift` — covers every boundary
  in the prompt's section 32 test table exactly, plus timezone-change,
  DST spring-forward/fall-back, and midnight-rollover cases. This
  required adding a `testTarget` to `Package.swift`, which had none
  before.

**Not done in batch 1, on purpose:** weather (`WeatherSource`,
`WeatherCondition`, live WeatherKit, randomized weather), the actual
star-field/atmospheric renderer, environment interpolation across every
boundary (only the explicit 10:00-11:00 bridge carries a progress value
so far), Settings UI, and integration into `EntryView`/
`ModeSelectorView`. These are steps 7 onward in the prompt's own order
and are separate, later batches — not an oversight.

**Important limitation, same as the rest of this UI/UX pass, and more
so:** written without a Swift compiler available (no toolchain in this
sandbox at all — checked directly, not assumed). Carefully hand-
reviewed, but UNVERIFIED by actual compilation, and this batch also
touches `Package.swift` (new test target) and `IsolynApp.swift` (new
`.environment()` call) on top of the still-unverified existing shell.
The one area of genuine, flagged uncertainty within this batch itself
is the `NotificationCenter` observer closure in `EnvironmentManager`
hopping to `@MainActor` via `Task { @MainActor in ... }` — a standard,
common pattern, but the one piece of this batch's Swift-concurrency
wiring not double- or triple-checked by hand the way the time-math
itself was. Build in Xcode and resolve whatever it reports before
trusting this the way Sections 1-6 below can be trusted.

### Batch 2 — confirmed building clean in Xcode, zero errors.

### Batch 3 — star field + weather subsystem

`Sources/IsolynApp/Environment/`: `StarField.swift` (seeded procedural
placement, not the reference photos), `SkyCondition.swift`,
`WeatherSource.swift` (`WeatherMode`: live/randomized/off),
`RandomWeatherService.swift` (no dependencies), `LiveWeatherService.swift`
(WeatherKit, `#if canImport` guarded). `EnvironmentManager` now owns
`weatherMode` and `currentSkyCondition` alongside time/phase, refreshing
weather on its own slower timer.

`Sources/IsolynApp/Components/StarFieldView.swift`: Canvas +
`TimelineView` twinkle, keyed off the existing `starVisibility` curve,
respects Reduce Motion.

Defaults to `.randomized` weather — works with no extra setup. `.live`
needs the WeatherKit capability added in Signing & Capabilities; that's
real project configuration, not optional.

Per the user's direction, dedicated test files are being skipped from
here forward — verification is happening by building directly in Xcode,
not by shipping parallel test suites.

Not done: rain/snow particle rendering, environment composition,
settings UI, view integration. Still ahead in the prompt's order.

### Batch 4 — steps 14, 15, 16, 17 in one pass

- **14** `WeatherField.swift` + `WeatherEffectView.swift`: rain (fast
  streaks) and snow (small angular crosses, not dots — echoing the
  reference photo's crystalline geometry at particle scale) via Canvas
  + TimelineView.
- **15** `EnvironmentAppearanceCurve.composite(atMinute:condition:)`:
  weather now genuinely modifies the time appearance (star suppression,
  dimmed luminance, sky tint per condition) instead of sitting as an
  independent state. `AtmosphericBackgroundView` and `StarFieldView`
  both switched to it. New `EnvironmentView.swift` stacks atmosphere +
  stars + weather as one drop-in layer.
- **16** `EnvironmentSettingsView.swift`: weather-source picker
  (live/randomized/off) + current-condition readout.
- **17** Reduced Motion completed on the background layer too
  (transition animation now skips under Reduce Motion, matching stars
  and weather particles).

Also added: `FixedWeatherSource` and an optional `weatherSource:`
override on `EnvironmentManager.init` (previews/testing only),
`Hashable` on `WeatherMode`/`SkyCondition` for the settings picker.

Checked before packaging: brace balance across the full source tree,
and every remaining `appearance(atMinute:)` call site confirmed
migrated to `composite()` except one deliberate exception (a preview
strip showing the raw time-only curve on purpose).

Not done: WeatherKit's fuller robustness (section 16 — auth handling,
foreground refresh, caching), fog as a discrete effect beyond the tint,
view integration (EntryView/ModeSelectorView), placeholder replacement,
audit, polish.

### Batch 5 — steps 18, 19, 20, plus closing part of the section 16 gap

**View integration (18/19/20), done as one architectural move rather
than three separate insertions:** `EnvironmentView()` now sits once in
`RootView.swift`, behind the `switch appState.screen` — it persists
continuously across screen changes instead of resetting per-screen.
`EntryView.swift`, `ModeSelectorView.swift`, and `ComingSoonView.swift`
(which `GamePlaceholderView` is built on) each had their own flat
`IsolynTheme.ebony.ignoresSafeArea()` fill removed, since that was
completely covering the environment. This covers all four screens —
Entry, Mode Select, Game Placeholder, Coming Soon (Training/Sandbox) —
in one place.

**That removal created a real legibility problem, fixed, not just
noted:** `IsolynTheme.ivory` is `(0.949, 0.925, 0.867)` — checked
against the actual theme file, not assumed — which has almost no
contrast against the daytime sky colors. `EnvironmentView.swift` now
has a `LegibilityScrim` layer, a black overlay whose opacity tracks
`ambientLuminance` (~0.14 at night, up to ~0.87 at peak day, calibrated
from the real ivory/ebony values, not guessed). Cards (`ModeCard`) and
the primary button already had their own opaque backgrounds, so neither
needed any change — checked both files directly before concluding that.

**Section 16, partially closed:** `LiveWeatherService` now caches the
last successful condition and returns that on failure instead of `nil`,
so one bad fetch doesn't blank the weather out. `EnvironmentManager`
gained an `NSApplication.didBecomeActiveNotification` observer so time
and weather both refresh the moment the app comes back to the
foreground, not just on the next timer tick. Deliberately did NOT
rebuild location access on a full `CLLocationManagerDelegate` +
authorization-request flow — the simpler synchronous
`CLLocationManager().location` call already in place is the form that's
actually been confirmed compiling across four batches now, and the
delegate/continuation rewrite has more real API-surface uncertainty
(exact `CLAuthorizationStatus` cases on macOS specifically) than its
value justified against that track record. Worth a real pass later,
ideally with WeatherKit actually reachable to test against.

**Section 22:** `EnvironmentTimeLabel.swift` — small time readout,
reads `EnvironmentManager.state` directly rather than computing its own
time. Not wired into any screen yet; no clear placement decision to
make that call, so it's built and ready rather than guessed at.

Checked before packaging: brace balance across the full source tree,
confirmed all three screens' flat backgrounds were actually removed
(not just two of three), confirmed `RootView` correctly hosts
`EnvironmentView`.

Not done: the fuller WeatherKit auth flow just described, fog as a
discrete effect, audit pass, final polish, and placing
`EnvironmentTimeLabel`/`EnvironmentSettingsView` somewhere in the actual
UI (both exist as ready-to-use components, neither is on screen yet).

### Batch 6 — Audit and merge: `Isolyn-complete` + `Isolyn-environment-complete` → `Isolyn current`

This tree is the fused result of two previously separate exports:
`Isolyn-complete.zip` (the C++ engine, its test suite, docs, and the
early app shell -- authoritative for everything it contains) and
`Isolyn-environment-complete.zip` (batches 1-5 above, plus the five
shared Swift files it touched to wire itself in). From here on, this
merged tree is the one to keep working from; the two separate zips are
superseded.

**What actually changed in the merge, file by file:**
- `Package.swift`, `IsolynApp.swift`, `RootView.swift`,
  `EntryView.swift`, `ModeSelectorView.swift`, `ComingSoonView.swift`
  — environment's versions used (each diffed line-by-line first; every
  change is exactly the environment-integration work batch 5 above
  describes, nothing else). `GamePlaceholderView.swift`,
  `AppState.swift`, `Theme/IsolynTheme.swift` — carried over unchanged
  from `Isolyn-complete`, since the environment batch never touched
  them (confirmed directly: `GamePlaceholderView` only wraps
  `ComingSoonView` and paints nothing of its own, so it needed no edit
  either). `PrimaryCapsuleButtonStyle.swift`, `PipGlyph.swift`,
  `ModeCard.swift` — byte-identical between both exports, no conflict.
- All 11 `Sources/IsolynApp/Environment/*.swift` files, all 6
  environment-related `Components/*.swift` files, and
  `Tests/IsolynAppTests/EnvironmentTests.swift` — added as-is (with one
  fix, below). `Sources/IsolynEngine`, `Tests/IsolynEngineTests`,
  `docs/`, `run_tests.sh` — carried over unchanged; the environment
  export never touched the engine at all.

**Audit performed, with real verification where verification was
possible, not just a read-through:**
- The C++ engine was actually compiled and run, not just read: all 17
  `Tests/IsolynEngineTests` executables rebuilt clean under
  `-Wall -Wextra -Wpedantic` (zero warnings), all 313 checks passed,
  then the entire suite was rebuilt and rerun a second time under
  AddressSanitizer + UndefinedBehaviorSanitizer — zero sanitizer trips
  across all 17 binaries. The engine is solid. This part of the merge
  is a non-event.
- Every new/modified Swift file was read in full (there's no Swift
  toolchain available in the audit environment, so this was careful
  manual tracing, not a build) — the `TimePhase` boundary math, the
  `EnvironmentTransition` keyframe interpolation/smoothstep, and the
  `StarField` SplitMix64 RNG were all hand-traced against their
  intended behavior and are correct. Every `IsolynTheme.*` token the
  new code references was cross-checked against the actual theme
  file — all valid.
- **One real bug found and fixed:** `EnvironmentTests.swift`'s
  `test_timezoneChange_reclassifiesTheSameInstant` asserted that 05:00
  in New York is "deep night" in Singapore and expected `.night`.
  Checked against the real IANA tz database (not assumed): Singapore
  is UTC+8 and New York is UTC-5 in January, so Singapore is 13 hours
  *ahead*, not behind — 05:00 NY is 18:00 (6pm) in Singapore, which is
  `.primeDay`, not `.night`. Fixed the assertion and the comment. This
  test would have failed the first time anyone actually ran
  `swift test`.
- **One design-level concurrency finding, deliberately not fixed here
  — flagged for a real decision instead of a guessed one:**
  `EnvironmentManager`'s `weatherSource` property and
  `LiveWeatherService`'s `lastKnownGood` cache are both plain,
  unsynchronized mutable state: read from the periodic weather-refresh
  loop and the foreground-notification handler (background/
  non-isolated execution contexts), written from `setWeatherMode`
  (UI/MainActor), and, for `lastKnownGood`, mutated inside
  `currentCondition()` itself on whatever context calls it.
  `LiveWeatherService` is explicitly `@unchecked Sendable`, so the
  compiler won't catch this. In practice it needs two low-frequency
  events to land within milliseconds of each other (a weather-mode
  change, or an app foreground-activation, coinciding with the
  periodic timer tick — and the `lastKnownGood` half only matters in
  `.live` weather mode), so it's a real but narrow window, not
  something likely to have surfaced in ordinary Xcode testing. Not
  changed in this merge because the right fix is a real design choice,
  not a one-line correction — options, roughly in order of how much
  they touch: (a) make `EnvironmentManager`'s weather-refresh path
  `@MainActor` and capture `weatherSource` into a local before any
  `await`; (b) turn `LiveWeatherService` into an `actor` instead of a
  `@unchecked Sendable` class; (c) add an in-flight guard so
  overlapping `refreshWeather()` calls coalesce instead of racing.
  Worth a real pass; picking one is a decision for whoever does that
  pass, not something to guess at here.
- **Confirmed, not newly discovered:** `EnvironmentSettingsView` and
  `EnvironmentTimeLabel` compile and preview fine but aren't placed in
  any actual screen yet — this matches what batch 5 above already
  says ("no clear placement decision to make that call"), not a new
  gap. Still true in this merged tree.
- Nothing else turned up. Specifically checked and clean: no duplicate
  type declarations anywhere in the merged Swift tree; no retain
  cycles (every `Task`/`NotificationCenter` closure correctly uses
  `[weak self]`); every timer/task/observer started in
  `EnvironmentManager.init` is balanced by a matching cancel/remove in
  `deinit`; no swallow-all catches, raw `new`/`delete`, or
  division-by-count risk anywhere in the C++ engine.

**Still true, unchanged by this merge:** everything batch 5 above
lists as not done (the fuller WeatherKit auth flow, fog as a discrete
effect, final polish) is still not done. This merge was audit + fuse,
not a new batch of feature work.

**What to tell the next AI or human:** this tree (`Isolyn current`) is
now the one to open in Xcode and build from. Confirm it compiles and
run `swift test` for real — nobody has yet; the engine side was
verified here by actually compiling and running it, the Swift side was
verified by reading it closely, not by compiling it. Then decide on
the concurrency fix above before shipping `.live` weather mode to
anyone. The two source zips this was built from are now superseded by
this tree.

### Batch 7 — EntropySource replaced with a user-supplied direct-OS-CSPRNG shuffler; 1v1v1 dealing re-verified, not changed

The user reviewed the previous `EntropySource` (`std::random_device`
seeding a `std::mt19937_64`, reseeded fresh every call via `seed_seq`,
shuffled via `std::shuffle`) and supplied their own replacement: every
random draw now goes directly to the OS CSPRNG on each platform
(`BCryptGenRandom` / `getrandom()` / `SecRandomCopyBytes`), with a
hand-rolled, rejection-sampled Fisher-Yates shuffle instead of
delegating to `std::shuffle`. No PRNG is seeded or held anywhere in the
class anymore -- there is no PRNG at all.

**What actually changed:** `Sources/IsolynEngine/EntropySource.cpp` and
`.hpp` rewritten. The user's supplied file was a standalone CLI
validator built around its own local `Domino` struct, not this
codebase's `DominoTile` -- it could not be dropped in verbatim. What was
carried over exactly: the three platform-specific CSPRNG calls, the
"no insecure fallback, throw on failure" posture, and the
`-bound % bound` rejection-sampling technique for unbiased integer
generation. What changed in the port: genericized into
`template<typename T> shuffle(std::vector<T>&)` so `DominoSet`,
`Dealer`, and `MatchController` needed zero call-site changes; moved
every platform-specific header (`<windows.h>`, `<Security/Security.h>`,
etc.) out of the public header and into the .cpp, so nothing that
includes `EntropySource.hpp` transitively pulls in e.g. `windows.h`'s
macro pollution; renamed to match this codebase's existing style. The
empty/single-element guard in the shuffle loop (needed now that
Fisher-Yates is hand-rolled instead of delegated to `std::shuffle`,
which handled that internally) was preserved from the user's file --
dropping it would underflow `size() - 1` on an empty vector.

`Package.swift`: added an explicit `.linkedFramework("Security", ...)`
to the `IsolynEngine` target, since the new `SecRandomCopyBytes` call
needs it and this is a plain C++ target, not a Swift one, so it is not
linked automatically the way it might be for a Swift target.

`Tests/IsolynEngineTests/EntropySourceTests.cpp` extended with two new
sections: an empty/single-element regression guard (directly testing
the underflow risk above), and a 5000-trial structural permutation
check (every shuffle is exactly the original 28 tiles -- nothing
duplicated, missing, or invented) -- porting the spirit of the user's
own `--test N` validation mode into this project's existing
test-harness convention instead of as a separate CLI tool.

**Verified, not just read:** full 17-executable suite recompiled and
rerun clean -- **316/316 checks passing, zero warnings** under
`-Wall -Wextra -Wpedantic` (up from 313 before this change; +3 from the
new EntropySourceTests sections). `EntropySourceTests` (~7000 shuffles
across empty/single/full-size inputs), `DealerTests`, and
`DominoSetTests` -- the file that exercises the new code hardest, plus
its two real production call sites -- additionally rebuilt and rerun
clean under AddressSanitizer + UndefinedBehaviorSanitizer, zero trips.
The full 17-binary suite was not re-run under sanitizers this session
(timed out once as a combined batch); the three above are the only
ones that actually exercise `EntropySource`, so they're the only ones
sanitizers have anything to say about.

**Explicitly NOT changed, and confirmed unnecessary:** the user also
asked for the 1v1v1 hand size (9, not 7) and pool size (27, not 28,
0-0 removed) to be corrected. `Dealer::handSizeForMode` and
`Dealer::deal`'s 1v1v1 branch already implement exactly this -- see
ambiguity #4 below, and `DealerTests.cpp`'s "1v1v1 hand size, 0-0
removal, empty boneyard" section, which passed before this session's
changes and was re-confirmed passing (including under sanitizers) with
the new `EntropySource` wired in. No dealing logic was touched. This
was checked directly against the code, not assumed or re-explained away.

**Caveats for whoever picks this up next:**
- Only the Linux (`getrandom()`) branch has actually been compiled and
  run here -- there is no macOS or Windows toolchain in this sandbox.
  The `SecRandomCopyBytes` branch (the one that matters, since this
  ships on macOS) and the new `Package.swift` linker setting are
  syntactically correct and hand-reviewed but unverified by real
  compilation. Build in Xcode and confirm before trusting this the way
  the sanitizer-checked Linux path can be trusted.
- `EntropySource` still cannot be seeded or mocked -- unchanged from
  before, and deliberate (see the class comment): anything needing
  reproducibility goes through `SimulationEngine`'s separate
  `std::mt19937_64` path instead, never this one.

---

# ISOLYN HANDOFF — READ THIS ENTIRE FILE BEFORE DOING ANYTHING

This file is the single source of truth for continuing this project. It
assumes you have no memory of any prior conversation. It assumes you may
be a small, weak model. Every instruction below is written to be followed
literally, without needing to infer anything not stated. If anything in
this file conflicts with what you think you remember, THIS FILE WINS.

The user has one file you need before you can do anything:
**`Isolyn-foundation.zip`** — ask them to attach it. It contains 61
already-written, already-compiled, already-tested C++ files (278/278
tests passing at time of last export). Do not try to rebuild those files
from scratch. Extract the zip and start from there.

## Why this file exists

A prior session did a large amount of work in a temporary Linux sandbox
(`/home/claude`). That sandbox's filesystem is NOT persistent — it can
reset without warning, mid-conversation, with zero notice. When it reset,
every file that had not yet been zipped and delivered to the user was
permanently lost, even though many tool calls had reported "success"
moments earlier. The last successful export (`Isolyn-foundation.zip`)
survived because it was copied to a separate, durable location and
already handed to the user — but everything built AFTER that export was
gone with no way to recover it.

**The lesson, stated as a hard rule for you to follow:** zip and deliver
the current state to the user FREQUENTLY — after every meaningfully-sized
batch of work, not just at the end of a long session. Never let more than
one substantial piece of work sit unexported. Treat the sandbox as
hostile and temporary at all times.

---

## 1. What Isolyn is

A tournament-grade Albanian Dominoes analysis engine, targeting native
macOS. Two layers, strictly separated:

- **C++ engine** (namespace `isolyn`) — all game rules, state, move
  generation/validation/execution, hidden-information reasoning,
  evaluation. This is what exists so far. Zero Swift code exists yet.
- **Swift/SwiftUI app** — not started at all. No bridge, no UI, no app
  target. This is explicitly, deliberately deferred; the user chose to
  keep building the engine deeper before touching UI.

### The three governing documents and their authority

Three source documents established this project. Their relative
authority, resolved early and non-negotiable since:

1. **Master Prompt** — process document. Defines the phased methodology
   (Phase 1 read/analyze, Phase 2 clarify, Phase 3 architecture, Phase 4
   detailed specs, Phase 5 implement smallest-first, Phase 6 validate,
   Phase 7 profile/optimize, Phase 8 expand). Also sets engineering
   principles: correctness > brevity, no placeholder implementations, no
   TODO-driven architecture, testability designed in from the start,
   never fabricate probabilities, everything must be explainable.
2. **Rules Spec** — the LITERAL, FINISHED, authoritative ruleset. When it
   conflicts with the Concept Spec, Rules Spec wins, always.
3. **Concept Spec** — vision/philosophy/mission document (mission
   statement, hidden-information philosophy, evaluation philosophy,
   non-goals). Authoritative ONLY where Rules Spec is silent. Never
   overrides Rules Spec on an actual rule.

Full original text of all three documents is not reproduced here — the
user has them. What matters is every ambiguity between/within them that's
already been resolved (Section 3 below) so you never have to re-derive
that work.

### Explicit non-goals (from Concept Spec, still binding)

No neural networks, no LLMs, no reinforcement learning, no deep learning,
no human-game-database training. Monte Carlo / sampling methods are
permitted ONLY as a mathematically-justified way to handle hidden
information (determinization sampling), never as a wholesale replacement
for deterministic search with a real evaluation function.

---

## 2. Current verified state (as of the last successful export)

**61 files, ~4,225 lines, 278/278 automated checks passing**, compiled
clean under `g++ -std=c++20 -Wall -Wextra -Wpedantic` with zero warnings.
This is all inside `Isolyn-foundation.zip`. Directory layout:

```
Isolyn/
├── Package.swift                    (SPM manifest — confirmed by the
│                                      user to actually build in real
│                                      Xcode, not just this sandbox)
├── Sources/IsolynEngine/
│   ├── include/*.hpp                (22 headers)
│   └── *.cpp                        (21 source files)
├── Tests/IsolynEngineTests/
│   ├── TestHarness.hpp              (hand-rolled [pass]/[FAIL] harness,
│   │                                  no external dependency)
│   └── *Tests.cpp                   (14 test executables)
└── docs/
    ├── STRATEGY_NOTES.md            (captured domain/strategy knowledge
    │                                  — do not re-derive, it's already
    │                                  written and correctly scoped)
    └── FEATURE_SPECS.md             (Training Mode + Sandbox Mode specs,
                                       for whenever UI work starts)
```

### Modules that exist, verified, in the zip (do NOT rebuild these)

**Foundation:**
- `DominoTile` — value type, canonical dense index 0–27 (triangular
  numbering: `index = high*(high+1)/2 + low`), `value()`, `isDouble()`,
  `hasFace(pip)`.
- `DominoSet` — the fixed 28-tile set; `shuffledTiles(EntropySource&)`.
- `EntropySource` — genuinely non-deterministic shuffling (seeded fresh
  from `std::random_device` every call) for REAL gameplay only. Never
  used for search/simulation — see `Determinizer` below, which uses a
  separate, explicitly-seedable `std::mt19937_64` instead.
- `GameMode` — `enum class { OneVsOne, OneVsOneVsOne, TwoVsTwo }`.

**Rules & State:**
- `RulesEngine` — `determineOpeningPlay` (highest double, or highest
  SUM-value plain tile if nobody has a double — see ambiguity #2 below),
  `determineCloser`, `computeRoundScores`, `combineTeamValue`,
  `hasReachedMatchLossThreshold`, `determineNextRoundStarter`,
  `teamIndexForPlayer`/`playersOnTeam` (2v2: player%2 gives team; team 0
  = players {0,2}, team 1 = players {1,3} — a confident but NOT certain
  assumption, see ambiguity #9).
- `Dealer` — `deal()` (reshuffles past Misdeals automatically),
  `isMisdeal()`, `handSizeForMode()`, `playerCountForMode()`.
- `Chain` — the played-tile layout. Always a simple two-ended sequence,
  NEVER branches (Rules Spec is explicit doubles don't spinner/branch in
  this variant). Has full undo (`undoOpening`/`undoLeft`/`undoRight`) via
  internal history stacks.
- `Boneyard` — draw pool. `drawableCount() = max(0, size()-2)` — the
  final 2 tiles are always permanently locked, revealed via
  `lockedTiles()` once `drawableCount()==0`. Has `undoDraw` — engine/
  search use only, real play can never return a drawn tile.
- `GameState` — owns hands, `Chain`, `Boneyard`, current player, play
  history. `playTile()` returns a `PlacementKind` (Opened/AttachedLeft/
  AttachedRight) that `undoPlayTile()` needs to reverse correctly.
  **This constructor needs to be extended — see Section 4, item 2.**

**Move System:**
- `Move` (tile + side), `MoveGenerator` (`generate`, `hasAnyLegalMove`,
  `isPositionClosed` — this last one is THE shared primitive for "is the
  round over with no winner," used by both `MatchController` and
  `EvaluationEngine`), `MoveValidator`, `MoveExecutor` (apply/undo pairs).

**Orchestration:**
- `MatchController` — `dealFirstRound()` (applies the ONE-TIME mandated
  opening tile — see ambiguity #7, this was a real bug fix) vs.
  `dealSubsequentRound()` (starter is free to choose ANY tile, chain
  starts empty). Also `currentPlayerHasLegalMove`, `voluntaryDraw`,
  `resolveForcedDraw`, `playTurn`, `endTurnWithNoPlay`. Does NOT support
  undo (real gameplay doesn't need to rewind) — this is why `SearchEngine`
  (Section 4) does NOT go through `MatchController`, it uses
  `MoveGenerator`/`MoveExecutor`/`GameState` directly.
- `ScoreSystem` — running match scores, `hasMatchEnded`,
  `winningParticipant` (lowest score wins — assumption, see ambiguity
  #10).

**Evaluation (does NOT need hidden-info machinery — see note below):**
- `MobilityHeuristic`, `BlockingHeuristic`, `ExpectedValueHeuristic`,
  `ClosingOpportunityHeuristic` (formalizes the closing-vs-Domino
  reasoning in `STRATEGY_NOTES.md`; has a placeholder weight
  `kNextRoundStartBonus = 5.0`, NOT calibrated, needs real tuning later).
- `EvaluationEngine` — combines the four heuristics with placeholder
  weights (all currently `1.0`). Handles 2v2 team-combination correctly
  via `RulesEngine::teamIndexForPlayer`/`combineTeamValue`. **Critical
  design fact, already correct, do not "fix": `EvaluationEngine` operates
  on a single, already-concrete `GameState` and needs NO `BeliefState`/
  `ProbabilityEngine` dependency at all.** The averaging-across-hidden-
  uncertainty happens one level up, in `SearchEngine`, by calling
  `EvaluationEngine::evaluate()` once per sampled determinization and
  averaging the results. This is why `EvaluationEngine` could be (and
  was) built before any of the probability machinery existed.

**Hidden information:**
- `BeliefState` — per-(unseen tile, possible location) probability,
  where location is another player's index or `kBoneyardLocation = -1`.
  **Rigor status, stated exactly, do not blur this:**
  - Initial distribution (constructor): EXACT. Proportional to each
    location's share of the unseen pool — the direct combinatorial
    consequence of a uniform random deal.
  - `applyOpponentDraw(player)`: EXACT. Derived from exchangeability (the
    boneyard's fixed draw order came from an unobserved uniform shuffle,
    so "the next tile drawn" is statistically indistinguishable from a
    uniform pick over what remains). For every tracked tile:
    `moved = p(tile, boneyard) / B` (B = boneyard's total probability
    mass before the draw) is added to `p(tile, drawingPlayer)` and
    subtracted from `p(tile, boneyard)`. This provably preserves BOTH
    per-tile normalization AND per-location aggregate counts exactly —
    verified by direct algebra, not just tested.
  - `markTileKnown(tile, location, newLocationCount)`: a DOCUMENTED
    APPROXIMATION, not exact. Rescales the affected location's share for
    remaining tracked tiles to (approximately) hit the new count. Getting
    this exactly right for all locations simultaneously would need
    iterative proportional fitting (Sinkhorn-style), which is NOT
    implemented. `probability()` always normalizes on query (divides by
    that tile's own current total across locations), so an individual
    tile's distribution ALWAYS sums to exactly 1 even though the
    aggregate per-location aggregate can drift slightly after this call.
    This is intentional and documented in the code — do not "fix" it
    without understanding why it's hard (see the class comment in the
    zip's `BeliefState.hpp`).
- `ProbabilityEngine` — the GameState↔BeliefState bridge.
  `constructFromGameState(state, believerIndex)` builds a fresh
  `BeliefState` (correctly excludes the believer's own hand AND the
  chain AND any already-revealed locked boneyard pair from tracking).
  `observePlay`/`observeDraw` are thin event wrappers around
  `BeliefState`'s own update methods. `expectedRemainingValue` and
  `probabilityHoldsAtLeast` (exact Poisson-binomial DP, ≤7 trials since
  at most 7 tiles share any one pip value) are aggregate queries already
  built and tested — `probabilityHoldsAtLeast` directly implements the
  "missing a set" concept from `STRATEGY_NOTES.md`.
  **Explicit, stated extension point:** behavioral evidence (hesitation,
  declined draws — Concept Spec's "Behavioral Analysis") is NOT
  implemented. Doing it rigorously needs a calibrated likelihood model
  that doesn't exist yet; adding an arbitrary adjustment would violate
  "never fabricate probabilities." Leave this alone until there's a real
  calibration approach, don't guess at a number.

---

## 3. Every rules ambiguity found and how it was resolved

Do not re-litigate these. Each was found by careful reading, cross-
checked against both documents, and resolved with reasoning. Several were
caught specifically by building real code and real tests, not by reading
alone.

1. **Opening priority when nobody holds a double.** Rules Spec has this
   fallback explicitly ("highest numerical domino begins"); Concept Spec
   says "no exceptions" and doesn't address it. Rules Spec governs
   (literal, finished document wins).

2. **That fallback's tiebreak is ambiguous even within Rules Spec.** Its
   own examples (6-5 beats 6-4, 6-4 beats 6-3, 5-4 beats 5-3) all happen
   to share the same HIGH side, so they don't distinguish "rank by summed
   value" from "rank by high-side-first." Implemented as sum-based,
   justified because Section 1 already defines "value" as Left+Right for
   the whole document. Flagged, not fully certain.

3. **1v1's one-domino-left ritual's third exit condition** ("a player
   must draw more than one domino") is read as: if the single mandated
   draw isn't playable, the ritual ends for that player and ordinary
   Forced Drawing takes over.

4. **Boneyard only exists in 1v1.** 1v1v1 deals 9×3=27 plus removes 0-0
   = 28, zero remain. 2v2 deals 7×4=28, zero remain. Confirmed by the
   user. `Boneyard`'s formulas (`drawableCount() = max(0,size()-2)`)
   naturally handle an empty boneyard with zero special-casing.

5. **Misdeal's "8 dominoes" trigger** is stated for 7-tile modes only,
   literally wouldn't even apply to 1v1v1's 9-tile hands. Generalized to
   "any hand whose size doesn't match the mode's expected count" —
   flagged as a generalization beyond the literal text, not a certain
   reading. (Moot in practice: a fully digital deal can't actually
   miscount; this matters mainly for future externally-constructed
   positions.)

6. **1v1 doubles-cannot-close**, per Rules Spec: if the closing move was
   a double, credit walks back to the most recent NON-double play,
   through an entire run of consecutive doubles if needed. Explicitly
   1v1-only (1v1v1/2v2 explicitly allow doubles to close). Open question,
   not resolved: if EVERY play in the round was a double, neither
   document says what happens; falls back to crediting whoever played
   last rather than guessing further.

7. **THE BIG ONE — opening-tile selection is FIRST-ROUND-OF-MATCH-ONLY,
   not every round.** Originally implemented (incorrectly) as applying
   to every round. Caught when the user walked through their own real
   gameplay trace and freely chose their own opening tile (not the
   highest-sum tile, not compared against the opponent's hand at all) —
   which is impossible under "mandatory highest-double every round,"
   since that rule requires comparing hands nobody could see mid-match.
   Rules Spec's "the first round always begins with..." is textually
   scoped to the first round; "Beginning Future Rounds" is a SEPARATE
   rule that only says WHO starts (Domino winner / closer), never which
   tile. Fixed by splitting `MatchController`'s old single ambiguous
   constructor into `dealFirstRound()` (auto-applies the mandated tile,
   ONLY for the very first round of a whole match) and
   `dealSubsequentRound(mode, entropy, startingPlayerIndex)` (deals
   fresh, sets the given starter, leaves the chain EMPTY — that player
   freely chooses their own opening tile via ordinary `playTurn`, exactly
   matching the observed real play).

8. **The 1v1-only "One Domino Rule"** (both players down to exactly one
   tile: draw-one-before-attempting, repeating) is EXPLICITLY NOT
   IMPLEMENTED. The exact mechanics were worked through at length and the
   mechanism by which a Domino win could occur WITHIN the ritual (given
   normal play is exactly one placement per turn, and draw-one-then-
   play-one always nets back to the same hand size) is genuinely
   underspecified by both documents. Several readings were considered;
   none is clearly correct. This needs a real conversation with the user
   before implementing — don't guess.

9. **2v2 team-index mapping** (`playerIndex % 2`; team 0 = players
   {0,2}, team 1 = players {1,3}): inferred from "partners sit opposite"
   plus standard partnership-game seating convention. Confident enough to
   implement, not certain enough to treat as settled.

10. **Match-winner-among-3+-participants** (`ScoreSystem::
    winningParticipant`): neither document says what happens in 1v1v1
    when the threshold is crossed — whether the two non-crossing players
    both "win" or the lower of the two wins outright. Implemented as a
    single outright winner (strictly lowest score), matching convention
    in comparable games. Flagged, not certain.

11. **MoveValidator's win/close semantics — CONFIRMED, not just assumed.**
    "May not refuse to win/close" does NOT narrow the legal-move set to
    only the winning/closing move. It restates ordinary Mandatory Play
    (must make SOME legal move if one exists). Players legitimately,
    often correctly, choose a different legal move — this was explicitly
    confirmed by the user with detailed real-play reasoning (closing to
    regain next-round initiative even at a worse points outcome; see
    `STRATEGY_NOTES.md`). `MoveValidator::isLegal` does no such filtering,
    correctly, and this is settled — not open.

12. **CRITICAL, HARD-WON LESSON — every `BeliefState` MUST account for
    all 28 real tiles, always.** Two separate real test failures this
    session were caused by constructing small, artificial `GameState`s
    (e.g. 4 tiles total across two hands and a tiny boneyard) for test
    convenience, which is completely fine for testing `Chain`/`Boneyard`/
    `MoveGenerator`/`MatchController` (they only care about the specific
    tiles given to them) but is NOT fine for anything touching
    `BeliefState`/`ProbabilityEngine`, whose constructor asserts that
    `myKnownTiles + otherKnownTiles + sum(locationCounts)` accounts for
    literally all 28 tiles. **When writing any test that goes through
    `ProbabilityEngine::constructFromGameState` (or constructs a
    `BeliefState` directly), the hands + chain + boneyard MUST sum to
    exactly 28 tiles.** The reliable pattern used throughout: build
    `allTiles` via `DominoTile::fromIndex(0..27)`, put your specific
    tiles of interest wherever they need to be, and PAD everything else
    into a location that can't interfere with what you're testing (the
    believer's own hand is the safest padding target — extra known tiles
    there never affect tracked/uncertain behavior at all).

---

## 4. What is NOT yet built — exact code to add, in this exact order

None of this exists in the zip. All of it was fully designed, and in some
cases built and verified, before the session that lost it. The code below
is correct and hand-verified; it does not need to be re-derived, only
typed in and compiled.

### Step 1 — `Chain::fromKnownState`

Add to `Sources/IsolynEngine/include/Chain.hpp`, in the public section,
right after `orderedTiles()`:

```cpp
    // Constructs a Chain directly from an already-known, already-valid
    // state -- for reconstructing a chain whose orientation history
    // isn't available (SimulationEngine's determinized worlds; later,
    // PositionConstructor/loaded positions), rather than requiring it to
    // be rebuilt via placeOpening/placeLeft/placeRight. Trusts the
    // caller that `tiles` (left-to-right) and the given end values are
    // mutually consistent -- this reconstructs a state already known to
    // be valid, it does not validate one.
    //
    // The undo history starts empty for a chain built this way -- only
    // placements made AFTER this reconstruction can be undone; undoing
    // "into" the reconstructed base state is not supported and will
    // violate undoOpening's own precondition if attempted.
    static Chain fromKnownState(const std::deque<DominoTile>& tiles, int leftEnd, int rightEnd);
```

Add to `Sources/IsolynEngine/Chain.cpp`, at the end, before the closing
`} // namespace isolyn`:

```cpp
Chain Chain::fromKnownState(const std::deque<DominoTile>& tiles, int leftEnd, int rightEnd) {
    Chain chain;
    chain.m_tiles = tiles;
    chain.m_leftEnd = leftEnd;
    chain.m_rightEnd = rightEnd;
    return chain;
}
```

Add to `Tests/IsolynEngineTests/ChainTests.cpp`, before the final
`if (failureCount() == 0)` block:

```cpp
    section("Chain: fromKnownState reconstructs a chain matching a real one, without replaying moves");
    {
        Chain real;
        real.placeOpening(DominoTile(4, 4));
        real.placeLeft(DominoTile(4, 6));
        real.placeRight(DominoTile(4, 1));
        // real: leftEnd=6, rightEnd=1, orderedTiles=[4-6,4-4,4-1]

        Chain reconstructed = Chain::fromKnownState(real.orderedTiles(), real.leftEnd(), real.rightEnd());
        check(reconstructed.orderedTiles() == real.orderedTiles(), "reconstructed chain has the exact same tile sequence");
        check(reconstructed.leftEnd() == real.leftEnd() && reconstructed.rightEnd() == real.rightEnd(),
              "reconstructed chain has the exact same exposed end values");
        check(!reconstructed.isEmpty(), "the reconstructed chain correctly reports itself as non-empty");
    }
```

### Step 2 — Extend `GameState`'s constructor

This is the gap `SimulationEngine` (Step 4) depends on directly. Replace
the existing constructor DECLARATION in
`Sources/IsolynEngine/include/GameState.hpp` (find
`GameState(GameMode mode, std::vector<std::vector<DominoTile>> hands, std::vector<DominoTile> boneyardTiles);`)
with:

```cpp
    // Precondition, asserted: if `initialCurrentPlayerIndex` is given
    // explicitly (or even at its default of 0), it must be a valid index
    // into `hands`.
    GameState(GameMode mode,
              std::vector<std::vector<DominoTile>> hands,
              std::vector<DominoTile> boneyardTiles,
              Chain initialChain = Chain(),
              std::vector<PlayRecord> initialPlayHistory = {},
              int initialCurrentPlayerIndex = 0);
```

Also add this note to the class-level comment block (anywhere reasonable,
e.g. right after the existing "Undo:" paragraph):

```cpp
// Reconstruction: the extended constructor above also accepts an
// already-built Chain, an already-recorded play history, and an
// already-established current player -- every piece of this class's
// observable state -- for reconstructing a GameState representing a
// hypothetical world consistent with already-known public facts
// (SimulationEngine's determinized worlds), rather than requiring those
// facts to be rebuilt by replaying moves through playTile. All three
// default to their original empty/zero values, so every existing call
// site is unaffected.
```

Replace the existing constructor IMPLEMENTATION in
`Sources/IsolynEngine/GameState.cpp` with:

```cpp
GameState::GameState(GameMode mode,
                      std::vector<std::vector<DominoTile>> hands,
                      std::vector<DominoTile> boneyardTiles,
                      Chain initialChain,
                      std::vector<PlayRecord> initialPlayHistory,
                      int initialCurrentPlayerIndex)
    : m_mode(mode), m_hands(std::move(hands)), m_chain(std::move(initialChain)),
      m_boneyard(std::move(boneyardTiles)), m_currentPlayerIndex(initialCurrentPlayerIndex),
      m_playHistory(std::move(initialPlayHistory)) {
    assert(m_currentPlayerIndex >= 0 && m_currentPlayerIndex < playerCount() &&
           "initialCurrentPlayerIndex must be a valid player index for the given hands");
}
```

**Member initializer order matters for `-Wreorder`.** `GameState`'s
members are declared in this order: `m_mode, m_hands, m_chain,
m_boneyard, m_currentPlayerIndex, m_playHistory`. The initializer list
above matches that order exactly — do not reorder it.

Add to `Tests/IsolynEngineTests/GameStateTests.cpp`, before the final
`if (failureCount() == 0)` block:

```cpp
    section("GameState: the extended constructor correctly accepts a pre-built chain and play history");
    {
        Chain preBuilt;
        preBuilt.placeOpening(DominoTile(3, 3));
        preBuilt.placeRight(DominoTile(3, 5));

        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6) }, { DominoTile(1, 1) } };
        std::vector<PlayRecord> history = { PlayRecord{1, DominoTile(3, 3)}, PlayRecord{0, DominoTile(3, 5)} };
        GameState state(GameMode::OneVsOne, hands, {}, preBuilt, history, 1);

        check(!state.chain().isEmpty(), "the injected chain is used directly, not started empty");
        check(state.chain().leftEnd() == 3 && state.chain().rightEnd() == 5, "the injected chain's exposed ends are exactly as given");
        check(state.chain().orderedTiles() == preBuilt.orderedTiles(), "the injected chain's tile sequence is exactly as given");
        check(state.playHistory().size() == 2, "the injected play history is used directly, not started empty");
        check(state.playHistory()[0].playerIndex == 1 && state.playHistory()[1].playerIndex == 0,
              "the injected play history's contents are exactly as given, in order");
        check(state.currentPlayerIndex() == 1, "the injected current player index is used directly");
    }

    section("GameState: the extended constructor's defaults preserve prior behavior exactly");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6) }, { DominoTile(1, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});
        check(state.chain().isEmpty(), "omitting the new parameters still starts with an empty chain");
        check(state.playHistory().empty(), "omitting the new parameters still starts with empty play history");
        check(state.currentPlayerIndex() == 0, "omitting the new parameter still defaults current player to 0");
    }
```

### Step 3 — `Determinizer` (new files)

Create `Sources/IsolynEngine/include/Determinizer.hpp`:

```cpp
#pragma once
#include <map>
#include <random>
#include <utility>
#include <vector>
#include "BeliefState.hpp"
#include "DominoTile.hpp"

namespace isolyn {

// Samples one concrete, complete assignment of every tile BeliefState
// still tracks as uncertain to exactly one location, respecting the
// EXACT capacity given for each location -- never approximately, always
// exactly, since the resulting assignment must be usable to build a
// genuinely valid GameState.
//
// Algorithm: processes locations in a randomly shuffled order (reduces
// systematic bias from a fixed order); for each location but the last,
// samples WITHOUT REPLACEMENT, weighted by each remaining tile's current
// belief-state probability for that location, exactly that location's
// capacity; whatever's left after every location but the last goes
// entirely to the last one (guaranteed correct count, by BeliefState's
// own invariant that capacities sum to the total tracked-tile count).
//
// Honest limitation: this is a valid, capacity-exact,
// marginal-probability-weighted sample, NOT a mathematically exact draw
// from the true joint posterior (which would need iterative proportional
// fitting). For search -- averaging outcomes across many independent
// samples -- this is the standard, defensible approach.
//
// Uses a caller-supplied, explicitly-seedable std::mt19937_64 -- never
// EntropySource, which is deliberately non-reproducible for real-game
// fairness. Determinization is a controlled simulation and needs the
// opposite property: reproducibility for testing and debugging.
class Determinizer {
public:
    static std::vector<std::pair<DominoTile, int>> sample(const BeliefState& belief,
                                                            const std::map<int, int>& locationCounts,
                                                            std::mt19937_64& rng);
};

} // namespace isolyn
```

Create `Sources/IsolynEngine/Determinizer.cpp`:

```cpp
#include "Determinizer.hpp"
#include <algorithm>
#include <cassert>

namespace isolyn {

std::vector<std::pair<DominoTile, int>> Determinizer::sample(const BeliefState& belief,
                                                               const std::map<int, int>& locationCounts,
                                                               std::mt19937_64& rng) {
    std::vector<DominoTile> remaining;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        DominoTile tile = DominoTile::fromIndex(i);
        if (belief.isTracked(tile)) remaining.push_back(tile);
    }

    std::vector<int> locations;
    for (const auto& [location, count] : locationCounts) locations.push_back(location);
    std::shuffle(locations.begin(), locations.end(), rng);

    std::vector<std::pair<DominoTile, int>> assignment;

    for (std::size_t li = 0; li + 1 < locations.size(); ++li) {
        int location = locations[li];
        int capacity = locationCounts.at(location);

        for (int k = 0; k < capacity; ++k) {
            assert(!remaining.empty() &&
                   "ran out of tiles before every location's capacity was filled -- locationCounts inconsistent with belief's tracked tiles");

            double totalWeight = 0.0;
            for (const auto& tile : remaining) totalWeight += belief.probability(tile, location);

            std::size_t chosenIndex = 0;
            if (totalWeight <= 0.0) {
                std::uniform_int_distribution<std::size_t> uniform(0, remaining.size() - 1);
                chosenIndex = uniform(rng);
            } else {
                std::uniform_real_distribution<double> dist(0.0, totalWeight);
                double r = dist(rng);
                double cumulative = 0.0;
                for (std::size_t i = 0; i < remaining.size(); ++i) {
                    cumulative += belief.probability(remaining[i], location);
                    if (r <= cumulative) {
                        chosenIndex = i;
                        break;
                    }
                }
            }

            assignment.push_back({remaining[chosenIndex], location});
            remaining.erase(remaining.begin() + static_cast<long>(chosenIndex));
        }
    }

    if (!locations.empty()) {
        int lastLocation = locations.back();
        for (const auto& tile : remaining) {
            assignment.push_back({tile, lastLocation});
        }
    }

    return assignment;
}

} // namespace isolyn
```

Create `Tests/IsolynEngineTests/DeterminizerTests.cpp`:

```cpp
#include "Determinizer.hpp"
#include "TestHarness.hpp"
#include <map>
#include <random>
#include <string>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("Determinizer: every sample respects exact location capacities");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 21; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 3}, {2, 2}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(known, {}, locationCounts);

        std::mt19937_64 rng(42);
        auto assignment = Determinizer::sample(belief, locationCounts, rng);

        check(assignment.size() == 7, "every tracked tile appears exactly once in the assignment");

        std::map<int, int> observedCounts;
        for (const auto& [tile, location] : assignment) observedCounts[location]++;
        check(observedCounts[1] == 3, "opponent1 receives exactly its capacity (3), not approximately");
        check(observedCounts[2] == 2, "opponent2 receives exactly its capacity (2)");
        check(observedCounts[BeliefState::kBoneyardLocation] == 2, "boneyard receives exactly its capacity (2)");
    }

    section("Determinizer: repeated samples vary -- genuine randomness");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 24; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 2}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(known, {}, locationCounts);

        std::mt19937_64 rng(7);
        auto first = Determinizer::sample(belief, locationCounts, rng);
        auto second = Determinizer::sample(belief, locationCounts, rng);
        check(!(first == second), "two independent samples from the same belief produce different assignments");
    }

    section("Determinizer: over many trials, every equally-likely tile is actually selectable");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 25; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 1}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(known, {}, locationCounts);

        std::mt19937_64 rng(99);
        std::map<int, int> hitCounts;
        constexpr int kTrials = 300;
        for (int t = 0; t < kTrials; ++t) {
            auto sample = Determinizer::sample(belief, locationCounts, rng);
            for (const auto& [tile, location] : sample) {
                if (location == 1) hitCounts[tile.index()]++;
            }
        }
        check(hitCounts.size() == 3, "over 300 trials, all three equally-likely tiles were selected at least once");
        for (int idx = 25; idx <= 27; ++idx) {
            check(hitCounts[idx] > 0, "index " + std::to_string(idx) + " was selected for opponent1 at least once");
        }
    }

    if (failureCount() == 0) {
        std::cout << "\nDeterminizer: all checks passed\n";
        return 0;
    }
    std::cout << "\nDeterminizer: " << failureCount() << " check(s) failed\n";
    return 1;
}
```

### Step 4 — `SimulationEngine` (new files, depends on Steps 1-3)

Create `Sources/IsolynEngine/include/SimulationEngine.hpp`:

```cpp
#pragma once
#include <random>
#include "BeliefState.hpp"
#include "GameState.hpp"

namespace isolyn {

// Produces one complete, hypothetical GameState consistent with
// everything `believerIndex` actually knows in `realState`: their own
// hand, the visible chain (and its exposed ends), the turn/history state,
// are all copied exactly. Every other player's hand and the boneyard's
// still-uncertain portion are filled in from one sample drawn via
// Determinizer, weighted by `belief`. The boneyard's already-revealed
// locked tiles (if any) are appended after the sampled portion, in their
// real identities -- nothing about them is re-sampled, since they were
// never uncertain to begin with.
class SimulationEngine {
public:
    static GameState sampleDeterminizedState(const GameState& realState, const BeliefState& belief,
                                              int believerIndex, std::mt19937_64& rng);
};

} // namespace isolyn
```

Create `Sources/IsolynEngine/SimulationEngine.cpp`:

```cpp
#include "SimulationEngine.hpp"
#include "Determinizer.hpp"
#include <algorithm>

namespace isolyn {

GameState SimulationEngine::sampleDeterminizedState(const GameState& realState, const BeliefState& belief,
                                                     int believerIndex, std::mt19937_64& rng) {
    std::map<int, int> locationCounts;
    for (int p = 0; p < realState.playerCount(); ++p) {
        if (p == believerIndex) continue;
        locationCounts[p] = static_cast<int>(realState.hand(p).size());
    }
    auto realLocked = realState.boneyard().lockedTiles();
    locationCounts[BeliefState::kBoneyardLocation] = realLocked.empty()
        ? static_cast<int>(realState.boneyard().size())
        : 0;

    auto assignment = Determinizer::sample(belief, locationCounts, rng);

    std::vector<std::vector<DominoTile>> hands(static_cast<std::size_t>(realState.playerCount()));
    hands[static_cast<std::size_t>(believerIndex)] =
        std::vector<DominoTile>(realState.hand(believerIndex).begin(), realState.hand(believerIndex).end());

    std::vector<DominoTile> sampledBoneyardTiles;
    for (const auto& [tile, location] : assignment) {
        if (location == BeliefState::kBoneyardLocation) {
            sampledBoneyardTiles.push_back(tile);
        } else {
            hands[static_cast<std::size_t>(location)].push_back(tile);
        }
    }
    std::shuffle(sampledBoneyardTiles.begin(), sampledBoneyardTiles.end(), rng);

    std::vector<DominoTile> boneyardTiles = sampledBoneyardTiles;
    for (const auto& tile : realLocked) boneyardTiles.push_back(tile);

    // IMPORTANT: realState.chain().leftEnd()/rightEnd() assert-fail if
    // the chain is empty -- must guard this, cannot call
    // Chain::fromKnownState unconditionally.
    Chain chainCopy = realState.chain().isEmpty()
        ? Chain()
        : Chain::fromKnownState(realState.chain().orderedTiles(), realState.chain().leftEnd(), realState.chain().rightEnd());

    return GameState(realState.mode(), hands, boneyardTiles, chainCopy, realState.playHistory(), realState.currentPlayerIndex());
}

} // namespace isolyn
```

Create `Tests/IsolynEngineTests/SimulationEngineTests.cpp`:

```cpp
#include "SimulationEngine.hpp"
#include "ProbabilityEngine.hpp"
#include "TestHarness.hpp"
#include <algorithm>
#include <random>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("SimulationEngine: the determinized world exactly preserves everything the believer actually knows");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 14),
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 14, allTiles.end());
        GameState real(GameMode::OneVsOne, hands, boneyard);
        real.playTile(0, allTiles[0], GameState::ChainSide::Left);
        real.setCurrentPlayerIndex(1);

        BeliefState belief = ProbabilityEngine::constructFromGameState(real, 0);
        std::mt19937_64 rng(123);
        GameState world = SimulationEngine::sampleDeterminizedState(real, belief, 0, rng);

        check(world.mode() == real.mode(), "mode is preserved exactly");
        check(world.currentPlayerIndex() == real.currentPlayerIndex(), "whose turn it is is preserved exactly");
        check(world.hand(0).size() == real.hand(0).size(), "the believer's own hand size is preserved exactly");

        auto byIndex = [](DominoTile a, DominoTile b) { return a.index() < b.index(); };
        std::vector<DominoTile> realHand0Sorted(real.hand(0).begin(), real.hand(0).end());
        std::vector<DominoTile> worldHand0Sorted(world.hand(0).begin(), world.hand(0).end());
        std::sort(realHand0Sorted.begin(), realHand0Sorted.end(), byIndex);
        std::sort(worldHand0Sorted.begin(), worldHand0Sorted.end(), byIndex);
        check(realHand0Sorted == worldHand0Sorted, "the believer's own hand contents are exactly preserved");

        check(world.chain().orderedTiles() == real.chain().orderedTiles(), "the chain is exactly preserved");
        check(world.chain().leftEnd() == real.chain().leftEnd() && world.chain().rightEnd() == real.chain().rightEnd(),
              "the chain's exposed ends are exactly preserved");
        check(world.playHistory().size() == real.playHistory().size(), "play history is exactly preserved");
        check(world.hand(1).size() == real.hand(1).size(), "the opponent's hand SIZE is preserved, even though its contents are hypothetical");
    }

    section("SimulationEngine: the boneyard's already-revealed locked pair is copied exactly, never re-sampled");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 26),
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 26, allTiles.end());
        GameState real(GameMode::OneVsOne, hands, boneyard);

        BeliefState belief = ProbabilityEngine::constructFromGameState(real, 0);
        std::mt19937_64 rng(456);
        GameState world = SimulationEngine::sampleDeterminizedState(real, belief, 0, rng);

        check(world.boneyard().size() == 2, "the determinized world's boneyard is exactly the known, revealed locked pair");
        auto worldLocked = world.boneyard().lockedTiles();
        auto realLocked = real.boneyard().lockedTiles();
        check(worldLocked.size() == 2 && worldLocked[0] == realLocked[0] && worldLocked[1] == realLocked[1],
              "the specific revealed tiles match exactly");
    }

    section("SimulationEngine: an empty chain is handled correctly, without touching leftEnd/rightEnd on it");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 14),
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 14, allTiles.end());
        GameState real(GameMode::OneVsOne, hands, boneyard); // no plays yet -- chain is empty

        BeliefState belief = ProbabilityEngine::constructFromGameState(real, 0);
        std::mt19937_64 rng(789);
        GameState world = SimulationEngine::sampleDeterminizedState(real, belief, 0, rng);

        check(world.chain().isEmpty(), "an empty real chain correctly produces an empty determinized chain, not a crash");
    }

    if (failureCount() == 0) {
        std::cout << "\nSimulationEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nSimulationEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
```

### Step 5 — `SearchEngine` (new files, depends on Steps 1-4)

**Design summary before the code:** for each legal candidate move from
the REAL hand, sample many complete hypothetical worlds (via
`SimulationEngine`), search a bounded number of plies ahead WITHIN each
fully-determined world (no hidden information left to reason about once a
world is sampled), and average each candidate's outcome across every
sampled world. Highest average wins. Within a world, this is a MaxN
search (each player, including for 2v2 each TEAM via
`RulesEngine::teamIndexForPlayer`/`playersOnTeam`, picks the move
maximizing their own resulting value) — the natural N-player
generalization of minimax, reducing correctly to ordinary minimax-like
behavior for 1v1.

**Explicit scope decision:** this search explores placement moves and
MANDATORY forced drawing only (deterministic within any one sampled
world, since that world's whole boneyard is already fixed). It does NOT
explore VOLUNTARY drawing as a branch — that's a legitimate future
extension, not implemented here.

**Explicitly deferred, do not build prematurely:** an abstract
`ISearchEngine` interface. There is currently exactly one implementation;
introducing an interface before a second implementation needs one would
be premature infrastructure.

Create `Sources/IsolynEngine/include/SearchEngine.hpp`:

```cpp
#pragma once
#include <random>
#include <vector>
#include "BeliefState.hpp"
#include "GameMode.hpp"
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

struct SearchDecision {
    Move move;
    // One entry per player, EvaluationEngine score, averaged across
    // every sampled determinization for the CHOSEN move.
    std::vector<double> expectedValuePerPlayer;
};

class SearchEngine {
public:
    struct Config {
        int maxDepthPlies = 4;
        int determinizationCount = 20;
    };

    // Precondition: it is currently a player's turn to choose a move
    // (any forced-draw sequence at the root has already been resolved --
    // exactly as real play does via MatchController -- before this is
    // called).
    static SearchDecision chooseBestMove(const GameState& state, const BeliefState& belief, GameMode mode,
                                          const Config& config, std::mt19937_64& rng);

private:
    // Mutates `state` via MoveExecutor and GameState's own draw/undo
    // machinery, always restoring it exactly before returning.
    static std::vector<double> searchNode(GameState& state, GameMode mode, int depthRemaining);

    // The value a player is actually maximizing at an internal node:
    // their own EvaluationEngine score for 1v1/1v1v1, or their own score
    // PLUS their partner's for 2v2.
    static double decisionCriterion(const std::vector<double>& valuePerPlayer, int playerIndex, GameMode mode);
};

} // namespace isolyn
```

Create `Sources/IsolynEngine/SearchEngine.cpp`:

```cpp
#include "SearchEngine.hpp"
#include "EvaluationEngine.hpp"
#include "MoveExecutor.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "RulesEngine.hpp"
#include "SimulationEngine.hpp"
#include <cassert>
#include <limits>

namespace isolyn {

double SearchEngine::decisionCriterion(const std::vector<double>& valuePerPlayer, int playerIndex, GameMode mode) {
    if (mode != GameMode::TwoVsTwo) {
        return valuePerPlayer[static_cast<std::size_t>(playerIndex)];
    }
    auto team = RulesEngine::playersOnTeam(RulesEngine::teamIndexForPlayer(playerIndex));
    return valuePerPlayer[static_cast<std::size_t>(team.first)] + valuePerPlayer[static_cast<std::size_t>(team.second)];
}

std::vector<double> SearchEngine::searchNode(GameState& state, GameMode mode, int depthRemaining) {
    if (MoveGenerator::isPositionClosed(state)) {
        std::vector<double> values;
        for (int p = 0; p < state.playerCount(); ++p) {
            values.push_back(EvaluationEngine::evaluate(mode, state, p).total);
        }
        return values;
    }

    if (depthRemaining <= 0) {
        std::vector<double> values;
        for (int p = 0; p < state.playerCount(); ++p) {
            values.push_back(EvaluationEngine::evaluate(mode, state, p).total);
        }
        return values;
    }

    int player = state.currentPlayerIndex();

    // Deterministic forced-draw within this single, fully-known world --
    // no chance node needed, since the whole boneyard's contents are
    // already fixed by this determinization.
    std::vector<DominoTile> drawnForUndo;
    while (!MoveGenerator::hasAnyLegalMove(state, player) && state.boneyard().drawableCount() > 0) {
        drawnForUndo.push_back(state.drawTile(player));
    }

    std::vector<double> result;

    if (!MoveGenerator::hasAnyLegalMove(state, player)) {
        int next = (player + 1) % state.playerCount();
        state.setCurrentPlayerIndex(next);
        result = searchNode(state, mode, depthRemaining - 1);
        state.setCurrentPlayerIndex(player);
    } else {
        auto candidates = MoveGenerator::generate(state, player);
        assert(!candidates.empty());

        double bestCriterion = -std::numeric_limits<double>::infinity();
        std::vector<double> bestValues;

        for (const auto& move : candidates) {
            assert(MoveValidator::isLegal(state, player, move));
            auto applied = MoveExecutor::apply(state, player, move);

            std::vector<double> childValues;
            if (state.hand(player).empty()) {
                for (int p = 0; p < state.playerCount(); ++p) {
                    childValues.push_back(EvaluationEngine::evaluate(mode, state, p).total);
                }
            } else {
                int next = (player + 1) % state.playerCount();
                state.setCurrentPlayerIndex(next);
                childValues = searchNode(state, mode, depthRemaining - 1);
                state.setCurrentPlayerIndex(player);
            }

            double criterion = decisionCriterion(childValues, player, mode);
            if (criterion > bestCriterion) {
                bestCriterion = criterion;
                bestValues = childValues;
            }

            MoveExecutor::undo(state, applied);
        }

        result = bestValues;
    }

    for (auto it = drawnForUndo.rbegin(); it != drawnForUndo.rend(); ++it) {
        state.undoDrawTile(player, *it);
    }

    return result;
}

SearchDecision SearchEngine::chooseBestMove(const GameState& state, const BeliefState& belief, GameMode mode,
                                             const Config& config, std::mt19937_64& rng) {
    int player = state.currentPlayerIndex();
    auto candidates = MoveGenerator::generate(state, player);
    assert(!candidates.empty() && "chooseBestMove requires the current player to already have a legal move");

    std::vector<std::vector<double>> accumulated(candidates.size(), std::vector<double>(static_cast<std::size_t>(state.playerCount()), 0.0));

    for (int sample = 0; sample < config.determinizationCount; ++sample) {
        GameState world = SimulationEngine::sampleDeterminizedState(state, belief, player, rng);

        for (std::size_t c = 0; c < candidates.size(); ++c) {
            GameState trial = world; // GameState is cheap to clone by design
            auto applied = MoveExecutor::apply(trial, player, candidates[c]);

            std::vector<double> values;
            if (trial.hand(player).empty()) {
                for (int p = 0; p < trial.playerCount(); ++p) {
                    values.push_back(EvaluationEngine::evaluate(mode, trial, p).total);
                }
            } else {
                int next = (player + 1) % trial.playerCount();
                trial.setCurrentPlayerIndex(next);
                values = searchNode(trial, mode, config.maxDepthPlies - 1);
            }

            for (std::size_t p = 0; p < values.size(); ++p) {
                accumulated[c][p] += values[p];
            }

            MoveExecutor::undo(trial, applied);
        }
    }

    std::size_t bestIndex = 0;
    double bestCriterion = -std::numeric_limits<double>::infinity();
    for (std::size_t c = 0; c < candidates.size(); ++c) {
        for (double& v : accumulated[c]) v /= config.determinizationCount;
        double criterion = decisionCriterion(accumulated[c], player, mode);
        if (criterion > bestCriterion) {
            bestCriterion = criterion;
            bestIndex = c;
        }
    }

    return SearchDecision{candidates[bestIndex], accumulated[bestIndex]};
}

} // namespace isolyn
```

Create `Tests/IsolynEngineTests/SearchEngineTests.cpp`. **This test
scenario was hand-verified move-by-move before this document was
written — do not alter the specific tiles chosen, they are load-bearing
for the puzzle to have a determinate correct answer:**

```cpp
#include "SearchEngine.hpp"
#include "ProbabilityEngine.hpp"
#include "TestHarness.hpp"
#include <deque>
#include <random>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("SearchEngine: correctly looks ahead to avoid handing the opponent an immediate Domino win");
    {
        // Chain opens with 4-4 (double, both ends show 4). Player 0
        // holds 4-6 and 4-1; player 1 holds only 6-6.
        //
        // Playing 4-6 first changes the touched end to 6 -- which
        // immediately hands player 1's 6-6 a legal move, and since it's
        // their only tile, an immediate Domino win for THEM.
        //
        // Playing 4-1 first changes the touched end to 1 instead -- 6-6
        // still matches nothing, player 1 is stuck with no boneyard to
        // draw from, and player 0's remaining 4-6 still matches the
        // untouched end (4), winning by Domino themselves next turn.
        //
        // A search with enough depth to see player 1's reply must prefer
        // 4-1 over 4-6.
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(4, 6) || t == DominoTile(4, 1) || t == DominoTile(6, 6)) continue;
            padding.push_back(t); // 25 tiles, naturally including 4-4 as the "opener"
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 4, 4);

        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(4, 6), DominoTile(4, 1) }, // player 0 -- the choice under test
            { DominoTile(6, 6) },                     // player 1 -- their only remaining tile
        };
        // 2 (player0) + 1 (player1) + 25 (chain) + 0 (boneyard) = 28.
        GameState state(GameMode::OneVsOne, hands, {}, chain, { PlayRecord{1, DominoTile(4, 4)} }, 0);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(2024);
        SearchEngine::Config config;
        config.maxDepthPlies = 4;
        config.determinizationCount = 1; // nothing is actually uncertain here -- only 6-6 is tracked, and locationCounts forces it to player 1 with certainty
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng);

        check(decision.move.tile == DominoTile(4, 1),
              "the search correctly avoids 4-6 (hands player 1 an immediate Domino win) and finds 4-1 instead");
    }

    section("SearchEngine: with only one legal candidate, it's chosen trivially and correctly evaluated");
    {
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(5, 5) || t == DominoTile(1, 1)) continue;
            padding.push_back(t); // 26 tiles, naturally including 5-2 as the "opener"
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 2, 5); // as if opened with 5-2: leftEnd=2, rightEnd=5

        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(5, 5) }, // player 0's only tile -- will Domino
            { DominoTile(1, 1) },
        };
        // 1 + 1 + 26 + 0 = 28.
        GameState state(GameMode::OneVsOne, hands, {}, chain, { PlayRecord{1, DominoTile(5, 2)} }, 0);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(1);
        SearchEngine::Config config;
        config.maxDepthPlies = 2;
        config.determinizationCount = 1;
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng);

        check(decision.move.tile == DominoTile(5, 5), "the only legal move is correctly identified and chosen");
        check(decision.expectedValuePerPlayer[0] == 0.0,
              "player 0's evaluation reflects an immediate Domino win -- an empty hand scores 0, the best possible ExpectedValueHeuristic outcome");
    }

    if (failureCount() == 0) {
        std::cout << "\nSearchEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nSearchEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
```

---

## 5. Exact instructions for what to do, in order

1. Ask the user to attach `Isolyn-foundation.zip` if it isn't already in
   context. Do not proceed without it — do not try to reconstruct the 61
   already-built files from this document, they are not reproduced here.
2. Extract it into a working directory (e.g. `/home/claude/Isolyn`).
3. Compile and run the EXISTING 14 test executables first, exactly as
   they are, to confirm the starting point is genuinely intact before
   changing anything. Use `g++ -std=c++20 -Wall -Wextra -Wpedantic`.
   Confirm 278/278 pass.
4. Apply Steps 1–5 from Section 4 above, in that exact order (each step
   depends on the previous one compiling correctly).
5. After EACH step, compile and run everything built so far, including
   the pre-existing 14 test executables (some of them — `ChainTests`,
   `GameStateTests` — are directly modified by Steps 1–2 and must be
   reverified, not assumed to still pass).
6. **Zip and deliver to the user after Step 2 (Chain + GameState), and
   again after Step 3 (Determinizer), and again after Step 4
   (SimulationEngine), and again after Step 5 (SearchEngine). Do not wait
   until everything is done to export. This is not optional — re-read
   the "Why this file exists" section at the top if this instruction is
   unclear.**
7. Once all five steps are done and verified, the natural next module is
   `DifficultyModel` (map a continuous strength value, 100.00–3000, to
   concrete `SearchEngine::Config` parameters — deeper search and more
   determinizations at higher strength; exact mapping not yet designed,
   this is real, undone work) — but confirm with the user before starting
   it, the same way every other major module in this project has been
   confirmed before being built.

## 6. Style and process rules this project has followed throughout

Match these, they are established, not optional:

- Every claim about correctness must be backed by an actual compile and
  an actual test run shown to the user — never assert something works
  without having run it. Several real bugs were caught exactly this way
  this session; assuming correctness without running it would have
  shipped them.
- When a rule or design point is genuinely ambiguous, say so explicitly,
  pick the most defensible interpretation, implement THAT, and document
  the ambiguity in code comments and to the user — never silently guess,
  never silently invent a rule.
- No placeholder implementations, no TODO-driven architecture. If
  something is out of scope for now, say so explicitly and explain why,
  rather than stubbing it.
- The user has provided extensive real-world strategic domain knowledge
  (tournament-level play, personal reasoning traces, elo-gap
  observations) — all captured in `docs/STRATEGY_NOTES.md`, which
  survived in the zip. Read it before building anything in
  `EvaluationEngine`/`ProbabilityEngine`/`DifficultyModel` further — it
  contains hard-won, concrete, non-obvious insight (the "5+ tiles
  including the double = not missing a set" threshold; the boneyard
  full-drain tactic; score-proximity-driven playstyle shifts; the
  double-locking endgame tactic) that should inform those modules'
  design, not be treated as flavor text.
