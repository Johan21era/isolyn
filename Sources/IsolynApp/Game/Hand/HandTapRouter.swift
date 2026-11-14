/// Decides whether a double-click on a hand tile may be resolved without the
/// player choosing an end.
///
/// Guessing is only allowed when the board's two open ends are equal. In that
/// position the same tile on either side produces the same pair of new ends,
/// so left/right is a purely cosmetic choice. When the ends differ, routing is
/// a real strategic decision and this deliberately returns nil.
enum HandTapRouter {
    static func automaticMove(
        for tile: Tile,
        legalMoves: [Move],
        openEndsMatch: Bool
    ) -> Move? {
        let moves = legalMoves.filter { $0.tile == tile }
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }
        guard openEndsMatch else { return nil }
        return moves.randomElement()
    }
}
