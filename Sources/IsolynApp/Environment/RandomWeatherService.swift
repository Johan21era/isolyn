import Foundation

/// A weather source needing no network, no location, no entitlements --
/// cycles through conditions over time so there's always *something* to
/// look at. Useful for development/previews, and a legitimate mode a
/// user might deliberately pick over live weather.
final class RandomWeatherService: WeatherSource {
    private let clock: EnvironmentClock
    private let cycleMinutes: Double

    init(clock: EnvironmentClock = SystemEnvironmentClock(), cycleMinutes: Double = 45) {
        self.clock = clock
        self.cycleMinutes = cycleMinutes
    }

    func currentCondition() async -> SkyCondition? {
        // Deterministic given the clock, not truly random per call --
        // which "cycle window" we're in decides the seed, so the
        // condition is stable for `cycleMinutes` at a stretch instead
        // of flickering between calls a second apart.
        let now = clock.now()
        let cycleIndex = Int64(now.timeIntervalSinceReferenceDate / (cycleMinutes * 60))
        var rng = SeededGenerator(seed: UInt64(bitPattern: cycleIndex))
        return SkyCondition.allCases.randomElement(using: &rng)
    }
}
