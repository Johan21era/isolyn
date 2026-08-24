import SwiftUI

/// Swaps between full-screen states based on `AppState.screen`. A plain
/// switch inside a ViewBuilder context, not a NavigationStack -- each
/// screen here is a distinct, full-window experience rather than a
/// page pushed onto a stack, which is the more natural fit for a
/// desktop game's entry/menu flow.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Persists continuously behind every screen rather than
            // being part of the switch below, so it doesn't reset or
            // refade every time the screen changes -- the environment
            // is one continuous world, navigation just moves through it.
            EnvironmentView()

            Group {
                switch appState.screen {
                case .entry:
                    EntryView()
                case .modeSelect:
                    ModeSelectorView()
                case .game(let format):
                    InteractiveGameBoardView(format: format)
                case .comingSoon(let title):
                    ComingSoonView(title: title)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}
