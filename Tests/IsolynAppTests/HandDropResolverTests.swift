import XCTest
@testable import IsolynApp

final class HandDropResolverTests: XCTestCase {
    private let tile = Tile(low: 3, high: 5)
    private let other = Tile(low: 1, high: 2)

    func test_dropInsideMatchingEnd_returnsTheLegalMove() {
        let move = Move(tile: tile, side: .left)
        let snapshot = makeSnapshot(
            chain: [Tile(low: 1, high: 1)],
            leftEnd: 1,
            rightEnd: 1,
            legalMoves: [move]
        )

        let resolved = HandDropResolver.move(
            for: tile,
            at: CGPoint(x: 20, y: 20),
            snapshot: snapshot,
            targets: [.left: CGRect(x: 0, y: 0, width: 44, height: 44)]
        )

        XCTAssertEqual(resolved, move)
    }

    func test_dropOutsideEveryEnd_returnsNil() {
        let snapshot = makeSnapshot(
            chain: [Tile(low: 1, high: 1)],
            leftEnd: 1,
            rightEnd: 1,
            legalMoves: [Move(tile: tile, side: .left)]
        )

        XCTAssertNil(HandDropResolver.move(
            for: tile,
            at: CGPoint(x: 100, y: 100),
            snapshot: snapshot,
            targets: [.left: CGRect(x: 0, y: 0, width: 44, height: 44)]
        ))
    }

    func test_dropJustOutsideVisualEnd_stillConnects() {
        let move = Move(tile: tile, side: .left)
        let snapshot = makeSnapshot(
            chain: [Tile(low: 1, high: 1)],
            leftEnd: 1,
            rightEnd: 1,
            legalMoves: [move]
        )

        // The visible end target is much smaller than the forgiving drop
        // zone; this point is outside the 44pt box but inside the padding.
        XCTAssertEqual(HandDropResolver.move(
            for: tile,
            at: CGPoint(x: 70, y: 22),
            snapshot: snapshot,
            targets: [.left: CGRect(x: 0, y: 0, width: 44, height: 44)]
        ), move)
    }

    func test_overlappingForgivingZones_pickTheNearestEnd() {
        let left = Move(tile: tile, side: .left)
        let right = Move(tile: tile, side: .right)
        let snapshot = makeSnapshot(
            chain: [Tile(low: 1, high: 1)],
            leftEnd: 1,
            rightEnd: 1,
            legalMoves: [left, right]
        )

        XCTAssertEqual(HandDropResolver.move(
            for: tile,
            at: CGPoint(x: 60, y: 22),
            snapshot: snapshot,
            targets: [
                .left: CGRect(x: 0, y: 0, width: 44, height: 44),
                .right: CGRect(x: 40, y: 0, width: 44, height: 44),
            ]
        ), right)
    }

    func test_dropOnWrongOrMismatchedSide_returnsNil() {
        let snapshot = makeSnapshot(
            chain: [Tile(low: 1, high: 1)],
            leftEnd: 1,
            rightEnd: 1,
            legalMoves: [Move(tile: tile, side: .left)]
        )

        XCTAssertNil(HandDropResolver.move(
            for: tile,
            at: CGPoint(x: 20, y: 20),
            snapshot: snapshot,
            targets: [.right: CGRect(x: 0, y: 0, width: 44, height: 44)]
        ))
        XCTAssertNil(HandDropResolver.move(
            for: other,
            at: CGPoint(x: 20, y: 20),
            snapshot: snapshot,
            targets: [.left: CGRect(x: 0, y: 0, width: 44, height: 44)]
        ))
    }

    func test_emptyChain_acceptsAnyLegalOpeningPlacement() {
        let opening = Move(tile: tile, side: .left)
        let snapshot = makeSnapshot(
            chain: [],
            leftEnd: nil,
            rightEnd: nil,
            legalMoves: [opening]
        )

        XCTAssertEqual(HandDropResolver.move(
            for: tile,
            at: CGPoint(x: 500, y: 500),
            snapshot: snapshot,
            targets: [:]
        ), opening)
    }

    private func makeSnapshot(
        chain: [Tile],
        leftEnd: Int?,
        rightEnd: Int?,
        legalMoves: [Move]
    ) -> GameSnapshot {
        GameSnapshot(
            stateVersion: 1,
            mode: .oneVOne,
            playerCount: 2,
            requestingPlayerIndex: 0,
            currentPlayerIndex: 0,
            ownHand: [tile, other],
            otherHandSizes: [0, 7],
            chain: chain,
            chainLeftEnd: leftEnd,
            chainRightEnd: rightEnd,
            boneyardDrawableCount: 0,
            finalHandValues: [0, 0],
            roundOutcome: .inProgress,
            legalMoves: legalMoves
        )
    }
}
