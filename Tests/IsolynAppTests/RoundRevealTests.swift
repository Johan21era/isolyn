import XCTest
@testable import IsolynApp

@MainActor
final class RoundRevealTests: XCTestCase {
    func test_realRound_revealsActualHands_onlyAtTheEnd() async throws {
        guard let session = EngineSession.createFirstRound(mode: .oneVOne) else {
            return XCTFail("could not create the first round")
        }

        do {
            let opening = try await session.snapshot(for: 0)
            XCTAssertTrue(opening.revealedHands.allSatisfy { $0.isEmpty },
                          "live play must not leak opponent tile identities")
            XCTAssertEqual(opening.boneyardDrawableCount, 12,
                           "1v1 leaves 14 tiles after the deal; the final two are locked, leaving 12 drawable")
            XCTAssertTrue(opening.boneyardLockedTiles.isEmpty,
                          "the locked pair stays identity-hidden while drawable tiles remain")

            var final: GameSnapshot?
            for _ in 0..<500 {
                let current = try await session.snapshot(for: 0)
                if current.roundOutcome != .inProgress {
                    final = current
                    break
                }

                let seat = current.currentPlayerIndex
                let view = try await session.snapshot(for: seat)
                if view.legalMoves.isEmpty {
                    if view.boneyardDrawableCount > 0 {
                        _ = try await session.resolveForcedDraw(expecting: view.stateVersion)
                    } else {
                        _ = try await session.endTurnWithNoPlay(expecting: view.stateVersion)
                    }
                } else if let move = view.legalMoves.first {
                    _ = try await session.submitMove(move, expecting: view.stateVersion)
                }
            }

            guard let final else {
                await session.close()
                return XCTFail("round did not reach a terminal outcome")
            }

            XCTAssertFalse(final.revealedHands.isEmpty)
            XCTAssertEqual(final.revealedHands[0], final.ownHand)
            XCTAssertEqual(final.revealedHands[1].count, final.otherHandSizes[1])
            for player in 0..<2 {
                let total = Tile.handPoints(final.revealedHands[player])
                XCTAssertEqual(total, final.finalHandValues[player],
                               "revealed tiles must sum to the round-end hand value")
            }
        } catch {
            await session.close()
            throw error
        }

        await session.close()
    }
}
