import XCTest
@testable import IsolynApp

final class HandTapRouterTests: XCTestCase {
    private let tile = Tile(low: 3, high: 6)
    private let left = Move(tile: Tile(low: 3, high: 6), side: .left)
    private let right = Move(tile: Tile(low: 3, high: 6), side: .right)

    func test_singleLegalSide_playsWithoutGuessing() {
        XCTAssertEqual(
            HandTapRouter.automaticMove(
                for: tile,
                legalMoves: [left],
                openEndsMatch: false
            ),
            left
        )
    }

    func test_equalOpenEnds_randomlyChoosesOneOfTheEquivalentSides() {
        for _ in 0..<40 {
            let move = HandTapRouter.automaticMove(
                for: tile,
                legalMoves: [left, right],
                openEndsMatch: true
            )
            XCTAssertNotNil(move)
            XCTAssertTrue(move == left || move == right)
        }
    }

    func test_differentOpenEnds_refusesToGuess() {
        XCTAssertNil(
            HandTapRouter.automaticMove(
                for: tile,
                legalMoves: [left, right],
                openEndsMatch: false
            )
        )
    }

    func test_noLegalSide_returnsNil() {
        XCTAssertNil(
            HandTapRouter.automaticMove(
                for: tile,
                legalMoves: [],
                openEndsMatch: true
            )
        )
    }

    func test_otherTile_isIgnored() {
        let other = Move(tile: Tile(low: 1, high: 2), side: .left)
        XCTAssertNil(
            HandTapRouter.automaticMove(
                for: tile,
                legalMoves: [other],
                openEndsMatch: true
            )
        )
    }
}
