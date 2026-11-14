import Foundation
import IsolynEngineBridge

// See EngineTypes.swift's header comment for the two known Cxx-interop
// uncertainties (namespace access spelling, fixed-array-as-tuple) that
// apply to every isolyn.bridge.* call in this file too -- not repeated
// here to avoid two copies of the same explanation drifting apart.

/// The actor-isolated Swift wrapper around one bridge session handle.
/// See IsolynBridge.hpp rule 3 for why this must be an actor (or
/// equivalent serialization) rather than a plain class: the C++ side is
/// not internally synchronized with respect to a session's own game
/// state (only its own handle-table bookkeeping is -- see
/// IsolynBridge.cpp's HandleTable), so all command and query calls
/// against ONE session must be serialized. An actor gives that for free,
/// as a compile-time property, rather than a discipline every call site
/// has to remember to uphold.
///
/// Deliberately a thin, faithful, 1:1 mirror of IsolynBridge.hpp's own
/// command/query/analysis shape -- no game-flow policy lives here (e.g.
/// this does NOT auto-call resolveForcedDraw when a player is blocked).
/// The bridge itself stays "boring" on purpose (see
/// docs/architecture/BRIDGE_ARCHITECTURE.md); layering policy like that belongs in
/// whatever consumes EngineSession once real gameplay UI exists, not in
/// this wrapper.
///
/// Analysis is the one operation NOT fully actor-isolated: phase 1
/// (bridge_analysis_snapshot_create) runs ON this actor since it reads
/// live session state, but phase 2 (bridge_analysis_run, the expensive
/// part) is dispatched to a detached background Task -- matching the
/// bridge's own two-phase design. An expensive multi-second search must
/// never block this actor, or every other operation on this session
/// (submitting a move, closing, even reading a snapshot) would queue up
/// behind it -- see requestAnalysis below.
actor EngineSession {
    private var handle: isolyn.bridge.SessionHandle?

    private init(handle: isolyn.bridge.SessionHandle) {
        self.handle = handle
    }

    // MARK: - Lifecycle

    /// Deals the first round of a brand-new match (the mandated opening
    /// tile is applied automatically). Returns nil on a genuine engine
    /// failure (EntropySource's OS CSPRNG failing -- see
    /// IsolynBridge.hpp) -- vanishingly rare, but a real possible outcome
    /// this can't paper over with a non-optional return.
    static func createFirstRound(mode: MatchFormat) -> EngineSession? {
        let h = isolyn.bridge.bridge_session_create_first_round(mode.bridgeMode)
        guard h != isolyn.bridge.kInvalidSessionHandle else { return nil }
        return EngineSession(handle: h)
    }

    /// Deals a round after the first, with the given player already
    /// established as the starter (chain starts empty, no mandated
    /// opening tile). `startingPlayerIndex` is the caller's
    /// responsibility to compute correctly (e.g. via whatever this app's
    /// eventual match-orchestration layer does with the PREVIOUS round's
    /// decidingPlayerIndex) -- this bridge is explicitly round-scoped,
    /// not match-scoped, and doesn't know or care how rounds chain
    /// together. See docs/architecture/BRIDGE_ARCHITECTURE.md's "Explicitly out of
    /// scope" section.
    static func createSubsequentRound(mode: MatchFormat, startingPlayerIndex: Int) -> EngineSession? {
        let h = isolyn.bridge.bridge_session_create_subsequent_round(mode.bridgeMode, Int32(startingPlayerIndex))
        guard h != isolyn.bridge.kInvalidSessionHandle else { return nil }
        return EngineSession(handle: h)
    }

    /// R-22 match-scoped continuation. The bridge decides whether the next
    /// deal is a fresh set's ritual round, an ordinary subsequent round, or
    /// the survivors' carried-points 1v1 -- the caller must not guess. This
    /// is the only factory that can deal the survivor phase correctly.
    static func createNextRound(matchHandle: isolyn.bridge.MatchHandle) -> EngineSession? {
        let h = isolyn.bridge.bridge_match_create_next_round(matchHandle)
        guard h != isolyn.bridge.kInvalidSessionHandle else { return nil }
        return EngineSession(handle: h)
    }

    /// Idempotent: safe to call more than once. `handle` is nilled on
    /// the FIRST call, so the underlying C++ bridge_session_close is
    /// only ever actually invoked once per real session either way, and
    /// every OTHER method on this actor sees a nil handle immediately
    /// after -- no method here can ever race a close from within the
    /// same actor (there's only ever one actor-isolated caller in
    /// flight at a time, that's the whole point).
    func close() {
        guard let h = handle else { return }
        handle = nil
        isolyn.bridge.bridge_session_close(h)
    }

    deinit {
        // Safety net for a session that was never explicitly closed --
        // actor deinits run synchronously and can't await, but
        // bridge_session_close is a plain synchronous C++ call, so
        // calling it directly here is safe. Not the intended normal
        // close path (Swift deinit timing isn't guaranteed to be
        // prompt) -- callers should still call close() explicitly once
        // a session is actually done with.
        if let h = handle {
            isolyn.bridge.bridge_session_close(h)
        }
    }

    // MARK: - Queries

    func snapshot(for playerIndex: Int) throws -> GameSnapshot {
        guard let h = handle else { throw BridgeError.sessionClosed }
        let dto = isolyn.bridge.bridge_get_snapshot(h, Int32(playerIndex))
        return try GameSnapshot.fromDtoOrThrow(dto)
    }

    /// R-17 private look. Read-only and genuinely seat-scoped: the bridge
    /// only returns the pair when THIS seat holds one tile and no other
    /// boneyard tile is drawable. The caller must show it only to that seat.
    func lookAtLockedPair(for playerIndex: Int) throws -> [Tile] {
        guard let h = handle else { throw BridgeError.sessionClosed }
        var dto = isolyn.bridge.bridge_session_private_locked_pair(h, Int32(playerIndex))
        guard dto.status == .Ok else {
            throw BridgeError(status: dto.status, diagnostic: "locked pair unavailable")
        }
        let tiles: [isolyn.bridge.TileDTO] = withTupleAsArray(
            &dto.tiles, capacity: 2, count: Int(dto.count), as: isolyn.bridge.TileDTO.self
        )
        return tiles.map(Tile.init(bridgeDto:))
    }

    // MARK: - Commands
    //
    // Every command below takes the state version the CALLER last
    // observed (from snapshot() or a previous command's newStateVersion)
    // and throws .staleRequest if the session has moved on since --
    // optimistic concurrency control, and the same mechanism that makes
    // an accidental double-submit of the same command a no-op rather
    // than applied twice. See IsolynBridge.hpp rule 6.

    func submitMove(_ move: Move, expecting stateVersion: UInt64) throws -> CommandOutcome {
        guard let h = handle else { throw BridgeError.sessionClosed }
        let dto = isolyn.bridge.bridge_submit_move(h, stateVersion, move.dto)
        return try CommandOutcome.fromDtoOrThrow(dto)
    }

    func voluntaryDraw(expecting stateVersion: UInt64) throws -> CommandOutcome {
        guard let h = handle else { throw BridgeError.sessionClosed }
        let dto = isolyn.bridge.bridge_voluntary_draw(h, stateVersion)
        return try CommandOutcome.fromDtoOrThrow(dto)
    }

    /// Precondition the bridge itself enforces (see IsolynBridge.cpp):
    /// the current player must NOT already have a legal move --
    /// use this only after a snapshot shows legalMoves.isEmpty for the
    /// current player.
    func resolveForcedDraw(expecting stateVersion: UInt64) throws -> CommandOutcome {
        guard let h = handle else { throw BridgeError.sessionClosed }
        let dto = isolyn.bridge.bridge_resolve_forced_draw(h, stateVersion)
        return try CommandOutcome.fromDtoOrThrow(dto)
    }

    /// For the case where resolveForcedDraw exhausted the boneyard
    /// without producing a legal move -- the turn passes with no play
    /// made. May end the round (see CommandOutcome.roundOutcome).
    func endTurnWithNoPlay(expecting stateVersion: UInt64) throws -> CommandOutcome {
        guard let h = handle else { throw BridgeError.sessionClosed }
        let dto = isolyn.bridge.bridge_end_turn_with_no_play(h, stateVersion)
        return try CommandOutcome.fromDtoOrThrow(dto)
    }

    // MARK: - Match recording

    /// Records THIS session's completed round into the given running match.
    /// Deliberately an actor method: it takes the bridge call synchronously in
    /// here so it serializes against every other command/query on the same
    /// session -- the same discipline all session surface follows. The bridge
    /// fails closed (BridgeError.invalidRequest) if this round is still in
    /// progress, was already recorded into this match, or the match has ended.
    func recordRoundInto(matchHandle: isolyn.bridge.MatchHandle) throws -> MatchOutcome {
        guard let h = handle else { throw BridgeError.sessionClosed }
        let dto = isolyn.bridge.bridge_match_record_round(matchHandle, h)
        return try MatchOutcome.fromDtoOrThrow(dto)
    }

    // MARK: - Analysis

    /// Starts a full analysis (snapshot creation + the expensive search)
    /// and returns immediately with a handle to it -- does NOT await the
    /// result itself. `believer` is whose hidden-information perspective
    /// to search from; in ordinary play this should be whichever player
    /// is asking for help with their own upcoming move, i.e. normally
    /// (but not necessarily -- the bridge doesn't enforce this) equal to
    /// the snapshot's currentPlayerIndex.
    ///
    /// Throws .invalidRequest if the session is closed, believer is out
    /// of range, OR the current player does not currently have a legal
    /// move (SearchEngine::chooseBestMove's own precondition -- see
    /// IsolynBridge.cpp's bridge_analysis_snapshot_create comment; the
    /// exact real bug this guards against was found by fuzzing, see
    /// docs/engineering/BRIDGE_TESTING.md). The bridge intentionally doesn't
    /// distinguish these three cases at this call -- if a caller needs
    /// to tell them apart, check a fresh snapshot() first rather than
    /// expecting a more specific error here.
    /// `timeLimitMs` must be positive in production. The bridge returns the
    /// best fully completed depth when the budget expires, with
    /// `completed == false`; it never runs an unbounded search on this path.
    func requestAnalysis(believer playerIndex: Int, maxDepthPlies: Int32,
                         determinizationCount: Int32, timeLimitMs: Int32) throws -> AnalysisTask {
        guard let h = handle else { throw BridgeError.sessionClosed }

        // PHASE 1 -- on this actor, deliberately: reads live session
        // state (see IsolynBridge.hpp). Cheap: one GameState copy, one
        // BeliefState construction.
        let snapshotHandle = isolyn.bridge.bridge_analysis_snapshot_create(h, Int32(playerIndex))
        guard snapshotHandle != isolyn.bridge.kInvalidAnalysisHandle else {
            throw BridgeError.invalidRequest
        }

        // PHASE 2 -- deliberately OFF this actor: this split is the
        // entire reason phase 1/phase 2 exist as separate bridge calls
        // at all. Task.detached (not a plain Task) matters here, not
        // just as a style choice: a plain Task would still run on
        // whatever actor context originated it, which would defeat the
        // point the moment this is ever called from MainActor-isolated
        // UI code.
        let resultTask = Task.detached(priority: .userInitiated) { () -> AnalysisOutcome in
            // Fresh randomness per call, on purpose -- reproducibility
            // only matters for tests, which supply their own fixed seed
            // directly to the C++ side (see
            // Tests/IsolynEngineBridgeTests/SmokeTest.cpp); production
            // analysis has no reason to ever repeat the same search.
            let seed = UInt64.random(in: UInt64.min...UInt64.max)
            let dto = isolyn.bridge.bridge_analysis_run_with_budget(
                snapshotHandle, maxDepthPlies, determinizationCount, seed, timeLimitMs)
            // Called unconditionally, before the possibly-throwing
            // conversion below -- bridge_analysis_run itself cannot
            // throw (C++ exceptions are contained inside the bridge; see
            // IsolynBridge.hpp rule 2), so this always runs exactly
            // once, leak-free, regardless of what fromDtoOrThrow does
            // with the result.
            isolyn.bridge.bridge_analysis_snapshot_destroy(snapshotHandle)
            return try AnalysisOutcome.fromDtoOrThrow(dto)
        }

        return AnalysisTask(snapshotHandle: snapshotHandle, resultTask: resultTask)
    }
}

/// A single in-flight (or already-finished) analysis request.
///
/// LIFECYCLE CONTRACT (FIX-16 / audit F-10): every holder MUST either
/// await `result` or call `cancel()` before dropping this value.
/// Dropping without either lets phase 2 run to completion on its
/// detached task -- wasted CPU plus a live snapshot handle for the
/// whole search duration. Production call sites satisfy this by
/// routing every discard/replacement through GameViewModel's
/// invalidateAnalysis()/shutdown(), and the game board cancels from
/// .onDisappear.
///
/// Holding
/// this rather than a bare Task is what makes cancel() possible --
/// bridge_analysis_request_cancel needs the AnalysisHandle, which a Task
/// alone doesn't carry. Sendable: safe to hand to any thread/actor (e.g.
/// capture in a MainActor-isolated view model to drive a "Cancel"
/// button), since both stored properties are themselves Sendable.
struct AnalysisTask: Sendable {
    fileprivate let snapshotHandle: isolyn.bridge.AnalysisHandle
    private let resultTask: Task<AnalysisOutcome, Error>

    fileprivate init(snapshotHandle: isolyn.bridge.AnalysisHandle, resultTask: Task<AnalysisOutcome, Error>) {
        self.snapshotHandle = snapshotHandle
        self.resultTask = resultTask
    }

    /// Awaits the analysis outcome. If cancel() was called, this still
    /// returns NORMALLY (not a thrown CancellationError) with
    /// `completed == false` on the result -- see
    /// AnalysisOutcome.completed's own doc comment. This only throws for
    /// a genuine bridge/engine failure.
    ///
    /// Deliberately NOT wired to Swift's own Task.isCancelled /
    /// structured-concurrency cancellation -- that mechanism is
    /// cooperative and requires the running closure to periodically
    /// check it, but bridge_analysis_run is one single, synchronous C++
    /// call from Swift's point of view: the closure never gets a chance
    /// to check anything while it's in flight. The ONLY thing that can
    /// actually reach into the C++ search and ask it to stop early is
    /// the cancelRequested atomic flag SearchEngine::chooseBestMove
    /// reads -- which is exactly what cancel() below sets, via
    /// bridge_analysis_request_cancel. Two different cancellation
    /// mechanisms for two different layers; conflating them would make
    /// this LESS clear about which one is actually doing anything.
    var result: AnalysisOutcome {
        get async throws {
            try await resultTask.value
        }
    }

    /// Safe to call from any thread/actor, at any time, including more
    /// than once, including after the analysis has already finished --
    /// see bridge_analysis_request_cancel's own contract. Does NOT stop
    /// the C++ computation any faster than "finish whichever
    /// determinization sample is already in flight" -- not instant, and
    /// does not itself cause `result` to resolve any sooner than that.
    func cancel() {
        isolyn.bridge.bridge_analysis_request_cancel(snapshotHandle)
    }
}
