import SwiftUI
import Observation

/// Classifies every pointer interaction on the board into exactly one
/// authoritative gesture owner. Once classified, the owner holds the pointer
/// until release — no competing gesture may steal it mid-flight.
///
/// State machine:
/// ```
/// idle
///   → pointerDown
///     ├─ small movement + release → tap
///     ├─ movement past threshold (on board bg) → boardPan
///     └─ movement past threshold (on domino) → dominoInteraction
/// ```
@MainActor
@Observable
final class GestureArbiter {

    enum GestureOwner: Equatable {
        case idle
        case pending        // pointer down, not yet classified
        case boardPan       // confirmed: camera owns this drag
        case dominoDrag     // confirmed: domino interaction owns this drag
    }

    private(set) var owner: GestureOwner = .idle

    /// The screen-space point where the current gesture began.
    private(set) var startPoint: CGPoint = .zero

    /// Centralized threshold — the minimum distance before a press becomes a drag.
    static let classificationThreshold: CGFloat = 6

    /// Called when the user presses anywhere on the board.
    func pointerDown(at location: CGPoint) {
        owner = .pending
        startPoint = location
    }

    /// Called on pointer movement while a gesture is active.
    /// Returns true if the gesture was just classified (first time past threshold).
    @discardableResult
    func pointerMoved(to location: CGPoint, targetIsDomino: Bool) -> Bool {
        guard owner == .pending else { return false }
        let dx = location.x - startPoint.x
        let dy = location.y - startPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist >= Self.classificationThreshold else { return false }

        // Classification is now permanent for this gesture.
        owner = targetIsDomino ? .dominoDrag : .boardPan
        return true
    }

    /// Called when the pointer is released.
    /// Returns true if this was a TAP (down→up without passing threshold).
    func pointerUp() -> Bool {
        let wasTap = (owner == .pending)
        owner = .idle
        return wasTap
    }

    /// Force-cancel any in-flight gesture (e.g. settings drawer opened).
    func cancel() {
        owner = .idle
    }

    var isDragging: Bool { owner == .boardPan || owner == .dominoDrag }
    var isBoardPanning: Bool { owner == .boardPan }
}
