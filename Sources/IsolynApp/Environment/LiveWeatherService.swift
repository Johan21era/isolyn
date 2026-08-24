import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

#if canImport(WeatherKit)
/// Real weather via Apple's WeatherKit, for whatever location
/// `locationProvider` returns. Needs the WeatherKit capability enabled
/// in Signing & Capabilities, and location permission if the default
/// provider is used.
///
/// Caches the last successful condition and returns that on failure (no
/// location, no network, WeatherKit error) instead of `nil` -- section
/// 16 wants weather to degrade gracefully rather than blank out on one
/// bad fetch. A `nil` result now only means "never successfully fetched
/// anything yet," not "this particular fetch failed."
final class LiveWeatherService: WeatherSource, @unchecked Sendable {
    private let weatherService: WeatherService
    private let locationProvider: @Sendable () -> CLLocation?
    private var lastKnownGood: SkyCondition?

    init(weatherService: WeatherService = .shared,
         locationProvider: @escaping @Sendable () -> CLLocation? = { CLLocationManager().location }) {
        self.weatherService = weatherService
        self.locationProvider = locationProvider
    }

    func currentCondition() async -> SkyCondition? {
        guard let location = locationProvider() else { return lastKnownGood }
        do {
            let weather = try await weatherService.weather(for: location)
            let condition = Self.map(weather.currentWeather.condition)
            lastKnownGood = condition
            return condition
        } catch {
            return lastKnownGood
        }
    }

    private static func map(_ condition: WeatherCondition) -> SkyCondition {
        switch condition {
        case .clear, .mostlyClear:
            return .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy:
            return .cloudy
        case .rain, .drizzle, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .thunderstorms, .tropicalStorm, .hurricane:
            return .rain
        case .snow, .flurries, .heavySnow, .blizzard, .blowingSnow, .freezingRain,
             .freezingDrizzle, .sleet, .wintryMix, .hail:
            return .snow
        default:
            return .fog
        }
    }
}
#endif
