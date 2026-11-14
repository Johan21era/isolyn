import Foundation
import IsolynEngineBridge

/// Owns the running score across rounds of one match -- the Swift-side half
/// of Phase 1's orchestration design. Scoring MATH stays in the tested engine
/// (ScoreSystem / RulesEngine, reached through the bridge's
/// bridge_match_record_round); this type owns only session-lifecycle POLICY:
/// when a round is recorded, who deals the next round, and when the match is
/// over.
///
/// MainActor by annotation; deliberately NOT @Observable -- views read
/// scores/winner/starter through GameViewModel's published passthroughs, so
/// observability here was dead weight and blocked the nonisolated handle
/// storage Swift 6 requires for deinit-safe teardown. Every bridge call it
/// makes is fast (score bookkeeping, never search). Round recording goes
/// THROUGH the finished round's EngineSession actor (recordRoundInto), so it
/// serializes against that session's other work -- composition, not new
/// synchronization concepts.
@MainActor
final class MatchCoordinator {
    /// Scores for the CURRENT set (players for 1v1/1v1v1, teams for 2v2).
    /// Empty until the first round has been recorded; reset to zero when a
    /// new set is dealt.
    private(set) var scores: [Int] = []

    /// Completed sets per participant.
    private(set) var setWins: [Int] = []

    /// The 1-based set the last recorded round belonged to.
    private(set) var setNumber = 1

    /// The pre-game format: 3 (best-of-5) or 4 (best-of-7).
    private(set) var setsToWin: Int

    /// True when the last recorded round ended its set at 151.
    private(set) var lastSetEnded = false

    /// True when the next round must be dealt as a fresh set, which restarts
    /// the double-six ritual (RULEBOOK R-12).
    private(set) var nextRoundStartsSet = false

    /// The participant who took the last set, when it ended.
    private(set) var setWinner: Int?

    /// Who opens the current/upcoming round. nil before the first record, at
    /// a set boundary (the ritual decides), or after the game ends.
    private(set) var lastNextStarter: Int?

    /// Set once a participant reaches `setsToWin` sets.
    private(set) var matchWinner: Int?

    /// True after close() -- guards double-recording into a dead match handle.
    private(set) var isClosed = false

    /// All mutations happen on @MainActor methods; `nonisolated(unsafe)`
    /// exists only so deinit (nonisolated under Swift 6 rules) can reach the
    /// value for its safety-net close. bridge_match_close is genuinely
    /// idempotent (a table miss), so any close/close/deinit interleaving is
    /// harmless by construction.
    nonisolated(unsafe) private var matchHandle: isolyn.bridge.MatchHandle
    private let mode: MatchFormat

    init(mode: MatchFormat, setsToWin: Int = 3) throws {
        self.mode = mode
        self.setsToWin = setsToWin
        let h = isolyn.bridge.bridge_match_begin_with_format(mode.bridgeMode, Int32(setsToWin))
        guard h != isolyn.bridge.kInvalidMatchHandle else {
            throw BridgeError.invalidRequest // invalid mode/format, or CSPRNG-class failure at begin
        }
        self.matchHandle = h
        self.setWins = Array(repeating: 0, count: mode.participantCount)
    }

    deinit {
        isolyn.bridge.bridge_match_close(matchHandle)
    }

    /// Explicit close -- same idempotency contract as EngineSession.close().
    func close() {
        guard !isClosed else { return }
        isClosed = true
        isolyn.bridge.bridge_match_close(matchHandle)
    }

    /// Records a COMPLETED round into the running score and updates published
    /// state. The session must have reached a real outcome (DominoVictory or
    /// Closed) -- the bridge rejects still-in-progress rounds with
    /// .invalidRequest, duplicate recordings with .invalidRequest as well.
    func recordRound(_ session: EngineSession) async throws -> MatchOutcome {
        guard !isClosed else { throw BridgeError.sessionClosed }
        let outcome = try await session.recordRoundInto(matchHandle: matchHandle)

        scores = outcome.scoresPerParticipant
        setWins = outcome.setWinsPerParticipant
        setNumber = outcome.setNumber
        lastSetEnded = outcome.setEnded
        nextRoundStartsSet = outcome.nextRoundStartsSet
        setWinner = outcome.setWinnerParticipantIndex
        lastNextStarter = outcome.nextRoundStarterIndex >= 0
            ? outcome.nextRoundStarterIndex
            : nil
        matchWinner = outcome.winnerParticipantIndex

        return outcome
    }

    /// Deals the next round. When the previous round ended a set, this deals
    /// a fresh set-opening round (the double-six ritual restarts, R-12) and
    /// resets the visible set scores; otherwise it uses the recorded starter
    /// and leaves the chain empty (no mandated opener past the first hand).
    /// Non-throwing by proof: the underlying calls return an optional rather
    /// than throwing, so callers get nil-on-failure with no try-tax.
    func dealNextRound() -> EngineSession? {
        guard !isClosed else { return nil }
        if nextRoundStartsSet {
            scores = Array(repeating: 0, count: scores.count)
            setNumber += 1
            nextRoundStartsSet = false
            lastSetEnded = false
            setWinner = nil
            return EngineSession.createFirstRound(mode: mode)
        }
        guard let starter = lastNextStarter else { return nil }
        return EngineSession.createSubsequentRound(mode: mode, startingPlayerIndex: starter)
    }

    var hasBegunRecording: Bool { !scores.isEmpty }

    /// Phase 2 seam -- GameViewModel.newMatch() is the only intended caller.
    /// Closes the current bridge-side tracker and begins a fresh one for the
    /// SAME mode: running scores zero out, winner clears. If bridge_match_begin
    /// somehow returned invalid, every later record call fails closed with
    /// SessionClosed -- honest degradation, never fabricated state.
    func reset() {
        if !isClosed {
            isolyn.bridge.bridge_match_close(matchHandle)
        }
        matchHandle = isolyn.bridge.bridge_match_begin_with_format(
            mode.bridgeMode, Int32(setsToWin)
        )
        scores = []
        setWins = Array(repeating: 0, count: mode.participantCount)
        setNumber = 1
        lastSetEnded = false
        nextRoundStartsSet = false
        setWinner = nil
        lastNextStarter = nil
        matchWinner = nil
        isClosed = false
    }
}
