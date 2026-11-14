import SwiftUI

@main
struct IsolynApp: App {
    @NSApplicationDelegateAdaptor(IsolynAppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var environmentManager = EnvironmentManager()
    // Owned at app scope so a run keeps its handle while the owner moves
    // between screens; a per-view service would lose the ability to stop it.
    @State private var labService = LabService()
    @State private var analysisService = LabAnalysisService()
    @State private var labEstimator = LabEstimator()

    public init() {}

    public var body: some Scene {
        WindowGroup("IsolynV2.0") {
            RootView()
                .environment(appState)
                .environment(environmentManager)
                .environment(labService)
                .environment(analysisService)
                .environment(labEstimator)
                .frame(minWidth: IsolynLayout.minWindowWidth,
                       minHeight: IsolynLayout.minWindowHeight)
                .background(IsolynTheme.ebony)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .windowList) {
                Button("Show Isolyn Window") {
                    WindowRestoration.restore(windows: NSApp.windows)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

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
