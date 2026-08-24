import SwiftUI

/// Describes one selectable entry on the mode selector. `pipCounts` has
/// one entry per side, and each number IS the player count on that side
/// -- e.g. `[1, 1]` for a 1v1 duel, `[2, 2]` for 2v2 partners -- so the
/// pip glyphs drawn from it are literally true, not decorative.
struct ModeOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let pipCounts: [Int]
}

/// A single tappable mode card. The whole card is the button -- no
/// separate "select" control buried inside it.
struct ModeCard: View {
    let option: ModeOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    ForEach(Array(option.pipCounts.enumerated()), id: \.offset) { index, count in
                        if index > 0 {
                            Text("vs")
                                .font(IsolynTheme.caption(11))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                        }
                        PipGlyph(count: count, color: isSelected ? IsolynTheme.brass : IsolynTheme.ivory)
                            .frame(width: 32, height: 32)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(IsolynTheme.title(18))
                        .foregroundStyle(IsolynTheme.ivory)
                    Text(option.subtitle)
                        .font(IsolynTheme.caption(12))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }

                Text(option.detail)
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(IsolynTheme.ebonyElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var borderColor: Color {
        if isSelected { return IsolynTheme.brass }
        if isHovering { return IsolynTheme.ivoryMuted }
        return IsolynTheme.ebonyLine
    }
}
