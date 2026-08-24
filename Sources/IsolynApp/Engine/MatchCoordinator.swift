import SwiftUI
import Observation
import IsolynEngineBridge

/// Owns the running score across rounds of one match -- the Swift-side half
/// of Phase 1's orchestration design. Scoring MATH stays in the tested engine
/// (ScoreSystem / RulesEngine, reached through the bridge's
/// bridge_match_record_round); this type owns only session-lifecycle POLICY:
/// when a round is recorded, who deals the next round, and when the match is
/// over.
///
/// MainActor by annotation: every field it publishes is UI state, and every
/// bridge call it makes is fast (score bookkeeping, never search). Round
/// recording goes THROUGH the finished round's EngineSession actor
/// (recordRoundInto), so it serializes against that session's other work --
/// no new synchronization concepts, just composition of existing ones.
@MainActor
@Observable
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

    /// Set exactly once in init, never mutated. `nonisolated(unsafe)` exists
    /// only so deinit (which is nonisolated under Swift 6 rules) can reach it;
    /// safety holds by construction: the value is immutable, and
    /// bridge_match_close is genuinely idempotent (a table miss), so even an
    /// explicit close() followed by deinit's close is a harmless no-op.
    nonisolated(unsafe) private let matchHandle: isolyn.bridge.MatchHandle
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
    func dealNextRound() throws -> EngineSession? {
        guard !isClosed else { return nil }
        guard let starter = lastNextStarter else { return nil }
        return try EngineSession.createSubsequentRound(mode: mode, startingPlayerIndex: starter)
    }

    var hasBegunRecording: Bool { !scores.isEmpty }
}
