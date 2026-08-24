import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit

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
///
/// FIX-15 (audit F-04): this type previously declared itself
/// `@unchecked Sendable` while mutating `lastKnownGood` from whatever
/// executor called `currentCondition()` -- the compiler stayed silent,
/// which is exactly what `@unchecked` means. The cache is now guarded
/// by an internal NSLock, so the Sendable claim is earned by the lock
/// rather than asserted over bare mutable state. (Production callers
/// are MainActor-confined via EnvironmentManager as of FIX-15; the
/// lock keeps the type honest for any future non-confined caller.)
final class LiveWeatherService: WeatherSource, @unchecked Sendable {
    private let weatherService: WeatherService
    private let locationProvider: @Sendable () -> CLLocation?
    private let cacheLock = NSLock()
    private var lastKnownGoodStorage: SkyCondition?

    /// Lock-guarded view of the cached condition. Never touch
    /// `lastKnownGoodStorage` directly.
    private var lastKnownGood: SkyCondition? {
        get { cacheLock.withLock { lastKnownGoodStorage } }
        set { cacheLock.withLock { lastKnownGoodStorage = newValue } }
    }

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
