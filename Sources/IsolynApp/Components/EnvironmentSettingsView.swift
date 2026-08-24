import SwiftUI

/// The controls the quality gate calls for: weather can be switched
/// off, random weather can be enabled. Small and focused, not a general
/// preferences screen.
struct EnvironmentSettingsView: View {
    @Environment(EnvironmentManager.self) private var environmentManager

    var body: some View {
        Form {
            Section("Weather") {
                Picker("Source", selection: Binding(
                    get: { environmentManager.weatherMode },
                    set: { environmentManager.setWeatherMode($0) }
                )) {
                    ForEach(WeatherMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if environmentManager.weatherMode != .off {
                    LabeledContent("Current condition", value: environmentManager.currentSkyCondition.displayName)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 160)
    }
}

#Preview("Environment settings") {
    EnvironmentSettingsView()
        .environment(EnvironmentManager())
}
