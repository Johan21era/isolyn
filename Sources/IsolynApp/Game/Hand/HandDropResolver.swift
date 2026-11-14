import CoreGraphics

/// Pure resolution of a dragged hand tile against the board's reported end
/// targets. Kept out of the SwiftUI view so the drop rules are testable
/// without a window or pointer events.
enum HandDropResolver {
    /// Extra forgiveness around the already-generous end-target frame.
    static let dropPadding: CGFloat = 32

    static func move(
        for tile: Tile,
        at point: CGPoint,
        snapshot: GameSnapshot,
        targets: [ChainSide: CGRect]
    ) -> Move? {
        guard snapshot.roundOutcome == .inProgress else { return nil }

        // The opening has no physical end yet; any legal opening placement
        // for this tile is the whole drop surface.
        if snapshot.chain.isEmpty {
            return snapshot.legalMoves.first(where: { $0.tile == tile })
        }

        // Nearest target wins when the forgiving zones overlap (short chains
        // put the two ends close together). This is deliberately much larger
        // than the visual tick: the player is aiming at a side, not a pixel.
        let candidates = targets.compactMap { side, rect -> (side: ChainSide, distance: CGFloat)? in
            let forgiving = rect.insetBy(dx: -Self.dropPadding, dy: -Self.dropPadding)
            guard forgiving.contains(point) else { return nil }
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return (side, hypot(dx, dy))
        }
        guard let side = candidates.min(by: { $0.distance < $1.distance })?.side else {
            return nil
        }
        return snapshot.legalMoves.first(where: { $0.tile == tile && $0.side == side })
    }
}
