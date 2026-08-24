import SwiftUI

// MARK: - Orientation / State

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

/// THE canonical domino renderer — the single source of truth for every
/// domino in the application (board, hand, overlays, previews).
///
/// NON-NEGOTIABLE GEOMETRY LAW (dominoes_ui_fix_non_negotiable.md §2/§3):
///  * ONE continuous rectangle: one background, one border, one radius,
///    one shadow, one bounding box, one interaction target.
///  * Aspect ratio EXACTLY 2:1 (width == 2 × height), preserved in both
///    orientations and at every scale.
///  * The center divider is a 1pt line INSIDE the rectangle, centered at
///    exactly 50%, never creating physical separation, never widening.
///  * The two halves are INTERNAL CONTENT REGIONS ONLY — they carry no
///    background, border, radius, or shadow of their own, and no amount
///    of zoom can read them as two cards.
///  * Pips are circular, one consistent diameter, placed on the canonical
///    3×3 domino grid for values 0–6 — identical math for every tile.
///
/// Orientation swaps which axis the divider crosses; the silhouette stays
/// one rectangle either way (§20). All tiles in the app share this exact
/// component so a 1|4 and a 6|6 are literally the same object with
/// different pip content (§10).
public struct IsolynDominoTile: View {
    let leftPips: Int
    let rightPips: Int
    var orientation: TileOrientation = .horizontal
    /// Half-height of the tile in points. Full size is exactly 2× this for
    /// the long axis. Defaults to the mandated desktop base (§3): 28pt
    /// half-axis → 56 × 28 horizontal.
    var height: CGFloat = 28
    var appearance: DominoAppearance? = nil
    var state: TileState = .idle
    var semanticEdge: Color? = nil

    /// Canonical pip layouts for values 0–6, normalized (0–1) within each
    /// half-face's own coordinate space. Identical for every tile, both
    /// orientations — the face coordinate space simply follows the divider
    /// axis (§20).
    static let pipLayout: [Int: [(CGFloat, CGFloat)]] = [
        0: [],
        1: [(0.50, 0.50)],
        2: [(0.30, 0.30), (0.70, 0.70)],
        3: [(0.26, 0.26), (0.50, 0.50), (0.74, 0.74)],
        4: [(0.30, 0.30), (0.70, 0.30), (0.30, 0.70), (0.70, 0.70)],
        5: [(0.26, 0.26), (0.74, 0.26), (0.50, 0.50), (0.26, 0.74), (0.74, 0.74)],
        6: [(0.30, 0.22), (0.70, 0.22), (0.30, 0.50), (0.70, 0.50), (0.30, 0.78), (0.70, 0.78)],
    ]

    // MARK: Derived metrics (the entire geometry contract lives here)

    /// Long axis. EXACTLY twice `height` — the 2:1 law (§3).
    private var longAxis: CGFloat { height * 2 }
    private var cornerRadius: CGFloat { min(6, max(4, height * 0.18)) }   // §3: 4–6px
    private var borderWidth: CGFloat { 1 }                                 // §3: 1px outer border
    private var dividerThickness: CGFloat { 1 }                            // §3: 1px divider
    /// Divider runs the SHORT axis, inset from the edges so it reads as an
    /// engraved rule rather than touching the border.
    private var dividerInset: CGFloat { max(3, height * 0.12) }

    public var body: some View {
        let size = (orientation == .horizontal)
            ? CGSize(width: longAxis, height: height)
            : CGSize(width: height, height: longAxis)

        return tileBody(size: size)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(state == .selected ? 0.35 : 0.18),
                    radius: state == .selected ? 7 : 2.5,
                    x: 0, y: state == .selected ? 3 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .opacity(state == .dimmed ? 0.38 : 1.0)
            .scaleEffect(state == .selected ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.14), value: state)   // §25: 100–180ms
    }

    // MARK: One rectangle: background + internal regions + divider

    private func tileBody(size: CGSize) -> some View {
        let bodyColor = appearance?.bodyColor ?? Color(red: 0.949, green: 0.925, blue: 0.867)
        let pipColor = appearance?.pipColor ?? Color(red: 0.071, green: 0.063, blue: 0.051)
        // Divider derives from the pip ink so custom themes stay coherent;
        // subtle enough to never read as a gap (contrast law §23).
        let dividerColor = pipColor.opacity(0.28)

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(bodyColor)

            if orientation == .horizontal {
                HStack(spacing: 0) {
                    face(pips: leftPips, pipColor: pipColor)
                        .frame(width: size.width / 2, height: size.height)
                    // Internal divider — a line INSIDE the material,
                    // exactly at 50% (§3). Never a gap, never wider.
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: dividerThickness)
                        .padding(.vertical, dividerInset)
                    face(pips: rightPips, pipColor: pipColor)
                        .frame(width: size.width / 2, height: size.height)
                }
            } else {
                VStack(spacing: 0) {
                    face(pips: leftPips, pipColor: pipColor)
                        .frame(width: size.width, height: size.height / 2)
                    Rectangle()
                        .fill(dividerColor)
                        .frame(height: dividerThickness)
                        .padding(.horizontal, dividerInset)
                    face(pips: rightPips, pipColor: pipColor)
                        .frame(width: size.width, height: size.height / 2)
                }
            }

            // Analytical semantic edges keep absolute precedence over the
            // user's decorative edge preference (FIX-22 contract).
            if let sem = semanticEdge {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(sem, lineWidth: 2)
            } else if let appearance, appearance.edgeMode != .none {
                let intensity = max(0, min(1, appearance.edgeIntensity))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(appearance.edgeColor.opacity(intensity),
                                  lineWidth: 0.75 + intensity * 1.25)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// One half-face: pure pip content, ZERO chrome of its own — no
    /// background, border, radius, or shadow. The halves are regions of
    /// the one tile, never cards (§2).
    private func face(pips: Int, pipColor: Color) -> some View {
        GeometryReader { geo in
            let d = geo.size
            // One uniform pip diameter per tile, derived from the SHORT
            // half dimension so horizontal and vertical faces match.
            let diameter = min(d.width, d.height) * 0.19
            ZStack {
                ForEach(Array(Self.pipPoints(pips: pips, size: d).enumerated()),
                        id: \.offset) { _, pt in
                    Circle()
                        .fill(pipColor)
                        .frame(width: diameter, height: diameter)
                        .position(pt)
                }
            }
        }
    }

    /// Maps the canonical normalized grid into the face's pixel space.
    static func pipPoints(pips: Int, size: CGSize) -> [CGPoint] {
        (pipLayout[pips] ?? []).map { CGPoint(x: $0.0 * size.width, y: $0.1 * size.height) }
    }

    var borderColor: Color {
        if let sem = semanticEdge { return sem.opacity(0.3) }
        switch state {
        case .selected: return Color(red: 0.737, green: 0.573, blue: 0.283)   // brass
        case .playable: return Color.white.opacity(0.45)
        default: return Color.black.opacity(0.10)
        }
    }
}

// MARK: - Convenience initializers (call-site compatibility)

extension IsolynDominoTile {
    init(tile low: Int, _ high: Int, orientation: TileOrientation = .horizontal,
         height: CGFloat = 28, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: low, rightPips: high, orientation: orientation,
                  height: height, appearance: appearance, state: state,
                  semanticEdge: semanticEdge)
    }

    init(displayingLeft left: Int, right: Int, isDouble: Bool,
         height: CGFloat = 28, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: left, rightPips: right,
                  orientation: isDouble ? .vertical : .horizontal,
                  height: height, appearance: appearance,
                  state: state, semanticEdge: semanticEdge)
    }

    init(low: Int, high: Int, orientation: TileOrientation = .horizontal,
         height: CGFloat = 28, appearance: DominoAppearance? = nil,
         state: TileState = .idle, semanticEdge: Color? = nil) {
        self.init(leftPips: low, rightPips: high, orientation: orientation,
                  height: height, appearance: appearance, state: state,
                  semanticEdge: semanticEdge)
    }

    init(tile: (low: Int, high: Int), orientation: TileOrientation = .horizontal,
         height: CGFloat = 28, appearance: DominoAppearance? = nil,
         state: TileState = .idle) {
        self.init(leftPips: tile.low, rightPips: tile.high,
                  orientation: orientation, height: height,
                  appearance: appearance, state: state)
    }
}
