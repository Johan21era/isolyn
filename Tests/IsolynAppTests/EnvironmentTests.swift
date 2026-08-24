import XCTest
@testable import IsolynApp

/// Exercises `TimePhase` against every boundary case called out by the
/// implementation prompt (section 32), plus timezone-change, DST, and
/// midnight-rollover behavior. Every test uses `FixedEnvironmentClock`;
/// nothing here depends on the actual wall clock or the host machine's
/// timezone.
final class TimePhaseTests: XCTestCase {

    /// Builds a `FixedEnvironmentClock` for a given wall-clock time, on
    /// an arbitrary fixed reference day, in the given timezone. The
    /// reference day (Jan 15, 2025) is deliberately far from any DST
    /// transition so ordinary boundary tests aren't accidentally
    /// sensitive to it; the DST-specific tests below pick their own
    /// dates on purpose.
    private func clock(hour: Int, minute: Int, second: Int = 0,
                        day: Int = 15, month: Int = 1, year: Int = 2025,
                        timeZoneIdentifier: String = "America/New_York") -> FixedEnvironmentClock {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: timeZoneIdentifier)!
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day,
                                         hour: hour, minute: minute, second: second)
        let date = calendar.date(from: components)!
        return FixedEnvironmentClock(fixedNow: date, fixedTimeZone: zone)
    }

    // MARK: - Section 32's exact boundary table

    func test_04_59_isNight() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 4, minute: 59)).phase, .night)
    }

    func test_05_00_isMorning() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 5, minute: 0)).phase, .morning)
    }

    func test_09_59_isMorning() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 9, minute: 59)).phase, .morning)
    }

    func test_10_00_isTransitionStart() {
        let result = TimePhase.resolve(for: clock(hour: 10, minute: 0))
        XCTAssertEqual(result.phase, .morningToAfternoonTransition)
        XCTAssertEqual(result.transitionProgress ?? -1, 0.0, accuracy: 0.001)
    }

    func test_10_30_isTransitionMidpoint() {
        let result = TimePhase.resolve(for: clock(hour: 10, minute: 30))
        XCTAssertEqual(result.phase, .morningToAfternoonTransition)
        XCTAssertEqual(result.transitionProgress ?? -1, 0.5, accuracy: 0.001)
    }

    func test_11_00_isAfternoon() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 11, minute: 0)).phase, .afternoon)
    }

    func test_15_59_isAfternoon() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 15, minute: 59)).phase, .afternoon)
    }

    func test_16_00_isPrimeDay() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 16, minute: 0)).phase, .primeDay)
    }

    func test_20_29_isPrimeDay() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 20, minute: 29)).phase, .primeDay)
    }

    func test_20_30_isNight() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 20, minute: 30)).phase, .night)
    }

    func test_00_00_isNight() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 0, minute: 0)).phase, .night)
    }

    // MARK: - Resting phases carry no transition progress

    func test_restingPhases_haveNilTransitionProgress() {
        XCTAssertNil(TimePhase.resolve(for: clock(hour: 7, minute: 0)).transitionProgress)
        XCTAssertNil(TimePhase.resolve(for: clock(hour: 13, minute: 0)).transitionProgress)
        XCTAssertNil(TimePhase.resolve(for: clock(hour: 18, minute: 0)).transitionProgress)
        XCTAssertNil(TimePhase.resolve(for: clock(hour: 2, minute: 0)).transitionProgress)
    }

    // MARK: - Timezone change

    func test_timezoneChange_reclassifiesTheSameInstant() {
        // 05:00 in New York is 18:00 (6pm) in Singapore -- Singapore
        // is UTC+8 and New York is UTC-5 in January, so Singapore is
        // 13 hours AHEAD, not behind (verified against the IANA tz
        // database, not assumed). Same absolute instant, different
        // local phase: 05:00 NY is `.morning`; 18:00 Singapore falls
        // in `.primeDay` (16:00-20:30). This is the behavior section 5
        // requires -- the *instant* doesn't change when the timezone
        // does, but the resolved phase must.
        var c = clock(hour: 5, minute: 0, timeZoneIdentifier: "America/New_York")
        XCTAssertEqual(TimePhase.resolve(for: c).phase, .morning)

        c.fixedTimeZone = TimeZone(identifier: "Asia/Singapore")!
        XCTAssertEqual(TimePhase.resolve(for: c).phase, .primeDay)
    }

    // MARK: - Daylight saving transition

    func test_daylightSaving_springForward_stillReadsWallClockCorrectly() {
        // US Eastern sprang forward on March 9, 2025 (02:00 -> 03:00).
        // If phase logic ever regresses to naive fixed-UTC-offset math
        // instead of real Calendar component extraction, this is the
        // test that would catch it: 05:00 local must still mean
        // `.morning` on the one day of the year local time isn't
        // simply "UTC minus the usual offset."
        let result = TimePhase.resolve(for: clock(hour: 5, minute: 0, day: 9, month: 3, year: 2025))
        XCTAssertEqual(result.phase, .morning)
    }

    func test_daylightSaving_fallBack_stillReadsWallClockCorrectly() {
        // US Eastern fell back on November 2, 2025 (02:00 -> 01:00),
        // producing a 25-hour local day. `.night` (20:30-05:00) is the
        // phase that actually contains the repeated hour; this confirms
        // it's still classified correctly rather than the extra hour
        // pushing the calculation into the wrong phase.
        let result = TimePhase.resolve(for: clock(hour: 1, minute: 30, day: 2, month: 11, year: 2025))
        XCTAssertEqual(result.phase, .night)
    }

    // MARK: - Midnight rollover

    func test_midnightRollover_remainsNightOnBothSides() {
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 23, minute: 59, second: 59)).phase, .night)
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 0, minute: 0, second: 0)).phase, .night)
        XCTAssertEqual(TimePhase.resolve(for: clock(hour: 0, minute: 0, second: 1)).phase, .night)
    }
}

/// Confirms `EnvironmentManager` actually wires up to `TimePhase`
/// correctly at construction time -- the pure-function tests above
/// cover the classification logic exhaustively, so this stays
/// intentionally small.
final class EnvironmentManagerTests: XCTestCase {

    private func clock(hour: Int, minute: Int,
                        timeZoneIdentifier: String = "America/New_York") -> FixedEnvironmentClock {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: timeZoneIdentifier)!
        calendar.timeZone = zone
        let components = DateComponents(year: 2025, month: 1, day: 15, hour: hour, minute: minute)
        return FixedEnvironmentClock(fixedNow: calendar.date(from: components)!, fixedTimeZone: zone)
    }

    func test_init_resolvesStateImmediately() {
        // Section 30 ("Launch Performance") requires the first frame to
        // reflect the real phase with no waiting -- this confirms
        // `state` is correct the instant the manager exists, not only
        // after some later refresh.
        let manager = EnvironmentManager(clock: clock(hour: 7, minute: 0), refreshIntervalSeconds: 0)
        XCTAssertEqual(manager.state.phase, .morning)
    }

    func test_init_capturesTransitionProgress() {
        let manager = EnvironmentManager(clock: clock(hour: 10, minute: 30), refreshIntervalSeconds: 0)
        XCTAssertEqual(manager.state.phase, .morningToAfternoonTransition)
        XCTAssertEqual(manager.state.transitionProgress ?? -1, 0.5, accuracy: 0.001)
    }

    func test_init_recordsTheResolvedTimeZone() {
        let manager = EnvironmentManager(clock: clock(hour: 22, minute: 0, timeZoneIdentifier: "Asia/Singapore"),
                                          refreshIntervalSeconds: 0)
        XCTAssertEqual(manager.state.timeZoneIdentifier, "Asia/Singapore")
    }

    func test_init_capturesTimeOfDayMinutes() {
        let manager = EnvironmentManager(clock: clock(hour: 10, minute: 30), refreshIntervalSeconds: 0)
        XCTAssertEqual(manager.state.timeOfDayMinutes, 630, accuracy: 0.01)
    }
}

/// Exercises the continuous appearance curve `AtmosphericBackgroundView`
/// reads from -- separate from `TimePhaseTests` because this is testing
/// smooth blending, not discrete classification.
final class EnvironmentAppearanceCurveTests: XCTestCase {

    func test_exactKeyframe_returnsThatKeyframesValuesExactly() {
        let appearance = EnvironmentAppearanceCurve.appearance(atMinute: 1230) // 20:30, night begins
        XCTAssertEqual(appearance.starVisibility, 0.90, accuracy: 0.001)
    }

    func test_midpointBetweenKeyframes_liesStrictlyBetweenTheirValues() {
        // Between 20:00 (starVisibility 0.60) and 20:30 (0.90). Not
        // asserting the exact midpoint value, since easing is
        // smoothstep, not linear -- only that it's strictly between.
        let before = EnvironmentAppearanceCurve.appearance(atMinute: 1200).starVisibility
        let after = EnvironmentAppearanceCurve.appearance(atMinute: 1230).starVisibility
        let midpoint = EnvironmentAppearanceCurve.appearance(atMinute: 1215).starVisibility
        XCTAssertGreaterThan(midpoint, min(before, after))
        XCTAssertLessThan(midpoint, max(before, after))
    }

    func test_wrapsAcrossMidnightContinuously() {
        // 23:59 and 00:01 sit on either side of the wraparound segment
        // and should be nearly identical, not a discontinuous jump.
        let justBefore = EnvironmentAppearanceCurve.appearance(atMinute: 1439)
        let justAfter = EnvironmentAppearanceCurve.appearance(atMinute: 1)
        XCTAssertEqual(justBefore.starVisibility, justAfter.starVisibility, accuracy: 0.01)
        XCTAssertEqual(justBefore.ambientLuminance, justAfter.ambientLuminance, accuracy: 0.01)
    }

    func test_negativeMinutes_wrapToTheSameResultAsTheirPositiveEquivalent() {
        let negative = EnvironmentAppearanceCurve.appearance(atMinute: -30)
        let wrapped = EnvironmentAppearanceCurve.appearance(atMinute: 1410)
        XCTAssertEqual(negative, wrapped)
    }

    func test_starsAreFullyHiddenAtMidday() {
        XCTAssertEqual(EnvironmentAppearanceCurve.appearance(atMinute: 13 * 60 + 30).starVisibility, 0, accuracy: 0.001)
    }
}
