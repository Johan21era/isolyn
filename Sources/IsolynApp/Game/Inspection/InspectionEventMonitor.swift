import AppKit
import SwiftUI

extension InspectionMouseButton {
    /// Right and other mouse buttons share the same matching policy here, so
    /// the settings picker and the event monitor cannot drift apart.
    func matches(eventType: NSEvent.EventType, buttonNumber: Int) -> Bool {
        switch self {
        case .right:
            return eventType == .rightMouseDown
        case .middle:
            return eventType == .otherMouseDown && buttonNumber == 2
        case .extra:
            return eventType == .otherMouseDown && buttonNumber > 2
        }
    }
}

/// A zero-size AppKit hook that catches only the configured inspection
/// button while the pointer is over a domino. It never claims left clicks,
/// so selecting and playing tiles keeps its normal path through SwiftUI.
struct InspectionEventMonitor: NSViewRepresentable {
    let button: InspectionMouseButton
    let tracker: InspectionHoverTracker
    let onInspect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        context.coordinator.start(view: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.button = button
        context.coordinator.tracker = tracker
        context.coordinator.onInspect = onInspect
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// The monitor itself must never participate in hit-testing: it exists
    /// only to observe the app's mouse events. Left clicks and bare board
    /// clicks continue to reach SwiftUI exactly as before.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        var button: InspectionMouseButton = .right
        var tracker: InspectionHoverTracker?
        var onInspect: ((Int) -> Void)?

        private var monitor: Any?
        private weak var view: NSView?

        func start(view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            view = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window = view?.window,
                  event.window === window,
                  let face = tracker?.face,
                  button.matches(eventType: event.type, buttonNumber: event.buttonNumber)
            else { return event }

            onInspect?(face)
            return nil
        }
    }
}
