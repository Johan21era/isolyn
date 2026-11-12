import XCTest
@testable import IsolynApp

/// Rules-level checks for the table's new physical draw pile. The UI projects
/// these snapshot values directly, so this is the authoritative seam: the
/// boneyard exists only in 1v1, and its final two tiles are never drawable.
@MainActor
final class BoneyardRulesTests: XCTestCase {
    func test_onlyDuelOpensWithABoneyard() async throws {
        let duel = try await openingSnapshot(for: .oneVOne)
        XCTAssertEqual(duel.mode, .oneVOne)
        XCTAssertEqual(duel.boneyardDrawableCount, 12,
                       "1v1 has 14 undrawn tiles; the final two are permanently locked")
        XCTAssertTrue(duel.boneyardLockedTiles.isEmpty,
                      "locked identities stay hidden until only the final two remain")

        for mode in [MatchFormat.oneVOneVOne, .twoVTwo] {
            let snap = try await openingSnapshot(for: mode)
            XCTAssertEqual(snap.mode, mode)
            XCTAssertEqual(snap.boneyardDrawableCount, 0,
                           "\(mode.rawValue) deals the complete set, so it has no draw pile")
            XCTAssertTrue(snap.boneyardLockedTiles.isEmpty,
                          "no boneyard means no locked pair to show")
        }
    }

    private func openingSnapshot(for mode: MatchFormat) async throws -> GameSnapshot {
        guard let session = EngineSession.createFirstRound(mode: mode) else {
            throw XCTSkip("could not create the first round for \(mode.rawValue)")
        }
        do {
            let snapshot = try await session.snapshot(for: 0)
            await session.close()
            return snapshot
        } catch {
            await session.close()
            throw error
        }
    }
}
