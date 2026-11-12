import XCTest
import AppKit
@testable import IsolynApp

@MainActor
final class InspectionTests: XCTestCase {
    func test_rightButton_only_matchesRightMouseDown() {
        XCTAssertTrue(InspectionMouseButton.right.matches(eventType: .rightMouseDown, buttonNumber: 1))
        XCTAssertFalse(InspectionMouseButton.right.matches(eventType: .leftMouseDown, buttonNumber: 0))
        XCTAssertFalse(InspectionMouseButton.right.matches(eventType: .otherMouseDown, buttonNumber: 2))
    }

    func test_middleButton_requiresButtonTwo() {
        XCTAssertTrue(InspectionMouseButton.middle.matches(eventType: .otherMouseDown, buttonNumber: 2))
        XCTAssertFalse(InspectionMouseButton.middle.matches(eventType: .otherMouseDown, buttonNumber: 3))
        XCTAssertFalse(InspectionMouseButton.middle.matches(eventType: .rightMouseDown, buttonNumber: 1))
    }

    func test_extraButton_matchesHigherButtons() {
        XCTAssertTrue(InspectionMouseButton.extra.matches(eventType: .otherMouseDown, buttonNumber: 3))
        XCTAssertTrue(InspectionMouseButton.extra.matches(eventType: .otherMouseDown, buttonNumber: 4))
        XCTAssertFalse(InspectionMouseButton.extra.matches(eventType: .otherMouseDown, buttonNumber: 2))
    }

    func test_hoverTracker_tracksFace_andClearsOnlyItsTile() {
        let tracker = InspectionHoverTracker()
        tracker.set(index: 2, face: 4)
        XCTAssertEqual(tracker.tileIndex, 2)
        XCTAssertEqual(tracker.face, 4)

        tracker.clear(index: 1)
        XCTAssertEqual(tracker.face, 4, "A stale tile must not clear the active tile's face")

        tracker.clear(index: 2)
        XCTAssertNil(tracker.tileIndex)
        XCTAssertNil(tracker.face)
    }

    func test_hoverTracker_faceChangesWithinTile() {
        let tracker = InspectionHoverTracker()
        tracker.set(index: 0, face: 3)
        tracker.set(index: 0, face: 5)
        XCTAssertEqual(tracker.face, 5)
    }

    func test_eventMonitor_consumesRightClick_whenTileIsHovered() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let monitorView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView = monitorView
        window.makeKeyAndOrderFront(nil)

        let tracker = InspectionHoverTracker()
        tracker.set(index: 0, face: 4)
        let coordinator = InspectionEventMonitor.Coordinator()
        coordinator.start(view: monitorView)
        coordinator.button = .right
        coordinator.tracker = tracker
        var inspected: [Int] = []
        coordinator.onInspect = { inspected.append($0) }

        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        NSApp.sendEvent(event)
        XCTAssertEqual(inspected, [4])

        coordinator.stop()
        window.close()
    }
}
