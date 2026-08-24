import SwiftUI

/// A deliberate, honest placeholder -- not a dead end or a blank
/// screen. Used for anything the navigation already leads to but the
/// UI/UX pass hasn't built out yet (Training, Sandbox, the game board
/// itself), so every path through the app today is complete and
/// demoable rather than silently doing nothing.
struct ComingSoonView: View {
    let title: String
    var message: String = "This part of Isolyn hasn't been built yet."
    var onBack: (() -> Void)?

    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Background is `EnvironmentView` behind the screen switcher
            // in `RootView` -- see `EntryView` for the same note. This
            // covers `GamePlaceholderView` too, since it's built on top
            // of this view.

            VStack(spacing: 18) {
                PipGlyph(count: 3, color: IsolynTheme.ivoryMuted)
                    .frame(width: 44, height: 44)

                Text(title)
                    .font(IsolynTheme.title(22))
                    .foregroundStyle(IsolynTheme.ivory)

                Text(message)
                    .font(IsolynTheme.body(14))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .font(IsolynTheme.body(14))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(48)
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let onBack {
                onBack()
            } else {
                appState.screen = .entry
            }
        }
    }
}
