import SwiftUI
import Observation

/// The three supported match formats, from the UI's point of view.
///
/// Deliberately a separate, pure-Swift enum for now -- NOT yet the real
/// `isolyn::GameMode` bridged from the C++ engine. Wiring this screen
/// layer to the actual engine (enabling Swift/C++ interop on this
/// target, mapping this enum onto `isolyn::GameMode`) is exactly the
/// kind of technical work meant to come AFTER the UI/UX pass, not
/// during it. Mapping the two is a small, well-contained step once
/// that's back on the table.
enum MatchFormat: String, Identifiable, Equatable {
    case oneVOne = "1v1"
    case oneVOneVOne = "1v1v1"
    case twoVTwo = "2v2"

    var id: String { rawValue }
}

/// The app's single navigation state. One root observable object, owned
/// by `IsolynApp` and read by every screen via `@Environment` -- no
/// separate navigation stack per screen, since this app is a sequence
/// of full, distinct screens (entry -> mode select -> game) rather than
/// a push/pop hierarchy.
@Observable
final class AppState {
    enum Screen: Equatable {
        case entry
        case modeSelect
        case game(MatchFormat, OpponentMode, AILevel)
        case comingSoon(String)
    }

    var screen: Screen = .entry
}
