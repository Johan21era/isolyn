import XCTest
@testable import IsolynApp
import IsolynEngineBridge

/// Drives a real 1v1v1 set to its end through `MatchCoordinator` and pins the
/// values `RoundEndOverlay` reads from it. The overlay itself is a SwiftUI view
/// and cannot be rendered in a unit test, but every string it shows comes from
/// these coordinator properties:
///
///   "Set N to Player X"  <- setNumber, setWinner
///   scores / set-win row <- scores, setWins
///   "Deal next set"      <- lastSetEnded, nextRoundStartsSet
///
/// There is deliberately nothing here about an eliminated seat, because the app
/// no longer has one: R-22 makes 1v1v1 a straight race to 151.
@MainActor
final class MatchSetEndTests: XCTestCase {

    /// Plays the current round to completion using the first legal move, with
    /// the same session calls the game screen makes (submit a legal move, take
    /// a forced draw, pass when nothing is playable).
    private func playRound(_ session: EngineSession) async throws {
        for _ in 0..<2_000 {
            let view = try await session.snapshot(for: 0)
            if view.roundOutcome != .inProgress { return }

            let snap = try await session.snapshot(for: view.currentPlayerIndex)
            if snap.roundOutcome != .inProgress { return }

            do {
                if let move = snap.legalMoves.first {
                    _ = try await session.submitMove(move, expecting: snap.stateVersion)
                } else if snap.boneyardDrawableCount > 0 {
                    _ = try await session.resolveForcedDraw(expecting: snap.stateVersion)
                } else {
                    _ = try await session.endTurnWithNoPlay(expecting: snap.stateVersion)
                }
            } catch BridgeError.staleRequest {
                continue // another call moved the state on; re-read and retry
            }
        }
        XCTFail("the round did not finish within 2000 operations")
    }

    func test_one_v_one_v_one_set_end_reports_the_winner_and_the_scores() async throws {
        let match = try MatchCoordinator(mode: .oneVOneVOne)
        defer { match.close() }

        guard var session = EngineSession.createFirstRound(mode: .oneVOneVOne) else {
            return XCTFail("the first 1v1v1 round could not be dealt")
        }

        var rounds = 0
        while !match.lastSetEnded && rounds < 400 {
            try await playRound(session)
            _ = try await match.recordRound(session)
            await session.close()
            rounds += 1
            if match.lastSetEnded { break }
            guard let next = match.dealNextRound() else {
                return XCTFail("the match stopped dealing with no set winner")
            }
            session = next
        }
        await session.close()

        XCTAssertTrue(match.lastSetEnded, "a 1v1v1 set must reach its end")

        guard let winner = match.setWinner else {
            return XCTFail("the overlay has no set winner to name")
        }

        // "Set N to Player X." -- the set that just finished, not the next one.
        XCTAssertEqual(match.setNumber, 1, "the overlay names the set that just ended")
        XCTAssertTrue((0..<3).contains(winner), "the winner is one of the three seats")

        // The score strip keeps every seat and shows the final, pre-reset totals.
        XCTAssertEqual(match.scores.count, 3,
                       "all three seats stay on the strip: nobody is eliminated")
        XCTAssertEqual(match.scores.max(), match.scores[winner],
                       "the set goes to the highest score, not the lowest")
        XCTAssertGreaterThanOrEqual(match.scores[winner], 151,
                                    "the set winner is the participant who reached 151")

        // The set-win row and the action button.
        XCTAssertEqual(match.setWins[winner], 1,
                       "the set win is credited exactly once, to that participant")
        XCTAssertEqual(match.setWins.reduce(0, +), 1, "no other participant is credited")
        XCTAssertTrue(match.nextRoundStartsSet, "the overlay offers 'Deal next set'")
        XCTAssertNil(match.matchWinner, "one set cannot end a best-of-five match")

        print("1v1v1 set end after \(rounds) rounds: scores \(match.scores), winner \(winner)")
    }
}
