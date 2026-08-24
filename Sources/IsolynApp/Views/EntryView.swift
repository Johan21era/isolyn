import SwiftUI

/// The very first thing a player sees. Deliberately quiet: the
/// wordmark, one clear primary action, and two lower-emphasis paths
/// into the more specialized modes from `docs/FEATURE_SPECS.md` --
/// nothing competes with "Play."
struct EntryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Background is `EnvironmentView`, rendered once behind the
            // screen switcher in `RootView`. This used to be a flat
            // `IsolynTheme.ebony.ignoresSafeArea()` fill here; the
            // legibility scrim built into `EnvironmentView` is what now
            // keeps the ivory text below readable against it.

            // The signature element: an oversized, almost-invisible
            // six-pip watermark, off-center and partially cropped --
            // texture and atmosphere, not a competing visual.
            GeometryReader { geo in
                PipGlyph(count: 6, color: IsolynTheme.ivory.opacity(0.035))
                    .frame(width: geo.size.height * 1.1, height: geo.size.height * 1.1)
                    .position(x: geo.size.width * 0.86, y: geo.size.height * 0.92)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text("ISOLYN")
                        .font(IsolynTheme.display(60))
                        .tracking(4)
                        .foregroundStyle(IsolynTheme.ivory)

                    Text("A game of memory, math, and misdirection.")
                        .font(IsolynTheme.body(16))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 64)

                Spacer().frame(height: 48)

                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            appState.screen = .modeSelect
                        }
                    } label: {
                        Text("Play")
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle())

                    HStack(spacing: 24) {
                        secondaryLink("Training") {
                            appState.screen = .comingSoon("Training")
                        }
                        secondaryLink("Sandbox") {
                            appState.screen = .comingSoon("Sandbox")
                        }
                    }
                }
                .padding(.horizontal, 64)

                Spacer()
                Spacer()
            }
        }
    }

    private func secondaryLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        }
        .buttonStyle(.plain)
    }
}
