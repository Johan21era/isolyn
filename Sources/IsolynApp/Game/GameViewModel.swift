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

    /// One boneyard draw worth animating at the table. Human draws carry the
    /// actual new tile(s); computer draws carry the seat and count only -- the
    /// opponent's identities stay hidden until the round-end reveal.
    struct DrawEvent: Identifiable, Equatable {
        let id: UUID
        let seat: Int
        let tiles: [Tile]
        let count: Int
    }

    // MARK: - Published state

    private(set) var phase: Phase = .loading
    private(set) var snapshot: GameSnapshot?
    let mode: MatchFormat
    let opponent: OpponentMode
    let aiLevel: AILevel
    /// The pre-game format choice: first to 3 sets (best-of-5) or first to 4
    /// (best-of-7), frozen for the life of this game.
    let setsToWin: Int
    /// R-06: the 1v1 race target (101 or 151), frozen for the match.
    let targetScore: Int

    /// Most recent boneyard draw. Kept as the latest-event convenience that
    /// tests and simple callers already use.
    private(set) var drawEvent: DrawEvent?
    /// Every draw still worth animating. Consecutive forced draws would
    /// otherwise cancel each other's flight; keeping a short overlapping
    /// window lets each one leave the pile visibly.
    private(set) var drawEvents: [DrawEvent] = []

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

    /// R-17 private pair, when the current seat is entitled to look. This is
    /// deliberately UI-local: it is never written into a snapshot or sent to
    /// the other seat.
    private(set) var privatePair: [Tile] = []

    // MARK: - Computer opponent state

    /// True while the opponent's turn is being searched or played. The board
    /// remains visible, but every human control is disabled.
    private(set) var aiThinking = false
    private var aiTask: AnalysisTask?
    private var aiTurnTask: Task<Void, Never>?

    // MARK: - Core objects

    private(set) var session: EngineSession?
    private let match: MatchCoordinator?
    /// Sessions whose rounds were already recorded -- local guard mirroring
    /// the bridge's own duplicate-record rejection, for clean UX. Actors are
    /// reference types, so identity is a sufficient key; no bridge surface
    /// had to widen for this.
    private var recordedSessions: Set<ObjectIdentifier> = []
    @ObservationIgnored private var drawEventClearTasks: [UUID: Task<Void, Never>] = [:]
    /// Stable across refreshes: whose turn the board believes it is.
    private var knownCurrentPlayerIndex = 0
    /// The outcome captured when we transitioned into .roundOver.
    private(set) var finishedOutcome: RoundOutcome = .inProgress

    // MARK: - Init / teardown

    init(mode: MatchFormat, opponent: OpponentMode = .human, aiLevel: AILevel = .club,
         setsToWin: Int = 3, targetScore: Int = 151) {
        self.mode = mode
        self.opponent = opponent
        self.aiLevel = aiLevel
        self.setsToWin = setsToWin
        self.targetScore = targetScore
        do {
            let coordinator = try MatchCoordinator(
                mode: mode, setsToWin: setsToWin, targetScore: targetScore
            )
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
        cancelAITurn()
        clearDrawEvents()
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
        guard setupError == nil, let session, let match else { return }
        do {
            // In AI mode the board is always requested from the human seat.
            // Showing the computer's own hand while it thinks would leak
            // hidden information; hot-seat still follows the current seat.
            let requestedSeat = opponent == .computer ? 0 : knownCurrentPlayerIndex
            var snap = try await session.snapshot(for: requestedSeat)
            if opponent == .human && snap.currentPlayerIndex != snap.requestingPlayerIndex {
                // Fresh-round pivot: the first fetch seeds from player 0, but
                // dealFirstRound already advanced the turn past the opener.
                // Re-request from the TRUE current seat so the board always
                // shows the acting player's rack (hot-seat contract).
                knownCurrentPlayerIndex = snap.currentPlayerIndex
                snap = try await session.snapshot(for: knownCurrentPlayerIndex)
            }
            let previousSnapshot = snapshot
            snapshot = snap
            knownCurrentPlayerIndex = snap.currentPlayerIndex
            if !canLookAtLockedPair { privatePair = [] }
            publishDrawIfNeeded(from: previousSnapshot, to: snap)
            discardStaleAnalysis()

            if snap.roundOutcome != .inProgress {
                clearDrawEvents()
                finishedOutcome = snap.roundOutcome
                phase = .roundOver
                await recordRoundIfFresh(session)
                return
            }
            if match.matchWinner != nil { phase = .matchOver; return }

            // Post-pivot invariant for hot-seat: the displayed snapshot IS
            // the acting player's view. AI mode intentionally shows the human
            // seat while the computer acts.
            if opponent == .human {
                assert(snap.currentPlayerIndex == snap.requestingPlayerIndex)
            }

            // A blocked player is deliberately NOT drawn for automatically.
            // Drawing is mandatory, not automatic: when the yard holds tiles
            // the Draw control is already enabled, and the player spends the
            // draws themselves, one tile at a time. Doing it for them removed
            // agency and pre-empted the very button that exists for it.
            phase = .playing
            scheduleAITurnIfNeeded()
        } catch let error as BridgeError {
            if case .staleRequest = error {
                await refresh()
                return
            }
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    // MARK: - Derived helpers (views read these, never raw digging)

    /// Detects only the requesting player's own draw. Hidden opponent hand
    /// identities never cross the bridge, and an opponent's draw can be
    /// immediately followed by a play (same final hand size), so computer
    /// draws are published explicitly from `performAITurn` instead.
    private func publishDrawIfNeeded(from previous: GameSnapshot?, to next: GameSnapshot) {
        guard let previous,
              previous.requestingPlayerIndex == next.requestingPlayerIndex,
              previous.roundOutcome == .inProgress,
              next.roundOutcome == .inProgress,
              next.stateVersion > previous.stateVersion else { return }

        let boneyardDrop = previous.boneyardDrawableCount - next.boneyardDrawableCount
        guard boneyardDrop > 0, next.ownHand.count > previous.ownHand.count else { return }

        let oldTiles = Set(previous.ownHand)
        let newTiles = next.ownHand.filter { !oldTiles.contains($0) }
        guard !newTiles.isEmpty else { return }
        publishDraw(
            seat: next.requestingPlayerIndex,
            tiles: newTiles,
            count: max(boneyardDrop, newTiles.count)
        )
    }

    private func publishDraw(seat: Int, tiles: [Tile], count: Int) {
        let event = DrawEvent(id: UUID(), seat: seat, tiles: tiles, count: max(1, count))
        drawEvent = event
        drawEvents.append(event)

        drawEventClearTasks[event.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.drawEvents.removeAll { $0.id == event.id }
            if self.drawEvent?.id == event.id { self.drawEvent = nil }
            self.drawEventClearTasks[event.id] = nil
        }
    }

    private func clearDrawEvents() {
        for task in drawEventClearTasks.values { task.cancel() }
        drawEventClearTasks.removeAll()
        drawEvents.removeAll()
        drawEvent = nil
    }

    /// A short beat for the opponent's visible turn and for chained forced
    /// draws. The engine stays synchronous; only the presentation waits.
    private func pace(_ nanoseconds: UInt64) async {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    var isMyTurn: Bool {
        guard let s = snapshot, s.roundOutcome == .inProgress else { return false }
        return s.currentPlayerIndex == s.requestingPlayerIndex
    }

    var isComputerTurn: Bool {
        guard let s = snapshot, s.roundOutcome == .inProgress else { return false }
        return isComputerSeat(s.currentPlayerIndex)
    }

    func isComputerSeat(_ seat: Int) -> Bool {
        mode.isComputerSeat(seat, for: opponent)
    }

    var turnLabel: String {
        guard let s = snapshot, s.roundOutcome == .inProgress else { return "Round complete" }
        if isComputerSeat(s.currentPlayerIndex) { return "Computer's turn" }
        if mode == .twoVTwo { return "Team \(s.currentPlayerIndex % 2 + 1)'s turn" }
        return "Player \(s.currentPlayerIndex + 1)'s turn"
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
        // The opener faces an empty chain and always holds a legal lead, so the
        // rules require a play. Offering a draw there was a live rules bug.
        return s.boneyardDrawableCount > 0 && !s.chain.isEmpty
    }

    /// R-17: a 1v1 player holding exactly one tile may inspect the locked
    /// pair once no other boneyard tile is drawable. The bridge re-checks
    /// both conditions and returns explicit refusal otherwise.
    var canLookAtLockedPair: Bool {
        guard let s = snapshot, s.roundOutcome == .inProgress else { return false }
        guard s.boneyardDrawableCount == 0 && s.ownHand.count == 1 else { return false }
        if s.playerCount == 2 { return true }
        // R-22 survivor phase: three seats in the state, but exactly one
        // other live hand. That is a 1v1 and R-17 applies.
        let otherLiveHands = s.otherHandSizes.enumerated().filter {
            $0.offset != s.requestingPlayerIndex && $0.element > 0
        }.count
        return s.playerCount == 3 && otherLiveHands == 1
    }

    var legalMoveSet: Set<Move> { Set(snapshot?.legalMoves ?? []) }

    // MARK: Overlay passthroughs (read-only views of coordinator state)

    var participantScores: [Int] { match?.scores ?? [] }
    var setWins: [Int] { match?.setWins ?? [] }
    var setNumber: Int { match?.setNumber ?? 1 }
    var matchSetsToWin: Int { match?.setsToWin ?? setsToWin }
    var lastSetEnded: Bool { match?.lastSetEnded ?? false }
    var setWinnerForOverlay: Int? { match?.setWinner }
    var nextRoundStartsSet: Bool { match?.nextRoundStartsSet ?? false }
    var matchWinnerParticipant: Int? { match?.matchWinner }
    var nextStarterForOverlay: Int? { match?.lastNextStarter }
    var eliminatedPerParticipant: [Bool] { match?.eliminatedPerParticipant ?? [] }
    var lastEliminatedParticipant: Int? { match?.lastEliminatedParticipant }

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
        guard isMyTurn, let session, let s = snapshot, s.roundOutcome == .inProgress else { return }
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
    /// R-17 private look. Read-only: no state version, no turn consumed.
    func lookAtLockedPair() async {
        guard let session, let s = snapshot, canLookAtLockedPair else { return }
        do {
            privatePair = try await session.lookAtLockedPair(for: s.requestingPlayerIndex)
        } catch let error as BridgeError {
            alertError = error
        } catch {
            alertError = .bridgeFailure(diagnostic: String(describing: error))
        }
    }

    func dismissPrivatePair() { privatePair = [] }

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

    /// Deals the NEXT round -- or, after a set ended, the next set's ritual
    /// opening (MatchCoordinator chooses which). Returns false when the match
    /// is over instead.
    @discardableResult
    func dealNextRound() async -> Bool {
        guard let match else { return false }
        guard match.matchWinner == nil else { phase = .matchOver; return false }
        guard let next = match.dealNextRound() else {
            alertError = .bridgeFailure(diagnostic: "could not deal the next round")
            return false
        }
        cancelAITurn()
        if let oldSession = session { await oldSession.close() }
        session = next
        invalidateAnalysis()
        clearDrawEvents()
        phase = .loading
        await refresh()
        return true
    }

    /// Fresh match: same mode, brand-new score tracker, mandated-opener deal.
    func newMatch() async {
        guard let match else { return }
        cancelAITurn()
        if let oldSession = session { await oldSession.close() }
        session = nil
        match.reset()
        recordedSessions.removeAll()
        scoreDeltas = []
        clearDrawEvents()
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

    /// Wall-clock caps for the two production search paths. A deep request
    /// must never leave the player waiting without a bound; a truncated run
    /// is reported through AnalysisOutcome.completed == false.
    private enum SearchBudget {
        static let coachMs: Int32 = 1_500
    }

    /// Starts (or cancels) a full two-phase search from the given believer's
    /// perspective. Defaults tuned to the engine's documented sweet spot.
    func toggleAnalysis(believer playerIndex: Int) async {
        if analysisRunning { cancelAnalysis(); return }
        guard isMyTurn, let session else { return }
        do {
            let task = try await session.requestAnalysis(
                believer: playerIndex,
                maxDepthPlies: 4,
                determinizationCount: 20,
                timeLimitMs: SearchBudget.coachMs
            )
            analysisTask = task
            analysisRunning = true
            analysisWasCancelled = false
            analysisOutcome = nil

            Task { [weak self] in
                defer { Task { self?.finishAnalysisRun() } }   // sync; no await needed
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
    /// A suggestion belongs to ONE position. Once the board has moved on it is
    /// not a weaker hint, it is a wrong one -- it names a tile that may no
    /// longer be legal (a live test read a stale "suggests 6-2" as a legal
    /// move and lost the turn). Drop it whenever the analysed version is gone.
    private func discardStaleAnalysis() {
        guard let outcome = analysisOutcome, let snap = snapshot else { return }
        let stillCurrent = outcome.stateVersionAnalyzed == snap.stateVersion
        let stillLegal = outcome.isDraw || snap.legalMoves.contains(outcome.recommendedMove)
        if !stillCurrent || !stillLegal { analysisOutcome = nil }
    }

    private func invalidateAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisOutcome = nil
        analysisRunning = false
        analysisWasCancelled = false
    }

    // MARK: - Computer opponent

    private func scheduleAITurnIfNeeded() {
        guard opponent == .computer,
              aiTurnTask == nil,
              !aiThinking,
              phase == .playing,
              let snap = snapshot,
              snap.roundOutcome == .inProgress,
              isComputerSeat(snap.currentPlayerIndex) else { return }

        aiTurnTask = Task { [weak self] in
            guard let self else { return }
            await self.performAITurn()
            self.aiTurnTask = nil
            // A three-way match can hand the turn from one computer seat to
            // another. The refresh inside performAITurn cannot schedule that
            // next turn while THIS task is still stored, so re-check here.
            self.scheduleAITurnIfNeeded()
        }
    }

    private func performAITurn() async {
        guard let session, let visible = snapshot,
              visible.roundOutcome == .inProgress,
              isComputerSeat(visible.currentPlayerIndex) else { return }

        aiThinking = true
        defer {
            aiThinking = false
            aiTask = nil
        }

        // Give the acting seat a visible beat before the engine result lands.
        await pace(450_000_000)
        guard !Task.isCancelled else { return }

        let seat = visible.currentPlayerIndex
        let profile = AIProfile(level: aiLevel)

        // Forced draws are rules actions, not strategic choices. Resolve them
        // one at a time from the computer's own snapshot until it can play or
        // has to pass, exactly as a human turn would.
        for _ in 0..<64 {
            if Task.isCancelled { return }

            do {
                let view = try await session.snapshot(for: seat)
                guard view.roundOutcome == .inProgress else {
                    await refresh()
                    return
                }
                guard view.currentPlayerIndex == seat else {
                    await refresh()
                    return
                }

                if view.legalMoves.isEmpty {
                    if view.boneyardDrawableCount > 0 {
                        await pace(200_000_000)
                        guard !Task.isCancelled else { return }
                        _ = try await session.resolveForcedDraw(expecting: view.stateVersion)
                        // The human-facing snapshot intentionally hides the
                        // computer's hand, but it still carries the shared
                        // boneyard count. Refresh before publishing the
                        // flight so the pile shrinks on the same beat.
                        await refresh()
                        publishDraw(seat: seat, tiles: [], count: 1)
                        await pace(300_000_000)
                    } else {
                        await pace(260_000_000)
                        _ = try await session.endTurnWithNoPlay(expecting: view.stateVersion)
                    }
                    continue
                }

                let task = try await session.requestAnalysis(
                    believer: seat,
                    maxDepthPlies: profile.maxDepthPlies,
                    determinizationCount: profile.determinizationCount,
                    timeLimitMs: aiLevel.thinkingTimeMs
                )
                aiTask = task
                let outcome = try await task.result
                aiTask = nil

                if Task.isCancelled { return }

                // A voluntary draw is a real action, not a placement. The
                // engine reports it separately because a draw does not consume
                // the turn: submitting the placeholder move it leaves in
                // `recommendedMove` would play a different game than the one it
                // searched.
                if outcome.samplesCompleted > 0, outcome.isDraw {
                    await pace(240_000_000)
                    guard !Task.isCancelled else { return }
                    _ = try await session.voluntaryDraw(expecting: view.stateVersion)
                    // The drawn tile is the computer's hidden card; only the
                    // fact and count of the draw are published.
                    publishDraw(seat: seat, tiles: [], count: 1)
                    await refresh()
                    return
                }

                // The analysis contract says zero completed samples means no
                // real recommendation. Fall back to a genuinely legal move
                // rather than displaying or submitting fabricated analysis.
                let move: Move
                if outcome.samplesCompleted > 0,
                   view.legalMoves.contains(outcome.recommendedMove) {
                    move = outcome.recommendedMove
                } else if let fallback = view.legalMoves.randomElement() {
                    move = fallback
                } else {
                    await refresh()
                    return
                }

                await pace(240_000_000)
                guard !Task.isCancelled else { return }
                _ = try await session.submitMove(move, expecting: view.stateVersion)
                await pace(360_000_000)
                guard !Task.isCancelled else { return }
                await refresh()
                return
            } catch let error as BridgeError {
                if case .staleRequest = error { continue }
                if case .invalidRequest = error { continue }
                alertError = error
                return
            } catch {
                alertError = .bridgeFailure(diagnostic: String(describing: error))
                return
            }
        }

        alertError = .bridgeFailure(diagnostic: "computer could not resolve its turn")
    }

    private func cancelAITurn() {
        aiTurnTask?.cancel()
        aiTurnTask = nil
        aiTask?.cancel()
        aiTask = nil
        aiThinking = false
    }
}
