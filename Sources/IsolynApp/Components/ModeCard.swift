import SwiftUI

/// One selectable entry on the simplified match-setup screen.
struct ModeOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

/// A compact mode choice. The whole card is the button; selected state is a
/// single bright rule, not a second control.
struct ModeCard: View {
    let option: ModeOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(option.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(IsolynTheme.ivory)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(IsolynTheme.ivory)
                            .transition(.opacity)
                    }
                }

                Text(option.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.06 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.25 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var borderColor: Color {
        if isSelected { return Color.white.opacity(0.8) }
        if isHovering { return Color.white.opacity(0.28) }
        return Color.white.opacity(0.1)
    }
}
