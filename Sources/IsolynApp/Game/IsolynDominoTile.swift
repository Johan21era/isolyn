import SwiftUI

enum TileOrientation {
    case horizontal
    case vertical
}

enum TileState {
    case idle
    case playable
    case selected
    case dimmed
}

/// ONE seamless rounded rectangle per domino. No seam, no divider, no gap.
/// Pips are positioned within each geometric half of the same continuous surface.
public struct IsolynDominoTile: View {
    let leftPips: Int
    let rightPips: Int
    var orientation: TileOrientation = .horizontal
    var height: CGFloat = 26
    var appearance: DominoAppearance? = nil
    var state: TileState = .idle
    var semanticEdge: Color? = nil

    // Standard 3×3 pip layouts, normalized (0–1) within each half.
    static let pipLayout: [Int: [(CGFloat, CGFloat)]] = [
        0: [],
        1: [(0.50, 0.50)],
        2: [(0.28, 0.28), (0.72, 0.72)],
        3: [(0.25, 0.25), (0.50, 0.50), (0.75, 0.75)],
        4: [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)],
        5: [(0.25, 0.25), (0.75, 0.25), (0.50, 0.50), (0.25, 0.75), (0.75, 0.75)],
        6: [(0.30, 0.20), (0.70, 0.20), (0.30, 0.50), (0.70, 0.50), (0.30, 0.80), (0.70, 0.80)],
    ]

    public var body: some View {
        let w = height * 2.1
        let h = height
        let r = height * 0.20
        let pr = height * 0.085

        Group {
            if orientation == .horizontal {
                tileBody(width: w, height: h, radius: r, pipRadius: pr)
                    .frame(width: w, height: h)
            } else {
                tileBody(width: w, height: h, radius: r, pipRadius: pr)
                    .rotationEffect(.degrees(90))
                    .frame(width: h, height: w)
            }
        }
        .shadow(color: .black.opacity(state == .selected ? 0.35 : 0.15),
                radius: state == .selected ? 7 : 2.5,
                x: 0, y: state == .selected ? 3 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .opacity(state == .dimmed ? 0.38 : 1.0)
        .scaleEffect(state == .selected ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.12), value: state)
    }

    /// One continuous rounded rectangle. Pips placed per half. Nothing else.
    func tileBody(width w: CGFloat, height h: CGFloat,
                  radius r: CGFloat, pipRadius pr: CGFloat) -> some View {
        let bodyColor = appearance?.bodyColor ?? Color(red: 0.949, green: 0.925, blue: 0.867)
        let pipColor = appearance?.pipColor ?? Color(red: 0.071, green: 0.063, blue: 0.051)

        return ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(bodyColor)

            ForEach(Array(pipPoints(halfWidth: w/2, tileHeight: h,
                                    pipR: pr, pips: leftPips).enumerated()),
                    id: \.offset) { _, pt in
                Circle().fill(pipColor).frame(width: pr*2, height: pr*2).position(pt)
            }

            ForEach(Array(pipPoints(halfWidth: w/2, tileHeight: h,
                                    pipR: pr, pips: rightPips, offset: w/2).enumerated()),
                    id: \.offset) { _, pt in
                Circle().fill(pipColor).frame(width: pr*2, height: pr*2).position(pt)
            }

            if let sem = semanticEdge {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(sem, lineWidth: 2)
            } else if let appearance, appearance.edgeMode != .none {
                // FIX-22 (roadmap N-2): the settings drawer's Edge
                // Highlight section is no longer decorative -- mode gates
                // on/off and the user's intensity slider drives opacity
                // + a subtly scaled stroke width. Analytical semantic
                // edges ALWAYS win precedence above: engine-derived
                // signal must never be drowned out by decoration.
                let intensity = max(0, min(1, appearance.edgeIntensity))
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(appearance.edgeColor.opacity(intensity),
                                  lineWidth: 0.75 + intensity * 1.25)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }

    private func pipPoints(halfWidth: CGFloat, tileHeight: CGFloat,
                           pipR: CGFloat, pips: Int, offset: CGFloat = 0) -> [CGPoint] {
        (Self.pipLayout[pips] ?? []).map { frac in
            CGPoint(x: offset + frac.0 * halfWidth, y: frac.1 * tileHeight)
        }
    }

    var borderColor: Color {
        if let sem = semanticEdge { return sem.opacity(0.3) }
        switch state {
        case .selected: return Color(red: 0.737, green: 0.573, blue: 0.283)
        case .playable: return Color.white.opacity(0.4)
        default: return Color.black.opacity(0.08)
        }
    }

    var borderWidth: CGFloat { state == .selected ? 1.5 : 0.5 }
}

// MARK: - Convenience

extension IsolynDominoTile {
    init(tile low: Int, _ high: Int, orientation: TileOrientation = .horizontal,
         height: CGFloat = 26, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: low, rightPips: high, orientation: orientation,
                  height: height, appearance: appearance, state: state,
                  semanticEdge: semanticEdge)
    }

    init(displayingLeft left: Int, right: Int, isDouble: Bool,
         height: CGFloat = 24, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: left, rightPips: right,
                  orientation: isDouble ? .vertical : .horizontal,
                  height: height, appearance: appearance,
                  state: state, semanticEdge: semanticEdge)
    }

    init(low: Int, high: Int, orientation: TileOrientation = .horizontal,
         height: CGFloat = 26, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: low, rightPips: high, orientation: orientation,
                  height: height, appearance: appearance, state: state,
                  semanticEdge: semanticEdge)
    }

    init(tile: (low: Int, high: Int), orientation: TileOrientation = .horizontal,
         height: CGFloat = 26, appearance: DominoAppearance? = nil,
         state: TileState = .idle) {
        self.init(leftPips: tile.low, rightPips: tile.high,
                  orientation: orientation, height: height,
                  appearance: appearance, state: state)
    }
}
