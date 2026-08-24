import SwiftUI

/// Renders `StarField.generate()` as a twinkling field, faded by
/// `starVisibility` from the appearance curve. Canvas + `TimelineView`
/// rather than one SwiftUI view per star -- at 150+ stars, per-star
/// views are real overhead for no visual benefit.
struct StarFieldView: View {
    @Environment(EnvironmentManager.self) private var environmentManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stars: [Star]

    init() {
        self.stars = StarField.generate()
    }

    init(starCount: Int, seed: UInt64) {
        self.stars = StarField.generate(count: starCount, seed: seed)
    }

    var body: some View {
        let starVisibility = EnvironmentAppearanceCurve.composite(
            atMinute: environmentManager.state.timeOfDayMinutes,
            condition: environmentManager.currentSkyCondition
        ).starVisibility

        TimelineView(.animation(paused: reduceMotion || starVisibility <= 0.001)) { timeline in
            Canvas { context, size in
                guard starVisibility > 0.001 else { return }
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                for star in stars {
                    let twinkle = reduceMotion
                        ? 1.0
                        : 0.65 + 0.35 * sin(elapsed * star.twinkleSpeed + star.twinklePhase)
                    let opacity = star.baseBrightness * starVisibility * twinkle
                    guard opacity > 0.01 else { continue }

                    let point = CGPoint(x: star.relativeX * size.width, y: star.relativeY * size.height)
                    let rect = CGRect(
                        x: point.x - star.radius, y: point.y - star.radius,
                        width: star.radius * 2, height: star.radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Star field alone — night") {
    StarFieldView()
        .environment(EnvironmentManager(clock: FixedEnvironmentClock(
            fixedNow: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now,
            fixedTimeZone: .current
        )))
        .frame(width: 500, height: 360)
        .background(Color.black)
}

#Preview("Composed with atmosphere — night") {
    ZStack {
        AtmosphericBackgroundView()
        StarFieldView()
    }
    .environment(EnvironmentManager(clock: FixedEnvironmentClock(
        fixedNow: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now,
        fixedTimeZone: .current
    )))
    .frame(width: 500, height: 360)
}

#Preview("Composed with atmosphere — midday (stars hidden)") {
    ZStack {
        AtmosphericBackgroundView()
        StarFieldView()
    }
    .environment(EnvironmentManager(clock: FixedEnvironmentClock(
        fixedNow: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now) ?? .now,
        fixedTimeZone: .current
    )))
    .frame(width: 500, height: 360)
}
