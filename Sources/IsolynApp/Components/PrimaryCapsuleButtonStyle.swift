import SwiftUI

/// The single recurring shape for a primary, filled action across the
/// app -- a capsule filled with the brass accent. Used sparingly and
/// consistently: "Play" on the entry screen, "Start" on the mode
/// selector, and nowhere else, since the accent only means something if
/// it stays rare.
///
/// Reads `isEnabled` from the environment rather than taking it as a
/// parameter, so a plain `.disabled(...)` on the button is all that's
/// ever needed to keep the visual state in sync.
struct PrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IsolynTheme.title(16))
            .foregroundStyle(isEnabled ? IsolynTheme.ebony : IsolynTheme.ivoryMuted)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(isEnabled ? IsolynTheme.brass : IsolynTheme.ebonyElevated)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
