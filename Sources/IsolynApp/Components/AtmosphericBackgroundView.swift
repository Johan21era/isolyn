import SwiftUI

/// Renders the full-bleed sky gradient behind everything else in the
/// app, continuously reflecting `EnvironmentManager`'s current state.
/// Purely presentational -- reads a resolved `EnvironmentAppearance`,
/// computes nothing about time or phase itself (section 31's
/// architecture rule: views ask, they don't calculate).
struct AtmosphericBackgroundView: View {
    @Environment(EnvironmentManager.self) private var environmentManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let appearance = EnvironmentAppearanceCurve.composite(
            atMinute: environmentManager.state.timeOfDayMinutes,
            condition: environmentManager.currentSkyCondition
        )

        LinearGradient(
            colors: [appearance.skyTop.swiftUIColor, appearance.skyBottom.swiftUIColor],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: appearance)
    }
}

#Preview("Live") {
    AtmosphericBackgroundView()
        .environment(EnvironmentManager())
        .frame(width: 500, height: 360)
}

#Preview("Day progression") {
    // A quick visual sanity strip across the keyframes, so the color
    // story can be judged in the canvas without touching the system
    // clock. Not a substitute for seeing it full-screen, but a fast
    // first look.
    let minutes: [Double] = [0, 270, 300, 450, 600, 660, 810, 960, 1080, 1140, 1200, 1230]
    return HStack(spacing: 0) {
        ForEach(minutes, id: \.self) { minute in
            let appearance = EnvironmentAppearanceCurve.appearance(atMinute: minute)
            LinearGradient(
                colors: [appearance.skyTop.swiftUIColor, appearance.skyBottom.swiftUIColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    .frame(height: 220)
}
