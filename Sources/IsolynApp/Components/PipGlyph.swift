import SwiftUI

/// Draws the pip arrangement for one face of a domino tile -- the same
/// six patterns used on a real set, from a single ace to a full six.
///
/// This is Isolyn's one recurring graphic signature: used to represent
/// player and team counts throughout the app (a "2" glyph literally
/// means "two players on this side") instead of generic people icons,
/// so the app's own chrome is made out of the same visual language as
/// the game itself.
struct PipGlyph: View {
    let count: Int
    var color: Color = IsolynTheme.ivory

    /// Grid positions (column, row) within a 3x3 layout, matching the
    /// standard pip arrangement for each face value.
    private static let layouts: [Int: [(CGFloat, CGFloat)]] = [
        1: [(1, 1)],
        2: [(0, 0), (2, 2)],
        3: [(0, 0), (1, 1), (2, 2)],
        4: [(0, 0), (0, 2), (2, 0), (2, 2)],
        5: [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)],
        6: [(0, 0), (0, 1), (0, 2), (2, 0), (2, 1), (2, 2)],
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 3
            let pipDiameter = cell * 0.6

            ForEach(Array(positions.enumerated()), id: \.offset) { _, position in
                Circle()
                    .fill(color)
                    .frame(width: pipDiameter, height: pipDiameter)
                    .position(
                        x: cell * (position.0 + 0.5),
                        y: cell * (position.1 + 0.5)
                    )
            }
        }
    }

    private var positions: [(CGFloat, CGFloat)] {
        Self.layouts[count] ?? []
    }
}
