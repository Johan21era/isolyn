import Foundation

/// The set of weather conditions the environment can render. Small and
/// renderer-oriented -- what does the sky/effects layer actually need
/// to draw differently -- rather than mirroring WeatherKit's own, much
/// larger condition enum one-to-one. Named `SkyCondition` rather than
/// `WeatherCondition` specifically to avoid colliding with WeatherKit's
/// own `WeatherCondition` type once that framework is imported
/// (see `LiveWeatherService.swift`).
enum SkyCondition: String, CaseIterable, Sendable, Equatable, Hashable {
    case clear
    case cloudy
    case rain
    case snow
    case fog

    var displayName: String {
        switch self {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .fog: return "Fog"
        }
    }
}
