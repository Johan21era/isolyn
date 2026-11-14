import SwiftUI

/// The very first thing a player sees. Deliberately quiet: the
/// wordmark, one clear primary action, and two lower-emphasis paths
/// into the more specialized modes from `docs/architecture/FEATURE_SPECS.md` --
/// nothing competes with "Play."
struct EntryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { proxy in
            let watermarkSide = min(proxy.size.width, proxy.size.height) * 1.08

            ZStack {
                // A centered watermark, not an off-screen decoration. On a
                // wide display it stays behind the wordmark and keeps the
                // screen balanced instead of pulling the eye to an edge.
                PipGlyph(count: 6, color: IsolynTheme.ivory.opacity(0.032))
                    .frame(width: watermarkSide, height: watermarkSide)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    VStack(spacing: 30) {
                        VStack(spacing: 12) {
                            Text("ISOLYN")
                                .font(IsolynTheme.display(56))
                                .tracking(7)
                                .foregroundStyle(IsolynTheme.ivory)

                            Text("A game of memory, math, and misdirection.")
                                .font(IsolynTheme.body(16))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 16) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    appState.screen = .modeSelect
                                }
                            } label: {
                                Text("Play")
                            }
                            .buttonStyle(PrimaryCapsuleButtonStyle(minWidth: 240))

                            HStack(spacing: 28) {
                                secondaryLink("Lab") {
                                    appState.screen = .lab
                                }
                                secondaryLink("Sandbox") {
                                    appState.screen = .comingSoon("Sandbox")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func secondaryLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
