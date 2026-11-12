# Bridge Architecture

What the Swift/C++ bridge is, why it's shaped the way it is, and what it deliberately does not do. Companion to `docs/BRIDGE_TESTING.md` (how it's been verified) and `Sources/IsolynEngineBridge/include/IsolynBridge.hpp` (the actual contract — this document explains it, the header IS it).

## What this is

A narrow layer between the SwiftUI app (`Sources/IsolynApp`) and the authoritative C++ engine (`Sources/IsolynEngine`). It exists because nothing wired the two together before this — `Package.swift` said so explicitly ("no Swift/C++ interop is wired up here... future work"), and a repo-wide search turned up zero prior bridge/adapter/interop artifacts of any kind. This is not a refactor of something that existed; it's new.

It is not a rules engine, not a strategy engine, not UI. `IsolynEngine` already owns all of that, is already thoroughly tested (`run_tests.sh`, 426 checks across 19 executables as of 2026-11-11), and this bridge does not reimplement any of it. What it adds is exactly three things the engine doesn't provide on its own: a boundary that's safe to call from Swift with untrusted/malformed input, a place for the one piece of concurrency policy the engine has no opinion about (analysis must not block the UI), and a stable, minimal, POD-only surface that doesn't leak C++ internals into Swift.

## Two facts about the engine that shaped every other decision here

These came from reading the actual `.cpp` files, not from assuming API behavior from headers — see `legacy handoff.md` §5.6 for the fuller audit trail.

**1. The engine enforces nothing at its own boundary.** `MatchController::playTurn` and `MoveExecutor::apply` check their legality precondition via `assert(MoveValidator::isLegal(...))` — and `assert()` compiles to nothing under `NDEBUG`, which Xcode's Release configuration defines by default. Calling either with an illegal move in a Release build is undefined behavior in the engine, not a safe rejection. This is why `bridge_submit_move` explicitly calls `MoveValidator::isLegal` itself before ever touching `MatchController`, regardless of build configuration — the bridge is the actual enforcement point, not a redundant extra check on top of one the engine already does. Same story for `resolveForcedDraw`/`endTurnWithNoPlay`'s `currentPlayerHasLegalMove()` precondition.

**2. The engine has zero internal concurrency support.** A direct grep across every `.cpp`/`.hpp` in `Sources/IsolynEngine` for `mutex`, `atomic`, `std::thread`, `lock_guard`, `condition_variable`, `thread_local` returns nothing (one incidental hit was an English comment, not code). `GameState`, `MatchController`, and everything downstream are ordinary value types with ordinary mutation — safe to use from one context at a time, and a data race the moment two threads touch the same live object concurrently. "The bridge is thread-safe" would therefore be a false claim on its own; what the bridge actually provides is described below.

## Threading model

Two different guarantees, layered:

- **Per-session mutex (`EngineSessionImpl::mutex` in `IsolynBridge.cpp`).** Every command and query takes this lock for the duration of its (always fast — the engine's mutating operations are all O(hand size) at most) work. This is defense in depth, not the primary design: it means a caller that violates the intended serialization discipline gets blocking, not a silent data race. It was not in the original design — added during review of an independently-written draft of this same bridge, and kept as defense in depth because it protects callers even if the intended actor discipline is violated. The Swift package now compiles and runs on this machine, but a mutex still makes misuse fail safely rather than silently race.
- **Swift actor (`EngineSession` in `Sources/IsolynApp/Engine/EngineSession.swift`).** The intended primary mechanism. One `EngineSession` actor per session; all command/query calls against it are automatically serialized by the language, not by convention.

**Analysis is the deliberate exception**, because `SearchEngine::chooseBestMove` (depth 4 × 20 determinizations by default) is genuinely slow, and nothing else on a session should have to wait behind it. This works specifically because of how the engine is designed, not despite it:

1. `bridge_analysis_snapshot_create` (phase 1) takes the mutex, copies the live `GameState` and constructs a `BeliefState`, and releases the mutex — cheap, because `GameState` is documented as cheap to clone by design.
2. `bridge_analysis_run` (phase 2) operates only on that independent copy — it never touches the originating session, the mutex, or any shared state except one `std::atomic<bool>` cancellation flag owned by the snapshot itself. It is safe to call from any thread, and does not block anything else happening on the session.

The Swift side mirrors this exactly: phase 1 runs actor-isolated (`EngineSession.requestAnalysis`), phase 2 runs on `Task.detached` specifically (a plain `Task` would inherit the caller's actor context, defeating the point).

**Handle tables get their own small mutex too** (`HandleTable` in `IsolynBridge.cpp`), separate from the per-session one — because a desktop app isn't guaranteed to have only one session alive, table insert/lookup/erase needed to be safe across sessions, and this is a fast, uncontended, never-held-during-slow-work lock, not a scalability concern.

## Cancellation

`SearchEngine::chooseBestMove` gained an additive `cancelRequested` parameter (`Sources/IsolynEngine/include/SearchEngine.hpp`) — `nullptr` by default, reproducing every existing call site's behavior exactly. When supplied, it's checked once before each determinization sample begins (never mid-sample — a sample already running always finishes and is fully counted before the next check). This is a deliberate trade-off: responsiveness is bounded by "one sample's worth of work," not instant, in exchange for never needing to abort a half-finished recursive search or leave `GameState` mutated mid-evaluation.

`bridge_analysis_request_cancel` sets the snapshot's own flag; safe from any thread, at any time, idempotent. It does not make `bridge_analysis_run` return early relative to whatever sample is already in flight — see `AnalysisOutcome.completed`/`samplesCompleted` for how a cancelled-partway result is reported honestly rather than presented with the same confidence as a completed one.

## Ownership: handles, not pointers

`SessionHandle` and `AnalysisHandle` are plain `uint64_t` tokens looked up in an internal table, not opaque pointers. Two concrete reasons, not a style preference:

- **Genuine idempotent close.** Looking up an unknown/already-erased ID in a table is always safe. Checking `->closed` on a `delete`d raw pointer is not — that's a real use-after-free regardless of how careful the check looks. `bridge_session_close`/`bridge_analysis_snapshot_destroy` being safe to call twice, or on a value that was never valid, is a real property this design has, not a documented-but-unenforced hope.
- **Zero import ambiguity.** Plain integers cross into Swift unambiguously no matter which exact Cxx-interop behavior a given Xcode version has for opaque pointer types — a real unknown this project has no way to resolve without a compiler (see `docs/BRIDGE_TESTING.md`'s Swift-side caveats).

IDs are never reused (monotonic counters), so there's no ABA-style risk of a stale handle later addressing a different, unrelated session.

`HandleTable` entries are held via `shared_ptr`, not `unique_ptr`. This closes a specific real risk: `bridge_analysis_run` can run for a while on a background thread, fully independent of the session it came from — if `bridge_analysis_snapshot_destroy` were called on that same handle while a run was still in flight (a caller bug, or a deliberate abandon-and-cleanup path), a raw pointer captured before that race would go dangling mid-use. A `shared_ptr` handed back from `find()` keeps the object alive for as long as the caller holds it, so `erase()` only ever drops the table's own reference.

## Error model

Every failure mode is a typed `BridgeStatus` (`Ok`, `InvalidRequest`, `InvalidMove`, `SessionClosed`, `StaleRequest`, `NotYourTurn`, `NoLegalMove`, `BoneyardEmpty`, `EngineFailure`, `BridgeFailure`), never a thrown exception crossing into Swift and never a silent no-op. `IsolynBridge.cpp`'s only real throw site to guard against is `EntropySource`'s OS-CSPRNG failure path — confirmed by a full `throw` grep across the engine — but every bridge function wraps its body in `catch (...)` regardless, so a future change on either side of the boundary can't accidentally leak an exception into Swift without anyone noticing.

Invalid input fails closed: rejected, typed error returned, nothing mutated. This isn't a policy statement — `bridge_submit_move`'s state-version check happens before `MoveValidator::isLegal`, which happens before any call into `MatchController`, so there's no code path where a rejected command has already touched engine state by the time the rejection is returned.

## State versioning

Every session tracks a monotonically increasing `stateVersion`, bumped on every successful mutating command. Every mutating command takes `expectedStateVersion` and rejects with `StaleRequest` (mutating nothing) on a mismatch. This does two jobs at once: it's how a UI can tell "did anything change since I last looked," and it's how an accidentally double-submitted command (the same tap registered twice, a retried network-adjacent call, whatever) fails closed as stale on its second occurrence instead of applying twice — the same mechanism, not two separate ones.

## Snapshot model — hidden information

`SnapshotDTO` is always taken from one specific player's point of view. During play, only that player's own hand carries real tile identities; every other player's hand is a size only (`otherHandSizes`), never contents. When the round reaches a terminal outcome, `finalRevealedTiles` and `finalHandCounts` expose the actual remaining tiles for every seat, matching the physical table turning hands face up at the end. That is the only reveal path: all reveal entries are sentinels/zero while `roundOutcome == InProgress`. `legalMovesForRequestingPlayer` is populated only when it's actually that player's turn — there's no legitimate reason to compute or expose legal moves for a hand the requester can't see, so it isn't computed at all otherwise, not just hidden by convention.

This mirrors how the engine itself keeps hidden and known information structurally separate (`BeliefState`/`ProbabilityEngine`) rather than trusting a caller not to look at something it was handed. Verified directly in `Tests/IsolynEngineBridgeTests/SmokeTest.cpp`: mid-round snapshots requested by one player and by the other both show only their own hand's real contents; at round end, the reveal counts match the racks, the revealed tiles sum to `finalHandValues`, and unused slots remain sentinels.

## Why the DTOs are POD-only, fixed-size, no STL

Every public type in `IsolynBridge.hpp` is a plain enum, a plain struct of primitives and fixed C arrays, or a `uint64_t` handle — no `std::vector`, `std::string`, `std::optional`, references, or templates cross the boundary. This is the most conservative reading of "narrowest boundary the actual toolchain supports," chosen for stable interop rather than relying on STL bridging behavior that varies by toolchain. The Swift target compiles this header and exercises it in the package tests. Fixed arrays are sized against the game's actual hard ceiling (28 tiles, `kTotalTileCount`) rather than a "typical" smaller number, specifically because Sandbox Mode (`docs/FEATURE_SPECS.md`) allows arbitrary, user-constructed positions — truncating real data to fit an assumed-typical bound would silently corrupt whatever didn't fit.

The cost of this choice lands entirely on the Swift side: a fixed C array imports into Swift as a tuple, not an `Array`, which is genuinely awkward to consume directly. `Sources/IsolynApp/Engine/EngineTypes.swift` handles this with one reusable `withTupleAsArray` helper (pointer-reinterpretation from tuple memory to a typed buffer, which is safe because the two are guaranteed to have identical layout) rather than hand-writing tuple-accessor code per field.

## Explicitly out of scope

Said plainly rather than silently dropped, matching this project's own established documentation standard:

- **Sandbox Mode's arbitrary starting positions.** No bridge entry point accepts a caller-constructed `GameState` — `docs/FEATURE_SPECS.md` calls for a `PositionConstructor` on the engine side that doesn't exist yet. Nothing to bridge to until that's built.
- **A `bridge_analysis_run` pinned against a concurrent `bridge_analysis_snapshot_destroy`.** `find()` on the analysis handle table only guarantees the snapshot was valid at that instant, not for the whole (potentially long) remainder of a run call. In practice this is safe under the documented discipline (destroy only after run returns; use `bridge_analysis_request_cancel` to ask an in-flight run to stop, never destroy underneath it) — but it's a caller-discipline guarantee, not a structurally-enforced one, unlike the shared_ptr fix that closed the equivalent gap for session handles. A generation-checked handle or reference count on the analysis side would close this properly; it's real, scoped, undone work, not something to improvise under this pass's time constraints.
- **Native visual and on-device performance behavior.** The Swift package compiles and its headless tests run on macOS, but this document cannot prove what the running window looks like or how search latency feels in the packaged app. Those remain manual checks.

---

## Match orchestration (added Phase 1)

The bridge now carries a running-score surface, closing the largest item in
this file's original "explicitly out of scope" list. The design split decided
there held: **scoring math stays in the engine** (ScoreSystem /
RulesEngine::computeRoundScores / combineTeamValue / thresholds -- single
source of truth), and this surface is data plumbing only:

- `bridge_match_begin(mode)` -> `MatchHandle` wrapping one running ScoreSystem
  (same HandleTable pattern: shared_ptr entries, monotonic IDs, idempotent
  close).
- `SnapshotDTO.finalHandValues[kMaxPlayers]` -- per-player remaining pip value,
  populated ONLY when roundOutcome != InProgress (reveal-on-end; zero during
  play, so no hidden information leaks mid-round).
- `SnapshotDTO.finalRevealedTiles[kMaxPlayers * kTotalTileCount]` and
  `finalHandCounts[kMaxPlayers]` -- the actual remaining tile identities and
  counts, populated under the same terminal-outcome guard. This is what the
  round-end card turns face up; it is never sent mid-round.
- `bridge_match_record_round(match, finishedSession)` -- team-combines for 2v2,
  computes participant scores, applies them, derives nextRoundStarterIndex from
  that round's cachedDecidingPlayer via RulesEngine::determineNextRoundStarter.
  Fails closed on: round still in progress, session already recorded into this
  match (no double-apply, ever), or match already ended. Lock ordering when
  touching both surfaces is SESSION->MATCH everywhere (single global order).
- `bridge_match_close(handle)` -- idempotent like every other close.

Policy lives Swift-side in `MatchCoordinator` (@MainActor @Observable): owns
the handle, publishes scores/winner/next-starter, drives
`EngineSession.recordRoundInto(matchHandle:)` through the actor so recording
serializes with the session's own command stream.

Verified: SmokeTest match section (record/duplicate-reject/starter/
accumulation/idempotent close) plus the reveal-on-end assertions -- current
bridge suite 73/73; ASan+UBSan clean over the new paths; Swift package
currently 68 tests, 1 skipped, 0 failures.
