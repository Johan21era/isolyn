import Foundation

/// The environment system's fully-resolved answer to "what should the
/// background look like right now" -- a plain, comparable value type,
/// so views, previews, and tests can all reason about "a given
/// environment state" without needing a live `EnvironmentManager`.
///
/// Deliberately scoped to time/phase only in this pass. Weather
/// (`WeatherSource`, `WeatherCondition`, intensity) is real, undone work
/// -- steps 11-15 of the implementation prompt -- and will extend this
/// type when it's built, rather than being stubbed into it now.
struct EnvironmentState: Equatable, Sendable {
    /// The current named phase.
    var phase: TimePhase

    /// 0...1 progress through the `.morningToAfternoonTransition`
    /// bridge. `nil` for every other (resting) phase.
    var transitionProgress: Double?

    /// Continuous minutes since local midnight, 0..<1440. Exists
    /// alongside the discrete `phase` specifically so rendering code
    /// (`EnvironmentAppearanceCurve`, later the star field) can blend
    /// smoothly across *every* boundary, not just the explicit
    /// transition bridge -- `phase`/`transitionProgress` stay the
    /// section-32-tested, discrete classification; this is the
    /// continuous companion value section 7 actually needs.
    var timeOfDayMinutes: Double

    /// The IANA identifier (e.g. "America/New_York") this state was
    /// resolved against -- kept mainly for debugging: "why did the
    /// background just change?" is much easier to answer with this
    /// visible.
    var timeZoneIdentifier: String

    /// The instant this state was resolved for -- not "now" in
    /// general, specifically the clock reading used to compute `phase`.
    var resolvedAt: Date

    /// A reasonable value for previews and initial view construction,
    /// before the first real resolution has happened. Deliberately
    /// `.night` -- section 8 of the prompt calls night "the hero
    /// environment," so an unresolved/initial state fails toward the
    /// app's best-looking state rather than an arbitrary one.
    static let initial = EnvironmentState(
        phase: .night,
        transitionProgress: nil,
        timeOfDayMinutes: 0,
        timeZoneIdentifier: TimeZone.current.identifier,
        resolvedAt: .distantPast
    )
}
