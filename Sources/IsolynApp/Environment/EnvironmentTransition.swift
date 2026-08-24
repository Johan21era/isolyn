import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// A plain, testable RGB color -- deliberately not SwiftUI's `Color`
/// directly, so the interpolation math below can be unit tested with
/// exact numeric assertions from a plain `swift test` run, no UI
/// framework required. Convert to `Color` at the view layer via
/// `swiftUIColor`.
struct EnvironmentColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static func lerp(_ a: EnvironmentColor, _ b: EnvironmentColor, _ t: Double) -> EnvironmentColor {
        EnvironmentColor(
            red: a.red + (b.red - a.red) * t,
            green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t
        )
    }
}

#if canImport(SwiftUI)
extension EnvironmentColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}
#endif

/// The continuously-interpolated visual answer for a moment in the day
/// -- what `AtmosphericBackgroundView` (and later the star field) reads
/// to render, rather than either of them computing time/color math
/// themselves (section 31's architecture rule extended to appearance,
/// not just phase).
struct EnvironmentAppearance: Equatable, Sendable {
    /// Sky gradient, top of screen.
    var skyTop: EnvironmentColor
    /// Sky gradient, bottom of screen (nearer the horizon).
    var skyBottom: EnvironmentColor
    /// 0...1: how visible the star field should be. 0 = fully hidden
    /// (bright daylight), 1 = fully visible (deep night). The star
    /// field renderer itself is later work; this is the value it will
    /// read once it exists.
    var starVisibility: Double
    /// 0...1: a single ambient-brightness scalar, for anything (UI
    /// chrome, contrast decisions) that needs "how bright is it right
    /// now" without reading the gradient directly.
    var ambientLuminance: Double
}

/// One point on the day's continuous appearance curve.
private struct AppearanceKeyframe {
    let minute: Double
    let skyTop: EnvironmentColor
    let skyBottom: EnvironmentColor
    let starVisibility: Double
    let ambientLuminance: Double
}

/// Turns a continuous time-of-day value into a continuous
/// `EnvironmentAppearance` by interpolating between hand-placed
/// keyframes -- this is section 7's "continuous time transitions"
/// requirement (luminance, star visibility, ambient gradients all
/// blending smoothly) and section 21's "Prime Day is a major
/// transition" (16:00 warm daylight -> 18:00 richer late-day -> 19:00
/// noticeable dusk -> 20:00 deep twilight -> 20:30 night), built as one
/// mechanism rather than special-cased per phase.
///
/// The specific RGB values below are a first pass, not a final art
/// pass -- easy to retune once this is actually visible in an Xcode
/// preview or on a real display, which this sandbox has no way to do.
enum EnvironmentAppearanceCurve {
    private static let keyframes: [AppearanceKeyframe] = [
        AppearanceKeyframe(minute: 0,    skyTop: EnvironmentColor(red: 0.03, green: 0.03, blue: 0.050), skyBottom: EnvironmentColor(red: 0.05, green: 0.045, blue: 0.040), starVisibility: 1.00, ambientLuminance: 0.05),
        AppearanceKeyframe(minute: 270,  skyTop: EnvironmentColor(red: 0.03, green: 0.03, blue: 0.055), skyBottom: EnvironmentColor(red: 0.08, green: 0.060, blue: 0.045), starVisibility: 0.95, ambientLuminance: 0.06),
        AppearanceKeyframe(minute: 300,  skyTop: EnvironmentColor(red: 0.10, green: 0.11, blue: 0.160), skyBottom: EnvironmentColor(red: 0.55, green: 0.380, blue: 0.280), starVisibility: 0.25, ambientLuminance: 0.25),
        AppearanceKeyframe(minute: 450,  skyTop: EnvironmentColor(red: 0.35, green: 0.50, blue: 0.680), skyBottom: EnvironmentColor(red: 0.80, green: 0.780, blue: 0.700), starVisibility: 0.00, ambientLuminance: 0.65),
        AppearanceKeyframe(minute: 600,  skyTop: EnvironmentColor(red: 0.38, green: 0.55, blue: 0.720), skyBottom: EnvironmentColor(red: 0.85, green: 0.820, blue: 0.720), starVisibility: 0.00, ambientLuminance: 0.72),
        AppearanceKeyframe(minute: 660,  skyTop: EnvironmentColor(red: 0.40, green: 0.60, blue: 0.780), skyBottom: EnvironmentColor(red: 0.88, green: 0.870, blue: 0.800), starVisibility: 0.00, ambientLuminance: 0.85),
        AppearanceKeyframe(minute: 810,  skyTop: EnvironmentColor(red: 0.38, green: 0.58, blue: 0.760), skyBottom: EnvironmentColor(red: 0.90, green: 0.880, blue: 0.800), starVisibility: 0.00, ambientLuminance: 0.90),
        AppearanceKeyframe(minute: 960,  skyTop: EnvironmentColor(red: 0.42, green: 0.55, blue: 0.700), skyBottom: EnvironmentColor(red: 0.92, green: 0.800, blue: 0.600), starVisibility: 0.00, ambientLuminance: 0.85),
        AppearanceKeyframe(minute: 1080, skyTop: EnvironmentColor(red: 0.35, green: 0.38, blue: 0.520), skyBottom: EnvironmentColor(red: 0.95, green: 0.650, blue: 0.400), starVisibility: 0.00, ambientLuminance: 0.70),
        AppearanceKeyframe(minute: 1140, skyTop: EnvironmentColor(red: 0.18, green: 0.18, blue: 0.300), skyBottom: EnvironmentColor(red: 0.80, green: 0.420, blue: 0.320), starVisibility: 0.15, ambientLuminance: 0.45),
        AppearanceKeyframe(minute: 1200, skyTop: EnvironmentColor(red: 0.06, green: 0.06, blue: 0.120), skyBottom: EnvironmentColor(red: 0.35, green: 0.200, blue: 0.220), starVisibility: 0.60, ambientLuminance: 0.20),
        AppearanceKeyframe(minute: 1230, skyTop: EnvironmentColor(red: 0.03, green: 0.03, blue: 0.055), skyBottom: EnvironmentColor(red: 0.09, green: 0.060, blue: 0.050), starVisibility: 0.90, ambientLuminance: 0.08),
    ]

    /// The continuously-interpolated appearance for any point in the
    /// day, including values outside `0..<1440` (wrapped automatically).
    /// Blends smoothly from the last keyframe (20:30) through the rest
    /// of the night back to the first (00:00), rather than treating
    /// midnight as a hard reset.
    static func appearance(atMinute minute: Double) -> EnvironmentAppearance {
        let remainder = minute.truncatingRemainder(dividingBy: 1440)
        let m = remainder < 0 ? remainder + 1440 : remainder

        var lower = keyframes[0]
        var upper = keyframes[0]
        var lowerMinute = 0.0
        var upperMinute = 1440.0

        for i in 0..<keyframes.count {
            let current = keyframes[i]
            let next = keyframes[(i + 1) % keyframes.count]
            let nextMinute = (i == keyframes.count - 1) ? next.minute + 1440 : next.minute
            if m >= current.minute && m < nextMinute {
                lower = current
                upper = next
                lowerMinute = current.minute
                upperMinute = nextMinute
                break
            }
        }

        let span = upperMinute - lowerMinute
        let rawT = span > 0 ? (m - lowerMinute) / span : 0
        let t = smoothstep(rawT)

        return EnvironmentAppearance(
            skyTop: EnvironmentColor.lerp(lower.skyTop, upper.skyTop, t),
            skyBottom: EnvironmentColor.lerp(lower.skyBottom, upper.skyBottom, t),
            starVisibility: lower.starVisibility + (upper.starVisibility - lower.starVisibility) * t,
            ambientLuminance: lower.ambientLuminance + (upper.ambientLuminance - lower.ambientLuminance) * t
        )
    }

    /// Smooth, restrained easing (Hermite/smoothstep) rather than
    /// linear -- per the prompt's explicit instruction to avoid
    /// anything that reads as a flashy crossfade.
    private static func smoothstep(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

extension EnvironmentAppearanceCurve {
    /// The full, composited appearance: time-of-day as the base (via
    /// `appearance(atMinute:)`), then weather applied on top -- per the
    /// prompt's explicit requirement that weather *modifies* the time
    /// environment rather than sitting as an independent second state.
    /// `.clear` returns the base appearance untouched.
    static func composite(atMinute minute: Double, condition: SkyCondition) -> EnvironmentAppearance {
        var result = appearance(atMinute: minute)
        switch condition {
        case .clear:
            break
        case .cloudy:
            result.starVisibility *= 0.35
            result.ambientLuminance *= 0.92
            result = tinted(result, toward: EnvironmentColor(red: 0.50, green: 0.52, blue: 0.55), amount: 0.15)
        case .rain:
            result.starVisibility *= 0.15
            result.ambientLuminance *= 0.80
            result = tinted(result, toward: EnvironmentColor(red: 0.30, green: 0.34, blue: 0.40), amount: 0.30)
        case .snow:
            result.starVisibility *= 0.25
            result.ambientLuminance *= 0.90
            result = tinted(result, toward: EnvironmentColor(red: 0.75, green: 0.78, blue: 0.85), amount: 0.20)
        case .fog:
            result.starVisibility *= 0.10
            result.ambientLuminance = result.ambientLuminance * 0.6 + 0.25
            result = tinted(result, toward: EnvironmentColor(red: 0.55, green: 0.55, blue: 0.55), amount: 0.35)
        }
        result.starVisibility = min(max(result.starVisibility, 0), 1)
        result.ambientLuminance = min(max(result.ambientLuminance, 0), 1)
        return result
    }

    private static func tinted(_ appearance: EnvironmentAppearance, toward color: EnvironmentColor, amount: Double) -> EnvironmentAppearance {
        var result = appearance
        result.skyTop = EnvironmentColor.lerp(appearance.skyTop, color, amount)
        result.skyBottom = EnvironmentColor.lerp(appearance.skyBottom, color, amount)
        return result
    }
}
