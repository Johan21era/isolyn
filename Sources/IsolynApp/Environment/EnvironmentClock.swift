import Foundation

/// An injectable source of "now" and "what timezone," so environment
/// logic can be tested deterministically instead of depending on the
/// wall clock -- the implementation prompt (sections 5 and 32) requires
/// exactly this: "create a deterministic time abstraction," "use
/// injectable clocks/time providers."
///
/// `timeZone()` is a method rather than a stored property so a *live*
/// clock can reflect a timezone change without needing to be recreated
/// -- `SystemEnvironmentClock` below always asks `TimeZone.current`
/// fresh, rather than caching a value from whenever it was constructed.
protocol EnvironmentClock: Sendable {
    func now() -> Date
    func timeZone() -> TimeZone
}

/// The real clock the running app uses: actual system time, actual
/// system timezone, read fresh on every call.
struct SystemEnvironmentClock: EnvironmentClock {
    func now() -> Date { Date() }
    func timeZone() -> TimeZone { .current }
}

/// A pinned clock for deterministic tests. Both the instant and the
/// timezone are plain settable properties, so a test can build one
/// fixed reading, or explicitly change a field mid-test (e.g. to
/// exercise "the same instant, viewed from a different timezone").
struct FixedEnvironmentClock: EnvironmentClock {
    var fixedNow: Date
    var fixedTimeZone: TimeZone

    func now() -> Date { fixedNow }
    func timeZone() -> TimeZone { fixedTimeZone }
}
