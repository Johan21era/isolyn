import Foundation

/// How the app decides what the weather is. Three modes: live (real
/// WeatherKit data for the user's location), randomized (no location or
/// network needed), and off (no weather layer at all).
enum WeatherMode: String, CaseIterable, Sendable, Equatable, Hashable {
    case live
    case randomized
    case off
}

/// Anything that can answer "what's the sky condition right now."
/// `LiveWeatherService` (WeatherKit) and `RandomWeatherService` (no
/// dependencies) both conform; `EnvironmentManager` holds whichever
/// matches the current `WeatherMode` and doesn't otherwise care which
/// it's talking to. `nil` means "couldn't determine a condition" (no
/// permission, no network, no signal yet) -- callers fall back to
/// leaving the last known condition in place rather than propagating an
/// error through the whole view hierarchy.
protocol WeatherSource: Sendable {
    func currentCondition() async -> SkyCondition?
}

extension WeatherMode {
    var displayName: String {
        switch self {
        case .live: return "Live"
        case .randomized: return "Randomized"
        case .off: return "Off"
        }
    }
}

/// Always returns the same condition. Useful for previews and anywhere
/// else a specific weather needs to be demonstrated without waiting for
/// `RandomWeatherService`'s cycle to land on it.
struct FixedWeatherSource: WeatherSource {
    let condition: SkyCondition?
    func currentCondition() async -> SkyCondition? { condition }
}
