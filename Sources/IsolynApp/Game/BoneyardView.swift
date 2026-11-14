import SwiftUI

/// The 1v1 draw pile on the table.
///
/// The rules treat the boneyard as one physical line of face-down tiles that
/// descends away from the player: draws come from the bottom (open) end, and
/// the two reserved tiles at the top become the closed side only after the
/// first draw has fixed that direction. At the opening deal neither side is
/// marked closed; all fourteen tiles simply sit in one column.
///
/// The top two tiles are still the permanently reserved pair from the engine's
/// canonical order; the UI deliberately withholds the `CLOSED` marker until a
/// draw has actually happened. When it does, those two pieces turn upright and
/// sit side by side as a distinct closed cap. The pair never turns face up —
/// the bridge's late identity reveal is strategy data, not a reason to expose
/// table tiles.
///
/// The whole pile is the draw target, using the same `voluntaryDraw` path as
/// the action-dock button. 1v1v1 and 2v2 deal the full set, so this view is not
/// placed on those tables at all.
struct BoneyardView: View {
    let drawableCount: Int
    let appearance: DominoAppearance

    /// The board's live height. The pile grows to stay readable on a large
    /// table and compresses only when the board is genuinely tight.
    var availableHeight: CGFloat? = nil

    /// Clicking the pile is an alternate Draw action, but only while drawing
    /// is actually legal. The action-dock Draw/Pass control remains present.
    var isDrawEnabled: Bool = false
    var onDraw: () -> Void = {}

    /// 1v1 leaves these many drawable tiles after the opening deal. The first
    /// draw takes this below the opening count, which is the physical moment
    /// the chosen direction closes the opposite side.
    private let openingDrawableCount = 12
    private let closedCount = 2
    private let maxTileHeight: CGFloat = 20
    private let minTileHeight: CGFloat = 14
    private let tileGap: CGFloat = 2.5
    private let closedGap: CGFloat = 9
    private let railWidth: CGFloat = 2

    private var drawable: Int { max(drawableCount, 0) }
    private var hasFirstDraw: Bool { drawableCount < openingDrawableCount }
    private var tileWidth: CGFloat { tileHeight * 2 }
    private var closedPairWidth: CGFloat { tileHeight * 2 + tileGap }

    /// After the first draw the closed pair stands upright, so reserve two
    /// portrait pieces plus the drawable column when fitting the board.
    private var tileHeight: CGFloat {
        guard let availableHeight, availableHeight > 0 else { return maxTileHeight }
        let reserved: CGFloat = 54
        let fit = (availableHeight - reserved) / 15 - tileGap
        return min(maxTileHeight, max(minTileHeight, fit))
    }

    var body: some View {
        Button(action: onDraw) {
            VStack(spacing: 4) {
                if hasFirstDraw {
                    Text("CLOSED")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.65)
                        .foregroundStyle(IsolynTheme.brass.opacity(0.9))
                        .transition(.offset(y: -5).combined(with: .opacity))
                }

                column

                if drawable > 0 {
                    Text("DRAW \(drawable)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .tracking(0.35)
                        .foregroundStyle(IsolynTheme.ivory.opacity(0.82))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.24), value: drawable)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.44, dampingFraction: 0.78), value: hasFirstDraw)
        }
        .buttonStyle(BoneyardPressStyle())
        .disabled(!isDrawEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isDrawEnabled ? "Draws one tile" : "")
    }

    // MARK: - The column

    private var column: some View {
        VStack(spacing: tileGap) {
            if hasFirstDraw {
                // The closed side points upward: a cap over the upright pair.
                rail(color: IsolynTheme.brass.opacity(0.92), width: closedPairWidth)
                    .transition(.scale(scale: 0.45, anchor: .top).combined(with: .opacity))
            }

            closedPair

            if hasFirstDraw {
                Color.clear.frame(width: tileWidth, height: closedGap)
            }

            if drawable > 0 {
                ForEach(0..<drawable, id: \.self) { _ in
                    faceDownTile(upright: false)
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: -9).combined(with: .opacity),
                                removal: .offset(y: 15).combined(with: .opacity)
                            )
                        )
                }

                // The draw edge is the bottom of the column.
                rail(color: IsolynTheme.brass.opacity(0.92))
                    .padding(.top, 1)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: drawable)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: hasFirstDraw)
        .background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(GameSurfaceCoordinateSpace.name))
                Color.clear.preference(
                    key: BoneyardAnchorKey.self,
                    value: CGPoint(
                        x: frame.midX,
                        y: frame.maxY - railWidth
                    )
                )
            }
        )
    }

    /// Before a direction exists, the reserved pair lies flat in the column.
    /// The first draw turns both pieces upright and lays them side by side as
    /// the closed cap, which makes the fixed end read immediately.
    private var closedPair: some View {
        let layout = hasFirstDraw
            ? AnyLayout(HStackLayout(spacing: tileGap))
            : AnyLayout(VStackLayout(spacing: tileGap))

        return layout {
            ForEach(0..<closedCount, id: \.self) { _ in
                faceDownTile(upright: hasFirstDraw)
            }
        }
    }

    private func faceDownTile(upright: Bool) -> some View {
        BoneyardFaceDownTile(
            appearance: appearance,
            height: tileHeight,
            upright: upright
        )
        .frame(
            width: upright ? tileHeight : tileWidth,
            height: upright ? tileWidth : tileHeight
        )
    }

    private func rail(color: Color, width: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: width ?? tileWidth, height: railWidth)
    }

    private var accessibilityText: String {
        let drawable = max(drawableCount, 0)
        let drawLabel = "\(drawable) drawable tile\(drawable == 1 ? "" : "s")"
        if hasFirstDraw {
            return "Draw pile, \(drawLabel); two closed tiles upright at the top"
        }
        return "Draw pile, \(drawLabel); no side closed yet"
    }
}

// MARK: - Press feedback

/// The pile should acknowledge a click before the engine round-trip finishes.
/// The draw itself lands with the column spring and the flying face-down tile.
private struct BoneyardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.045 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Face-down piece

/// The back of a boneyard tile. Same 2:1 silhouette as every other domino,
/// with a quiet inset rule and a single centered mark so it reads as a
/// physical face-down piece rather than an empty card. `upright` turns the
/// silhouette portrait for the closed pair.
struct BoneyardFaceDownTile: View {
    let appearance: DominoAppearance
    var height: CGFloat = 22
    var upright: Bool = false

    private var pieceWidth: CGFloat { upright ? height : height * 2 }
    private var pieceHeight: CGFloat { upright ? height * 2 : height }
    private var cornerRadius: CGFloat { max(3, min(5, height * 0.18)) }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(appearance.bodyColor)
            .frame(width: pieceWidth, height: pieceHeight)
            .overlay(
                RoundedRectangle(cornerRadius: max(2, cornerRadius - 1), style: .continuous)
                    .strokeBorder(appearance.pipColor.opacity(0.19), lineWidth: 0.7)
                    .padding(height * 0.13)
            )
            .overlay(
                Rectangle()
                    .fill(appearance.pipColor.opacity(0.24))
                    .frame(width: height * 0.16, height: height * 0.16)
                    .rotationEffect(.degrees(45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(appearance.pipColor.opacity(0.11), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.25), radius: 1.8, y: 1.2)
    }
}

// MARK: - Flight origin

/// The live center of the open bottom edge in `gameSurface` coordinates. The
/// flight reads this rather than guessing at the action-dock position.
struct BoneyardAnchorKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
