import SwiftUI

// MARK: - Orientation

enum TileOrientation {
    case horizontal   // long axis left-right
    case vertical     // long axis up-down (doubles on chain)
}

// MARK: - Visual Emphasis

enum TileState {
    case idle
    case playable
    case selected
    case dimmed
}

// MARK: - The One True Domino Renderer

/// Renders a domino as ONE sleek curved rectangular piece — not two squares.
/// Real tournament dominoes are polished bone/resin with soft edges; this
/// renderer recreates that feel through proportional geometry, subtle depth,
/// and a restrained center seam.
///
/// Every tile in the app renders through this view. No exceptions.
struct IsolynDominoTile: View {
    let leftPips: Int
    let rightPips: Int
    var orientation: TileOrientation = .horizontal
    /// Height of the tile in points. Width ≈ 2.1× height (real domino ratio).
    var height: CGFloat = 26
    var appearance: DominoAppearance? = nil
    var state: TileState = .idle
    /// Semantic overlay color for hover-chain knowledge classification.
    var semanticEdge: Color? = nil

    var body: some View {
        let w = width
        let h = height
        let radius = h * 0.22
        let pipR = h * 0.09

        let bodyColor = appearance?.bodyColor ?? IsolynTheme.ivory
        let pipColor = appearance?.pipColor ?? IsolynTheme.ebony

        // The single unified tile shape
        Group {
            if orientation == .horizontal {
                content(w: w, h: h, radius: radius, pipRadius: pipR,
                        bodyColor: bodyColor, pipColor: pipColor)
                    .frame(width: w, height: h)
            } else {
                content(w: w, h: h, radius: radius, pipRadius: pipR,
                        bodyColor: bodyColor, pipColor: pipColor)
                    .rotationEffect(.degrees(90))
                    .frame(width: h, height: w)
            }
        }
        .shadow(color: .black.opacity(state == .selected ? 0.35 : 0.18),
                radius: state == .selected ? 8 : 3,
                x: 0, y: state == .selected ? 4 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .opacity(state == .dimmed ? 0.38 : 1.0)
        .scaleEffect(state == .selected ? 1.04 : 1.0)
        .scaleEffect(orientation == .vertical ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.12), value: state)
    }

    // MARK: Internal layout

    private func content(w: CGFloat, h: CGFloat, radius: CGFloat,
                         pipRadius: CGFloat, bodyColor: Color, pipColor: Color) -> some View {
        ZStack {
            // Body — one piece, softly curved
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [bodyColor.opacity(1.0), bodyColor.opacity(0.88)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Center seam — subtle groove, not a thick bar
            seam(width: w, height: h)

            // Pips — positioned per standard domino layouts
            ForEach(Array(leftPipPositions.enumerated()), id: \.offset) { _, pos in
                Circle()
                    .fill(pipColor)
                    .frame(width: pipRadius * 2, height: pipRadius * 2)
                    .position(x: pos.0 * w, y: pos.1 * h)
                    .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            }
            ForEach(Array(rightPipPositions.enumerated()), id: \.offset) { _, pos in
                Circle()
                    .fill(pipColor)
                    .frame(width: pipRadius * 2, height: pipRadius * 2)
                    .position(x: w - pos.0 * w, y: pos.1 * h)
                    .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            }

            // Semantic overlay (hover-chain classification)
            if let sem = semanticEdge {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(sem, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Center seam: a hairline groove suggesting two halves without breaking
    /// the silhouette. Much subtler than a thick divider bar.
    @ViewBuilder
    private func seam(width: CGFloat, height: CGFloat) -> some View {
        let seamW: CGFloat = max(1, height * 0.03)
        HStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: seamW / 2)
                .fill(Color.black.opacity(0.10))
                .frame(width: seamW, height: height * 0.72)
            Spacer()
        }
    }

    // MARK: Geometry helpers

    private var width: CGFloat {
        // Real domino ratio ≈ 2:1 (length:width). Add tiny padding for seam.
        height * 2.08
    }

    /// Pip positions as normalized (0..1, 0..1) fractions of the LEFT half.
    private var leftPipPositions: [(CGFloat, CGFloat)] {
        Self.pipLayout[leftPips] ?? []
    }

    /// Mirror of left positions for the RIGHT half (same layout, offset right).
    private var rightPipPositions: [(CGFloat, CGFloat)] {
        Self.pipLayout[rightPips] ?? []
    }

    private var borderColor: Color {
        if let sem = semanticEdge { return sem.opacity(0.3) }
        switch state {
        case .selected: return IsolynTheme.brass
        case .playable: return IsolynTheme.ivoryMuted.opacity(0.5)
        default: return Color.black.opacity(0.08)
        }
    }

    private var borderWidth: CGFloat {
        state == .selected ? 1.5 : 0.5
    }

    // MARK: Pip layouts (normalized 0..1 within each HALF)

    // Positions use fractional coordinates where 0=left/top edge of half,
    // 1=right/bottom. The renderer maps these into actual pixel space.
    private static let pipLayout: [Int: [(CGFloat, CGFloat)]] = [
        0: [],
        1: [(0.5, 0.5)],
        2: [(0.25, 0.22), (0.75, 0.78)],
        3: [(0.22, 0.20), (0.50, 0.50), (0.78, 0.80)],
        4: [(0.25, 0.22), (0.75, 0.22), (0.25, 0.78), (0.75, 0.78)],
        5: [(0.22, 0.20), (0.78, 0.20), (0.50, 0.50), (0.22, 0.80), (0.78, 0.80)],
        6: [(0.25, 0.18), (0.75, 0.18), (0.25, 0.50), (0.75, 0.50), (0.25, 0.82), (0.75, 0.82)],
    ]
}

// MARK: - Convenience initializers

extension IsolynDominoTile {
    /// From a bridge Tile (canonical low/high).
    init(tile: Tile, orientation: TileOrientation = .horizontal,
         height: CGFloat = 26, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: tile.low, rightPips: tile.high,
                  orientation: orientation, height: height,
                  appearance: appearance, state: state, semanticEdge: semanticEdge)
    }

    /// From explicit displayed faces (chain rendering).
    init(displayingLeft left: Int, right: Int, isDouble: Bool,
         height: CGFloat = 24, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: left, rightPips: right,
                  orientation: isDouble ? .vertical : .horizontal,
                  height: height, appearance: appearance,
                  state: state, semanticEdge: semanticEdge)
    }
}
