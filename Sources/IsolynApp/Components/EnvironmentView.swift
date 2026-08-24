import SwiftUI

/// The complete environment, correctly layered: atmosphere, then stars,
/// then weather particles on top -- all reading the same weather-
/// composited appearance (`EnvironmentAppearanceCurve.composite`), so
/// e.g. "night + rain" is a genuinely different look from "night +
/// clear," not two independent layers that happen to overlap. Drop this
/// in as the background behind any screen; it never intercepts input.
struct EnvironmentView: View {
    var body: some View {
        ZStack {
            AtmosphericBackgroundView()
            StarFieldView()
            WeatherEffectView()
            LegibilityScrim()
        }
        .allowsHitTesting(false)
    }
}

/// A dark scrim, strength tied to `ambientLuminance`, so existing
/// ivory-on-dark UI (`IsolynTheme.ivory` is `(0.949, 0.925, 0.867)` --
/// nearly white) stays legible against a background that swings from
/// near-black at night to near-white at midday. Minimal at night, since
/// the environment is already dark there and should read at full
/// strength as the "hero" moment; much stronger by day, deliberately
/// trading some daytime vividness for keeping every existing screen's
/// text readable without touching that screen's own colors.
///
/// Calibrated from the actual theme values, not guessed, but this is a
/// first pass -- worth eyeballing once it's on screen and adjusting the
/// two constants below if it reads too heavy or too thin.
private struct LegibilityScrim: View {
    @Environment(EnvironmentManager.self) private var environmentManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let luminance = EnvironmentAppearanceCurve.composite(
            atMinute: environmentManager.state.timeOfDayMinutes,
            condition: environmentManager.currentSkyCondition
        ).ambientLuminance

        let opacity = min(0.10 + luminance * 0.85, 0.92)

        Color.black
            .opacity(opacity)
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: opacity)
    }
}

@MainActor private func previewManager(hour: Int, minute: Int = 0, condition: SkyCondition?) -> EnvironmentManager {
    EnvironmentManager(
        clock: FixedEnvironmentClock(
            fixedNow: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now,
            fixedTimeZone: .current
        ),
        weatherMode: .randomized,
        weatherSource: FixedWeatherSource(condition: condition)
    )
}

#Preview("Night, clear") {
    EnvironmentView()
        .environment(previewManager(hour: 23, condition: .clear))
        .frame(width: 500, height: 360)
}

#Preview("Night, rain") {
    EnvironmentView()
        .environment(previewManager(hour: 23, condition: .rain))
        .frame(width: 500, height: 360)
}

#Preview("Night, snow") {
    EnvironmentView()
        .environment(previewManager(hour: 23, condition: .snow))
        .frame(width: 500, height: 360)
}

#Preview("Prime Day dusk, fog") {
    EnvironmentView()
        .environment(previewManager(hour: 19, condition: .fog))
        .frame(width: 500, height: 360)
}

#Preview("Midday, cloudy") {
    EnvironmentView()
        .environment(previewManager(hour: 13, condition: .cloudy))
        .frame(width: 500, height: 360)
}
