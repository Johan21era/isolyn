import SwiftUI

/// The 1v1 draw pile on the table.
///
/// The rules treat the boneyard as one physical row, not a stack: face-down
/// tiles line up side by side, drawing only ever removes from the open end,
/// and the final two at the opposite end are permanently closed. This view
/// mirrors that row literally.
///
/// The closed pair sits on the left and never moves. The draw end is on the
/// right; when a tile is drawn the rightmost tile leaves and the row gets
/// shorter toward the closed pair. The two closed tiles stay face down for
/// the whole round, including after the bridge learns their identities.
///
/// 1v1v1 and 2v2 deal the full set, so this view is not placed on those
/// tables at all. The Draw/Pass control lives in `actionDock` and is never
/// replaced by this object.
struct BoneyardView: View {
    let drawableCount: Int
    let appearance: DominoAppearance

    /// The rules always reserve exactly two tiles at the closed end in 1v1.
    /// They remain physical table objects from the opening deal onward, even
    /// while the bridge is still withholding their identities.
    private let closedCount = 2
    private let tileHeight: CGFloat = 26
    private let tileGap: CGFloat = 2
    private let closedGap: CGFloat = 9
    private let railWidth: CGFloat = 1.5
    private let edgePad: CGFloat = 4
    private let drawRailPad: CGFloat = 5

    private var drawable: Int { max(drawableCount, 0) }
    private var tileWidth: CGFloat { tileHeight * 2 }

    private var closedPairWidth: CGFloat {
        CGFloat(closedCount) * tileWidth + CGFloat(closedCount - 1) * tileGap
    }

    private var closedBlockWidth: CGFloat {
        railWidth + edgePad + closedPairWidth
    }

    private var drawableWidth: CGFloat {
        guard drawable > 0 else { return 0 }
        return CGFloat(drawable) * tileWidth + CGFloat(drawable - 1) * tileGap
    }

    private var lineWidth: CGFloat {
        closedBlockWidth + closedGap + drawableWidth + drawRailPad + railWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            HStack(spacing: 0) {
                Text("CLOSED")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(IsolynTheme.brass.opacity(0.82))
                    .frame(width: closedBlockWidth, alignment: .leading)

                Spacer(minLength: 0)

                if drawable > 0 {
                    Text("DRAW \(drawable)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .tracking(0.4)
                        .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.85))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: drawable)
                }
            }
            .frame(width: lineWidth)
        }
        .fixedSize(horizontal: true, vertical: true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - The row

    private var row: some View {
        HStack(alignment: .center, spacing: 0) {
            // The closed end is a physical stop: a thin rail, then the two
            // reserved tiles. It never moves as the open end drains.
            Rectangle()
                .fill(IsolynTheme.ivoryMuted.opacity(0.32))
                .frame(width: railWidth, height: tileHeight + 4)

            HStack(spacing: tileGap) {
                ForEach(0..<closedCount, id: \.self) { _ in
                    BoneyardFaceDownTile(
                        appearance: appearance,
                        height: tileHeight
                    )
                }
            }
            .padding(.leading, edgePad)

            Color.clear.frame(width: closedGap, height: 1)

            if drawable > 0 {
                HStack(spacing: tileGap) {
                    ForEach(0..<drawable, id: \.self) { _ in
                        BoneyardFaceDownTile(
                            appearance: appearance,
                            height: tileHeight
                        )
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .offset(x: 18).combined(with: .opacity)
                            )
                        )
                    }
                }
                .animation(.easeOut(duration: 0.22), value: drawable)
            }

            // The open end. Draws remove the rightmost face-down tile, so
            // this rail is always the live edge of the row.
            Rectangle()
                .fill(
                    drawable > 0
                        ? IsolynTheme.brass.opacity(0.9)
                        : IsolynTheme.ivoryMuted.opacity(0.22)
                )
                .frame(width: railWidth, height: tileHeight + 4)
                .padding(.leading, drawRailPad)
        }
        .frame(width: lineWidth, height: tileHeight + 4, alignment: .leading)
        .background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(GameSurfaceCoordinateSpace.name))
                Color.clear.preference(
                    key: BoneyardAnchorKey.self,
                    value: CGPoint(
                        x: frame.maxX - railWidth,
                        y: frame.midY
                    )
                )
            }
        )
    }

    private var accessibilityText: String {
        let drawable = max(drawableCount, 0)
        let drawLabel = "\(drawable) drawable tile\(drawable == 1 ? "" : "s")"
        return drawable == 0
            ? "Draw pile empty; two closed tiles at the far end"
            : "Draw pile, \(drawLabel); two closed tiles at the far end"
    }
}

// MARK: - Face-down piece

/// The back of a boneyard tile. Same 2:1 silhouette as every other domino,
/// with a quiet inset rule and a single centered mark so it reads as a
/// physical face-down piece rather than an empty card.
struct BoneyardFaceDownTile: View {
    let appearance: DominoAppearance
    var height: CGFloat = 22

    private var cornerRadius: CGFloat { max(3, min(5, height * 0.18)) }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(appearance.bodyColor)
            .frame(width: height * 2, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: max(2, cornerRadius - 1), style: .continuous)
                    .strokeBorder(appearance.pipColor.opacity(0.17), lineWidth: 0.7)
                    .padding(height * 0.13)
            )
            .overlay(
                Rectangle()
                    .fill(appearance.pipColor.opacity(0.22))
                    .frame(width: height * 0.16, height: height * 0.16)
                    .rotationEffect(.degrees(45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(appearance.pipColor.opacity(0.10), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
    }
}

// MARK: - Flight origin

/// The live open-end center of the row in `gameSurface` coordinates. The
/// flight reads this rather than guessing at the action-dock position.
struct BoneyardAnchorKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
