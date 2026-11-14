import AppKit

/// The window operations restoration needs, so the behaviour can be tested
/// without depending on a GUI session's focus and animation timing.
protocol RestorableWindow: AnyObject {
    var isMiniaturized: Bool { get }
    var isVisible: Bool { get }
    var canBecomeMain: Bool { get }
    var isExcludedFromWindowsMenu: Bool { get }
    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: RestorableWindow {}

/// Restores the app's window when it is miniaturized.
///
/// Why this exists: a plain SwiftUI `WindowGroup` in a hand-wrapped `.app` does
/// not reliably deminiaturize on Dock reopen. Clicking the yellow button then
/// leaves a running process with no way back to its window except Force Quit.
/// Restoring is deliberately explicit — deminiaturize first, then order front —
/// because `makeKeyAndOrderFront` alone does nothing for a miniaturized window.
enum WindowRestoration {
    /// The windows worth restoring: real document windows, not panels or
    /// transient popovers.
    private static func candidates<W: RestorableWindow>(_ windows: [W]) -> [W] {
        windows.filter { $0.canBecomeMain && !$0.isExcludedFromWindowsMenu }
    }

    static func hasVisibleWindow<W: RestorableWindow>(_ windows: [W]) -> Bool {
        candidates(windows).contains { $0.isVisible && !$0.isMiniaturized }
    }

    /// Brings back every miniaturized window and puts one on screen.
    /// - Returns: true if there was a window to restore.
    @discardableResult
    static func restore<W: RestorableWindow>(windows: [W]) -> Bool {
        let windows = candidates(windows)
        guard !windows.isEmpty else { return false }

        for window in windows where window.isMiniaturized {
            window.deminiaturize(nil)
        }

        let target = windows.first { $0.isVisible && !$0.isMiniaturized }
            ?? windows.first { !$0.isMiniaturized }
            ?? windows[0]
        target.makeKeyAndOrderFront(nil)
        return true
    }
}

final class IsolynAppDelegate: NSObject, NSApplicationDelegate {
    /// Called when the Dock icon is clicked, or when `open` targets an app that
    /// is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowRestoration.restore(windows: sender.windows)
        }
        return true
    }

    /// Cmd-Tab or a Dock click can activate an app whose only window is
    /// miniaturized. In that case there is nothing visible to interact with, so
    /// bring the window back rather than leaving a blank active app.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard let app = notification.object as? NSApplication else { return }
        if !WindowRestoration.hasVisibleWindow(app.windows) {
            WindowRestoration.restore(windows: app.windows)
        }
    }
}
