import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// Owns the app's single source of truth for "what does the
/// environment look like right now" -- time/phase, and, as of this
/// batch, weather. Keeps both current automatically: time on a
/// lightweight timer plus immediately on a system timezone change;
/// weather on its own, much slower timer.
@Observable
final class EnvironmentManager {
    /// The fully-resolved current time/phase state. Views should read
    /// this -- and only this, for time -- rather than computing
    /// phase/time themselves (section 31's architecture rule).
    private(set) var state: EnvironmentState = .initial

    /// Which weather source is currently backing `currentSkyCondition`.
    private(set) var weatherMode: WeatherMode

    /// The last successfully-fetched sky condition. Starts `.clear` and
    /// stays at its last good value if a fetch fails or the source
    /// reports unavailable -- see `refreshWeather`.
    private(set) var currentSkyCondition: SkyCondition = .clear

    private let clock: EnvironmentClock
    private let calendar: Calendar

    @ObservationIgnored private var weatherSource: any WeatherSource
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var weatherTask: Task<Void, Never>?
    @ObservationIgnored private var timeZoneObserver: NSObjectProtocol?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - clock: Defaults to the real system clock. Tests inject
    ///     `FixedEnvironmentClock` instead.
    ///   - refreshIntervalSeconds: Time/phase refresh cadence. Pass 0 to
    ///     disable.
    ///   - weatherMode: Defaults to `.randomized` -- works with zero
    ///     extra project configuration. `.live` needs the WeatherKit
    ///     capability and location permission; see `LiveWeatherService`.
    ///   - weatherRefreshIntervalSeconds: How often to re-fetch weather.
    ///     Much slower than the time refresh. Pass 0 to disable.
    init(clock: EnvironmentClock = SystemEnvironmentClock(),
         calendar: Calendar = .current,
         refreshIntervalSeconds: Int = 30,
         weatherMode: WeatherMode = .randomized,
         weatherSource: (any WeatherSource)? = nil,
         weatherRefreshIntervalSeconds: Int = 600) {
        self.clock = clock
        self.calendar = calendar
        self.weatherMode = weatherMode
        self.weatherSource = weatherSource ?? Self.makeWeatherSource(for: weatherMode, clock: clock)
        refresh()
        observeTimeZoneChanges()
        observeForegroundNotifications()
        scheduleRefreshLoop(intervalSeconds: refreshIntervalSeconds)
        scheduleWeatherLoop(intervalSeconds: weatherRefreshIntervalSeconds)
    }

    deinit {
        refreshTask?.cancel()
        weatherTask?.cancel()
        if let timeZoneObserver {
            NotificationCenter.default.removeObserver(timeZoneObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    /// Re-resolves `state` from the clock right now. Safe to call as
    /// often as needed -- cheap, synchronous, no I/O.
    func refresh() {
        let (phase, progress, timeOfDayMinutes) = TimePhase.resolve(for: clock, calendar: calendar)
        state = EnvironmentState(
            phase: phase,
            transitionProgress: progress,
            timeOfDayMinutes: timeOfDayMinutes,
            timeZoneIdentifier: clock.timeZone().identifier,
            resolvedAt: clock.now()
        )
    }

    /// Switches which `WeatherSource` backs `currentSkyCondition` and
    /// refreshes from it immediately. `.off` clears to `.clear`;
    /// `.live`/`.randomized` kick off an async fetch.
    func setWeatherMode(_ mode: WeatherMode) {
        weatherMode = mode
        weatherSource = Self.makeWeatherSource(for: mode, clock: clock)
        if mode == .off {
            currentSkyCondition = .clear
        } else {
            Task { [weak self] in await self?.refreshWeather() }
        }
    }

    /// Fetches once from the current `weatherSource`. On success,
    /// updates `currentSkyCondition`. On failure/unavailable (`nil`),
    /// deliberately leaves it at its last value -- a stale-but-plausible
    /// condition reads better than the sky flickering to "clear" every
    /// time one fetch fails.
    func refreshWeather() async {
        guard weatherMode != .off else { return }
        guard let condition = await weatherSource.currentCondition() else { return }
        await MainActor.run { self.currentSkyCondition = condition }
    }

    private static func makeWeatherSource(for mode: WeatherMode, clock: EnvironmentClock) -> any WeatherSource {
        switch mode {
        case .live:
            #if canImport(WeatherKit)
            return LiveWeatherService()
            #else
            return RandomWeatherService(clock: clock)
            #endif
        case .randomized, .off:
            return RandomWeatherService(clock: clock)
        }
    }

    private func observeTimeZoneChanges() {
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // `.current` is cached per-process; this is the
                // documented way to force it to reflect the *new*
                // system timezone before re-resolving.
                NSTimeZone.resetSystemTimeZone()
                self?.refresh()
            }
        }
    }

    private func scheduleRefreshLoop(intervalSeconds: Int) {
        guard intervalSeconds > 0 else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { self?.refresh() }
            }
        }
    }

    /// macOS equivalent of "refresh on foreground": re-resolves both
    /// time and weather as soon as the app becomes active again, rather
    /// than waiting for the next timer tick -- covers the case where the
    /// app sat backgrounded long enough that either is stale the moment
    /// someone actually looks at it again.
    private func observeForegroundNotifications() {
        #if canImport(AppKit)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                await self?.refreshWeather()
            }
        }
        #endif
    }

    private func scheduleWeatherLoop(intervalSeconds: Int) {
        guard intervalSeconds > 0, weatherMode != .off else { return }
        weatherTask = Task { [weak self] in
            await self?.refreshWeather()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.refreshWeather()
            }
        }
    }
}

