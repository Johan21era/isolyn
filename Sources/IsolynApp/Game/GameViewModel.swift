import Foundation
import Observation
import IsolynEngineBridge

/// Drives the entire game screen: owns the current round's EngineSession and
/// the running MatchCoordinator, projects the latest GameSnapshot into a
/// five-phase state machine, and executes every rules-mandated action
/// (forced draws, pass-turns, round recording) exactly as real play would.
///
/// Single source of UI truth: the last successfully fetched GameSnapshot.
/// Every mutation sends its `expectedStateVersion`, so double-taps fail
/// closed as StaleRequest and are healed by a silent refresh -- optimistic
/// concurrency, inherited straight from the bridge's design.
///
/// Hot-seat model: snapshots are always requested from the CURRENT player's
/// perspective, so the active player's rack is what's on screen --
/// pass-the-device trust, enforced by the same structural hidden-info rules
/// the bridge has enforced since day one.
@MainActor
@Observable
final class GameViewModel {

    // MARK: - Phases

    enum Phase: Equatable {
        /// Initial fetch in flight (or failed setup -- see setupError).
        case loading
        /// A round is live. Turn/draw sub-states derive from the snapshot.
        case playing
        /// Round reached DominoVictory or Closed; reveal overlay showing.
        case roundOver
        /// MatchCoordinator reports a participant crossed the loss threshold.
        case matchOver
    }

    // MARK: - Published state

    private(set) var phase: Phase = .loading
    private(set) var snapshot: GameSnapshot?
    let mode: MatchFormat

    /// Scores BEFORE vs AFTER the most recent recording -- powers the
    /// "+N points" animation on the reveal overlay. Empty until first record.
    private(set) var scoreDeltas: [Int] = []

    /// Set when construction could not produce a session/coordinator pair.
    private(set) var setupError: String?

    /// Last BridgeError that wasn't stale-request-healed -- surfaced as alert.
    private(set) var alertError: BridgeError?

    // MARK: - Analysis drawer state

    private(set) var analysisRunning = false
    private(set) var analysisOutcome: AnalysisOutcome?
    /// True after a cancelled/zero-sample analysis, so the drawer says "no
    /// real analysis happened" instead of displaying a bogus recommendation
    /// (the samplesCompleted == 0 honesty contract, enforced at this layer too).
    private(set) var analysisWasCancelled = false
    private var analysisTask: AnalysisTask?

    // MARK: - Core objects

    private(set) var session: EngineSession?
    private let match: MatchCoordinator?
    /// Sessions whose rounds were already recorded -- local guard mirroring
    /// the bridge's own duplicate-record rejection, for clean UX. Actors are
    /// reference types, so identity is a sufficient key; no bridge surface
    /// had to widen for this.
    private var recordedSessions: Set<ObjectIdentifier> = []
    /// Stable across refreshes: whose turn the board believes it is.
    private var knownCurrentPlayerIndex = 0
    /// The outcome captured when we transitioned into .roundOver.
    private(set) var finishedOutcome: RoundOutcome = .inProgress

    // MARK: - Init / teardown

    init(mode: MatchFormat) {
        self.mode = mode
        do {
            let coordinator = try MatchCoordinator(mode: mode)
            guard let firstRound = EngineSession.createFirstRound(mode: mode) else {
                throw BridgeError.engineFailure(diagnostic: "initial deal failed")
            }
            self.match = coordinator
            self.session = firstRound
        } catch {
            // Coordinator creation failing is near-impossible (invalid mode /
            // OS entropy loss), but the type system deserves honesty over a
            // force-unwrap: everything guards on the optional instead.
            self.match = nil
            self.setupError = "Could not start the match: \(error)"
        }
    }

    /// Release-only teardown. Children own their own bridge handles and
    /// close them in their OWN deinits (EngineSession's actor deinit calls
    /// bridge_session_close; MatchCoordinator likewise) -- so dropping the
    /// references here is sufficient, and avoids awaiting an actor method
    /// from synchronous teardown contexts like test defer blocks.
    func shutdown() {
        analysisTask?.cancel()
        session = nil
        match?.close()
    }

    // MARK: - Refresh

    /// Pulls a fresh snapshot from the CURRENT player's perspective and
    /// re-derives phase. Runs the rules-mandated forced-draw automatically,
    /// exactly as MatchController would headlessly. Bounded: a boneyard can
    /// only feed ~12 forced draws per turn in the worst legal game.
    func refresh() async {
        await refresh(forcedDrawAttempts: 0)
    }

    private func refresh(forcedDrawAttempts: Int) async {
        guard setupError == nil, let session, let match else { return }
        do {
            var snap = try await session.snapshot(for: knownCurrentPlayerIndex)
            if snap.currentPlayerIndex != snap.requestingPlayerIndex {
                // Fresh-round pivot: the first fetch seeds from player 0, but
                // dealFirstRound already advanced the turn past the opener.
                // Re-request from the TRUE current seat so the board always
                // shows the acting player's rack (hot-seat contract).
                knownCurrentPlayerIndex = snap.currentPlayerIndex
                snap = try await session.snapshot(for: knownCurrentPlayerIndex)
            }
            snapshot = snap
            knownCurrentPlayerIndex = snap.currentPlayerIndex

            if snap.roundOutcome != .inProgress {
                finishedOutcome = snap.roundOutcome
                phase = .roundOver
                await recordRoundIfFresh(session)
                return
            }
            if match.matchWinner != nil { phase = .matchOver; return }

            // Post-pivot invariant: the displayed snapshot IS the acting
            // player's view.
            assert(snap.currentPlayerIndex == snap.requestingPlayerIndex)

            if snap.legalMoves.isEmpty {
                if snap.boneyardDrawableCount > 0, forcedDrawAttempts < 32 {
                    _ = try await session.resolveForcedDraw(expecting: snap.stateVersion)
                    await refresh(forcedDrawAttempts: forcedDrawAttempts + 1)
                    return
                } else if snap.boneyardDrawableCount == 0 {
                    phase = .playing   // blocked + dry yard: pass button appears
                    return
                }
            }

            phase = .playing
        } catch let error as BridgeError {
            if case .staleRequest = error {
                await refresh(forcedDrawAttempts: forcedDrawAttempts)
                return
            }
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    // MARK: - Derived helpers (views read these, never raw digging)

    var isMyTurn: Bool {
        guard let s = snapshot, s.roundOutcome == .inProgress else { return false }
        return s.currentPlayerIndex == s.requestingPlayerIndex
    }

    var canPlayTiles: Bool {
        isMyTurn && !(snapshot?.legalMoves.isEmpty ?? true)
    }

    var mustPass: Bool {
        guard let s = snapshot, isMyTurn else { return false }
        return s.legalMoves.isEmpty && s.boneyardDrawableCount == 0
    }

    var canVoluntaryDraw: Bool {
        guard let s = snapshot, isMyTurn, s.roundOutcome == .inProgress else { return false }
        return s.boneyardDrawableCount > 0
    }

    var legalMoveSet: Set<Move> { Set(snapshot?.legalMoves ?? []) }

    // MARK: Overlay passthroughs (read-only views of coordinator state)

    var participantScores: [Int] { match?.scores ?? [] }
    var matchWinnerParticipant: Int? { match?.matchWinner }
    var nextStarterForOverlay: Int? { match?.lastNextStarter }

    /// Clears a surfaced bridge error once its alert has been shown.
    func dismissAlert() {
        alertError = nil
        if setupError != nil { setupError = nil }
    }

    /// Opponent rack counts for the sidebar, excluding the requesting seat.
    var opponentCounts: [(player: Int, tiles: Int)] {
        guard let s = snapshot else { return [] }
        return (0..<s.playerCount).compactMap { p in
            p == s.requestingPlayerIndex ? nil : (p, s.otherHandSizes[p])
        }
    }

    // MARK: - Actions

    func play(_ move: Move) async {
        guard let session, let s = snapshot, s.roundOutcome == .inProgress else { return }
        do {
            _ = try await session.submitMove(move, expecting: s.stateVersion)
            invalidateAnalysis()
            await refresh()
        } catch let error as BridgeError {
            if case .staleRequest = error { await refresh(); return }
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    /// Voluntary draw -- a real rules action (STRATEGY_NOTES treats proactive
    /// drawing as core strategy); the UI offers it, never auto-decides it.
    func voluntaryDraw() async {
        guard let session, let s = snapshot, canVoluntaryDraw else { return }
        do {
            _ = try await session.voluntaryDraw(expecting: s.stateVersion)
            await refresh()
        } catch let error as BridgeError {
            if case .staleRequest = error { await refresh(); return }
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    /// Only ever offered when blocked AND the yard is dry -- the bridge
    /// enforces the identical precondition underneath us.
    func passTurn() async {
        guard let session, let s = snapshot, mustPass else { return }
        do {
            _ = try await session.endTurnWithNoPlay(expecting: s.stateVersion)
            await refresh()
        } catch let error as BridgeError {
            if case .staleRequest = error { await refresh(); return }
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    // MARK: - Round lifecycle

    private func recordRoundIfFresh(_ session: EngineSession) async {
        guard let match else { return }
        let sessionId = ObjectIdentifier(session)
        guard !recordedSessions.contains(sessionId) else { return }
        do {
            let before = match.scores
            let outcome = try await match.recordRound(session)
            recordedSessions.insert(sessionId)

            var deltas: [Int] = []
            for i in 0..<max(outcome.scoresPerParticipant.count, before.count) {
                let b = i < before.count ? before[i] : 0
                let a = i < outcome.scoresPerParticipant.count ? outcome.scoresPerParticipant[i] : 0
                deltas.append(a - b)
            }
            scoreDeltas = deltas
            if match.matchWinner != nil { phase = .matchOver }
        } catch let error as BridgeError {
            // A duplicate-record race loses harmlessly here (the bridge
            // rejected it); anything real surfaces.
            if case .invalidRequest = error { return }
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    /// Deals the NEXT round from the recorded starter (empty chain, free
    /// choice opening). Returns false when the match is over instead.
    @discardableResult
    func dealNextRound() async -> Bool {
        guard let match else { return false }
        guard match.matchWinner == nil else { phase = .matchOver; return false }
        guard let next = match.dealNextRound() else {
            alertError = .bridgeFailure(diagnostic: "could not deal the next round")
            return false
        }
        if let oldSession = session { await oldSession.close() }
        session = next
        invalidateAnalysis()
        phase = .loading
        await refresh()
        return true
    }

    /// Fresh match: same mode, brand-new score tracker, mandated-opener deal.
    func newMatch() async {
        guard let match else { return }
        if let oldSession = session { await oldSession.close() }
        session = nil
        match.reset()
        recordedSessions.removeAll()
        scoreDeltas = []
        invalidateAnalysis()
        do {
            guard let firstRound = EngineSession.createFirstRound(mode: mode) else {
                throw BridgeError.engineFailure(diagnostic: "fresh deal failed")
            }
            session = firstRound
            knownCurrentPlayerIndex = 0
            phase = .loading
            await refresh()
        } catch {
            setupError = "Could not start a new match: \(error)"
        }
    }

    // MARK: - Analysis

    /// Starts (or cancels) a full two-phase search from the given believer's
    /// perspective. Defaults tuned to the engine's documented sweet spot.
    func toggleAnalysis(believer playerIndex: Int) async {
        if analysisRunning { cancelAnalysis(); return }
        guard let session else { return }
        do {
            let task = try await session.requestAnalysis(
                believer: playerIndex,
                maxDepthPlies: 4,
                determinizationCount: 20
            )
            analysisTask = task
            analysisRunning = true
            analysisWasCancelled = false
            analysisOutcome = nil

            Task { [weak self] in
                defer { Task { await self?.finishAnalysisRun() } }
                do {
                    let outcome = try await task.result
                    guard let self else { return }
                    if outcome.samplesCompleted == 0 {
                        self.analysisWasCancelled = true   // honesty contract
                    } else {
                        self.analysisOutcome = outcome
                    }
                } catch {
                    guard let self else { return }
                    self.alertError = (error as? BridgeError)
                        ?? .bridgeFailure(diagnostic: String(describing: error))
                }
            }
        } catch let error as BridgeError {
            // Most legitimate failure: current player blocked (needs a forced
            // draw first) -- same precondition real play satisfies.
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    private func finishAnalysisRun() {
        analysisRunning = false
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
    }

    /// Single funnel for discarding analysis state (FIX-16 / audit
    /// F-10). Every path that replaces, finishes, or abandons an
    /// AnalysisTask routes through here -- play(), dealNextRound(),
    /// newMatch(), shutdown() -- which is what guarantees no task is
    /// ever dropped without cancel().
    private func invalidateAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisOutcome = nil
        analysisRunning = false
        analysisWasCancelled = false
    }
}
