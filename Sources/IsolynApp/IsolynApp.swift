import SwiftUI

@main
struct IsolynApp: App {
    @State private var appState = AppState()
    @State private var environmentManager = EnvironmentManager()

    var body: some Scene {
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
    }
}
