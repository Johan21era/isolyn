import SwiftUI

/// One face of a domino (0-6 pips) drawn as the classic 3x3 pip arrangement.
/// Blank faces render as clean bone -- the zero is real information, not an
/// absence. Deliberately independent of `PipGlyph` (that component encodes
/// PLAYER COUNTS as its graphic signature; a domino face is a different
/// semantic and deserves its own minimal renderer).
struct DominoFaceView: View {
    let pips: Int
    let side: CGFloat

    /// Grid positions (column, row) within a 3x3 layout, standard pip maps.
    private static let layouts: [Int: [(CGFloat, CGFloat)]] = [
        0: [],
        1: [(1, 1)],
        2: [(0, 0), (2, 2)],
        3: [(0, 0), (1, 1), (2, 2)],
        4: [(0, 0), (0, 2), (2, 0), (2, 2)],
        5: [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)],
        6: [(0, 0), (0, 1), (0, 2), (2, 0), (2, 1), (2, 2)],
    ]

    var body: some View {
        let cell = side / 3
        let pip = cell * 0.52
        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.14, style: .continuous)
                .fill(IsolynTheme.ivory)
            ForEach(Array(pipPositions.enumerated()), id: \.offset) { _, pos in
                Circle()
                    .fill(IsolynTheme.ebony)
                    .frame(width: pip, height: pip)
                    .position(x: cell * (pos.0 + 0.5), y: cell * (pos.1 + 0.5))
            }
        }
        .frame(width: side, height: side)
    }

    private var pipPositions: [(CGFloat, CGFloat)] {
        Self.layouts[pips] ?? []
    }
}

/// Visual emphasis of a tile in the rack or on the board.
enum TileState {
    case idle        // ordinary display
    case playable    // mine, and this tile has at least one legal move
    case selected    // mine, currently tapped
    case dimmed      // not interactable right now (opponent view, blocked, etc.)
}

/// A full domino rendered from two explicit displayed faces. Orientation is
/// ALWAYS supplied by the caller (rack = horizontal; chain doubles =
/// vertical) -- mirroring the engine's own rule that per-tile orientation is
/// derivable context, never stored state.
struct TileView: View {
    let leftPips: Int
    let rightPips: Int
    var vertical: Bool = false
    var tileSize: CGFloat = 30     // square face edge
    var state: TileState = .idle

    var body: some View {
        let faceStack = HStack(spacing: 1.5) {
            DominoFaceView(pips: leftPips, side: tileSize)
            Rectangle()
                .fill(IsolynTheme.ebonyLine)
                .frame(width: 1.5)
            DominoFaceView(pips: rightPips, side: tileSize)
        }

        Group {
            if vertical {
                faceStack.rotationEffect(.degrees(-90))
                    .frame(width: tileSize * 2 + 4, height: tileSize)
            } else {
                faceStack
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: tileSize * 0.18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: state == .selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.35), radius: state == .selected ? 6 : 2,
                x: 0, y: state == .selected ? 3 : 1)
        .opacity(state == .dimmed ? 0.45 : 1)
        .scaleEffect(state == .selected ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: state)
    }

    private var borderColor: Color {
        switch state {
        case .selected: return IsolynTheme.brass
        case .playable: return IsolynTheme.ivoryMuted
        default: return IsolynTheme.ebonyLine
        }
    }
}

/// Convenience initializers from the bridge-side Tile model.
extension TileView {
    /// Rack-style: canonical low|high reading.
    init(tile: Tile, tileSize: CGFloat = 30, state: TileState = .idle) {
        self.init(leftPips: tile.low, rightPips: tile.high,
                  vertical: false, tileSize: tileSize, state: state)
    }

    /// Chain-style: explicit displayed orientation so adjacent pips visually
    /// match their neighbours.
    init(displayingLeft left: Int, right: Int, isDouble: Bool,
         tileSize: CGFloat = 26, state: TileState = .idle) {
        self.init(leftPips: left, rightPips: right,
                  vertical: isDouble, tileSize: tileSize, state: state)
    }
}
