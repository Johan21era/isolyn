import SwiftUI

@main
struct IsolynApp: App {
    @State private var appState = AppState()
    @State private var environmentManager = EnvironmentManager()

    public init() {}

    public var body: some Scene {
        WindowGroup("Isolyn") {
            RootView()
                .environment(appState)
                .environment(environmentManager)
                .frame(minWidth: 900, minHeight: 620)
                .background(IsolynTheme.ebony)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)

        // FIX-26b (roadmap 5b): ends the audit's oldest "wire-or-remove
        // limbo". EnvironmentSettingsView was compiled-but-unreachable
        // since batch 5 -- no screen referenced it and no placement
        // decision had been made. Decision: it lives in the platform-
        // standard Settings scene (Cmd-,) with the manager injected,
        // exactly as the audit recommended. Reachable from any screen.
        Settings {
            EnvironmentSettingsView()
                .environment(environmentManager)
                .frame(width: 380)
        }
    }
}
