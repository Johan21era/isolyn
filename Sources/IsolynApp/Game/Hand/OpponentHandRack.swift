import SwiftUI

/// A non-requesting seat's physical hand: one face-down back per tile.
///
/// The bridge deliberately exposes only hand *sizes* for other players, never
/// identities. This view respects that boundary by taking an `Int` count and
/// drawing identical backs — there is no tile data here to accidentally leak.
/// A draw inserts a back, a play removes one, so the table shows the same
/// physical fact a player would see across from them: "six tiles, then seven."
struct OpponentHandRack: View {
    let count: Int
    let appearance: DominoAppearance

    private let tileHeight: CGFloat = 14
    private let tileGap: CGFloat = 2

    private var shownCount: Int { max(count, 0) }

    var body: some View {
        HStack(spacing: tileGap) {
            ForEach(0..<shownCount, id: \.self) { _ in
                BoneyardFaceDownTile(
                    appearance: appearance,
                    height: tileHeight
                )
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 5).combined(with: .opacity),
                        removal: .scale(scale: 0.82).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.easeOut(duration: 0.22), value: shownCount)
        .accessibilityHidden(true)
    }
}
