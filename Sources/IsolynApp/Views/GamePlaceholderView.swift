import SwiftUI

/// Where a chosen `MatchFormat` currently leads. The actual board --
/// tile rendering, the chain, drag-and-drop play -- is its own large
/// piece of work, deliberately not started in this UI/UX pass. This
/// screen exists so a full "entry -> mode select -> game" pass through
/// the app is real and clickable today, not a dead end after Start.
struct GamePlaceholderView: View {
    let format: MatchFormat

    @Environment(AppState.self) private var appState

    var body: some View {
        ComingSoonView(
            title: title,
            message: "The board itself is next. This screen exists so the format you picked carries all the way through.",
            onBack: { appState.screen = .modeSelect }
        )
    }

    private var title: String {
        switch format {
        case .oneVOne: return "Head to Head"
        case .oneVOneVOne: return "Three-Way"
        case .twoVTwo: return "Partners"
        }
    }
}
