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
    /// Participant scores (players for 1v1/1v1v1, teams for 2v2). Empty until
    /// the first round has been recorded.
    private(set) var scores: [Int] = []

    /// Who opens the current/upcoming round. nil before the first record and
    /// irrelevant for `begin`'s caller-created first-round session (which
    /// applies the mandated opener itself).
    private(set) var lastNextStarter: Int?

    /// Set once any participant crosses the mode's loss threshold.
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

    init(mode: MatchFormat) throws {
        self.mode = mode
        let h = isolyn.bridge.bridge_match_begin(mode.bridgeMode)
        guard h != isolyn.bridge.kInvalidMatchHandle else {
            throw BridgeError.invalidRequest // only reachable on invalid mode or CSPRNG-class failure at begin
        }
        self.matchHandle = h
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
        lastNextStarter = outcome.nextRoundStarterIndex
        matchWinner = outcome.winnerParticipantIndex

        return outcome
    }

    /// Deals the next round from the most recently recorded starter. Chain
    /// starts empty; there is no mandated opening tile past round one (the
    /// engine enforces all of this via dealSubsequentRound).
    /// Non-throwing by proof: the only underlying call returns an optional
    /// rather than throwing, so callers get nil-on-failure with no try-tax.
    func dealNextRound() -> EngineSession? {
        guard !isClosed else { return nil }
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
        matchHandle = isolyn.bridge.bridge_match_begin(mode.bridgeMode)
        scores = []
        lastNextStarter = nil
        matchWinner = nil
        isClosed = false
    }
}
