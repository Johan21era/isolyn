import Foundation

/// The board tile currently under the pointer. A reference type keeps
/// pointer tracking out of SwiftUI state, so moving across a domino does not
/// recompute the chain layout or re-render every tile.
@MainActor
final class InspectionHoverTracker {
    private(set) var tileIndex: Int?
    private(set) var face: Int?

    func set(index: Int, face: Int) {
        tileIndex = index
        self.face = face
    }

    func clear(index: Int) {
        guard tileIndex == index else { return }
        clearAll()
    }

    func clearAll() {
        tileIndex = nil
        face = nil
    }
}
