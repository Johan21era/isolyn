import AppKit
import XCTest
@testable import IsolynApp

/// Guards the failure the owner hit: the yellow button leaves a running process
/// whose window cannot be reached again.
@MainActor
final class WindowRestorationTests: XCTestCase {

    final class FakeWindow: RestorableWindow {
        var isMiniaturized = true
        var isVisible = false
        var canBecomeMain = true
        var isExcludedFromWindowsMenu = false
        private(set) var deminiaturized = false
        private(set) var orderedFront = false

        func deminiaturize(_ sender: Any?) {
            deminiaturized = true
            isMiniaturized = false
            isVisible = true
        }

        func makeKeyAndOrderFront(_ sender: Any?) {
            orderedFront = true
            isVisible = true
        }
    }

    func test_miniaturizedWindowIsNotConsideredVisible() {
        let window = FakeWindow()
        XCTAssertTrue(window.isMiniaturized)
        XCTAssertFalse(WindowRestoration.hasVisibleWindow([window]))
    }

    func test_restoringDeminiaturizesAndOrdersTheWindowFront() {
        let window = FakeWindow()

        XCTAssertTrue(WindowRestoration.restore(windows: [window]))

        XCTAssertTrue(window.deminiaturized, "makeKeyAndOrderFront alone does not unminimize")
        XCTAssertTrue(window.orderedFront)
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertTrue(WindowRestoration.hasVisibleWindow([window]))
    }

    func test_restoreIsANoOpWithNoWindows() {
        let windows: [FakeWindow] = []
        XCTAssertFalse(WindowRestoration.restore(windows: windows))
        XCTAssertFalse(WindowRestoration.hasVisibleWindow(windows))
    }

    func test_alreadyVisibleWindowIsLeftOpenAndBroughtForward() {
        let window = FakeWindow()
        window.isMiniaturized = false
        window.isVisible = true

        XCTAssertTrue(WindowRestoration.restore(windows: [window]))
        XCTAssertFalse(window.deminiaturized)
        XCTAssertTrue(window.orderedFront)
    }

    func test_panelsAndTransientWindowsAreNotRestored() {
        let panel = FakeWindow()
        panel.isExcludedFromWindowsMenu = true

        XCTAssertFalse(WindowRestoration.restore(windows: [panel]))
        XCTAssertFalse(panel.deminiaturized)
    }

    func test_restoringPutsOneWindowOnScreenWhenSeveralExist() {
        let minimized = FakeWindow()
        let open = FakeWindow()
        open.isMiniaturized = false
        open.isVisible = true

        XCTAssertTrue(WindowRestoration.restore(windows: [minimized, open]))
        XCTAssertTrue(minimized.deminiaturized, "every miniaturized window comes back")
        XCTAssertTrue(open.isVisible)
        XCTAssertTrue(
            minimized.orderedFront || open.orderedFront,
            "one of the restored windows is brought forward"
        )
    }
}
