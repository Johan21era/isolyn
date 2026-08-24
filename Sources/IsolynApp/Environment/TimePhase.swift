import Foundation

/// The five environmental time states Isolyn's background system can be
/// in. Four are stable "resting" phases (`morning`, `afternoon`,
/// `primeDay`, `night`); `morningToAfternoonTransition` is an explicit,
/// hour-long bridge between `morning` and `afternoon` -- not a resting
/// phase of its own, but a named state so that hour has a distinct,
/// testable identity instead of an abrupt jump (implementation prompt,
/// section 4).
///
/// Boundaries below are authoritative, local-time, and must not drift:
/// - `night`     20:30 ..< 05:00 (wraps past midnight)
/// - `morning`   05:00 ..< 10:00
/// - `morningToAfternoonTransition` 10:00 ..< 11:00
/// - `afternoon` 11:00 ..< 16:00
/// - `primeDay`  16:00 ..< 20:30
enum TimePhase: String, CaseIterable, Sendable, Equatable {
    case night
    case morning
    case morningToAfternoonTransition
    case afternoon
    case primeDay
}

extension TimePhase {
    // Boundaries, expressed as minutes since local midnight, so
    // classification is exact fractional-minute comparison -- never
    // hour/minute compound conditionals that are easy to get subtly
    // wrong at the edges.
    static let morningStartMinute: Double = 5 * 60        // 05:00
    static let transitionStartMinute: Double = 10 * 60     // 10:00
    static let afternoonStartMinute: Double = 11 * 60       // 11:00
    static let primeDayStartMinute: Double = 16 * 60        // 16:00
    static let nightStartMinute: Double = 20 * 60 + 30      // 20:30

    /// Pure classification: given minutes-since-local-midnight, which
    /// phase is it? Total -- every value in `0..<1440` maps to exactly
    /// one case, with `.night` as the fallthrough for both sides of
    /// midnight (`[20:30, 24:00)` and `[00:00, 05:00)`).
    static func classify(minutesSinceMidnight minutes: Double) -> TimePhase {
        switch minutes {
        case morningStartMinute..<transitionStartMinute: return .morning
        case transitionStartMinute..<afternoonStartMinute: return .morningToAfternoonTransition
        case afternoonStartMinute..<primeDayStartMinute: return .afternoon
        case primeDayStartMinute..<nightStartMinute: return .primeDay
        default: return .night
        }
    }

    /// `classify`, plus -- only while inside the explicit transition
    /// bridge -- how far through that hour we are (0 at 10:00,
    /// approaching 1 at 11:00). `nil` for every resting phase; those
    /// don't carry a progress value in this pass. (Continuous blending
    /// across *every* boundary, for the renderer, is the environment-
    /// interpolation step -- separate, later work, not this one.)
    static func resolve(minutesSinceMidnight minutes: Double) -> (phase: TimePhase, transitionProgress: Double?) {
        let phase = classify(minutesSinceMidnight: minutes)
        guard phase == .morningToAfternoonTransition else { return (phase, nil) }
        let span = afternoonStartMinute - transitionStartMinute
        let progress = (minutes - transitionStartMinute) / span
        return (phase, min(max(progress, 0), 1))
    }

    /// The entry point everything else (the manager, tests) should call.
    /// Reads the clock's instant and timezone, converts to local
    /// wall-clock minutes-since-midnight via `Calendar` component
    /// extraction (DST-safe by construction -- never manual UTC-offset
    /// arithmetic, per section 5's explicit instruction), and resolves.
    /// Also returns that raw `timeOfDayMinutes` value alongside the
    /// discrete phase -- rendering code (`EnvironmentAppearanceCurve`,
    /// later the star field) needs the continuous value to blend
    /// smoothly across *every* boundary, not just the explicit
    /// transition bridge.
    static func resolve(for clock: EnvironmentClock, calendar: Calendar = .current) -> (phase: TimePhase, transitionProgress: Double?, timeOfDayMinutes: Double) {
        var calendar = calendar
        calendar.timeZone = clock.timeZone()
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: clock.now())
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)
        let nanosecond = Double(components.nanosecond ?? 0)
        let minutesSinceMidnight = hour * 60 + minute + second / 60 + nanosecond / 60_000_000_000
        let (phase, progress) = resolve(minutesSinceMidnight: minutesSinceMidnight)
        return (phase, progress, minutesSinceMidnight)
    }
}
