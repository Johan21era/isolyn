import SwiftUI

/// Renders rain or snow, driven by `EnvironmentManager.currentSkyCondition`.
/// Fog is deliberately not a particle system here -- it's a contrast/tint
/// effect applied in `EnvironmentAppearanceCurve.composite`, not discrete
/// shapes. Same Canvas + TimelineView approach as `StarFieldView`.
struct WeatherEffectView: View {
    @Environment(EnvironmentManager.self) private var environmentManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rainParticles: [WeatherParticle]
    private let snowParticles: [WeatherParticle]

    init() {
        self.rainParticles = WeatherField.generateRain()
        self.snowParticles = WeatherField.generateSnow()
    }

    var body: some View {
        let condition = environmentManager.currentSkyCondition
        let isAnimating = !reduceMotion && (condition == .rain || condition == .snow)

        TimelineView(.animation(paused: !isAnimating)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                switch condition {
                case .rain:
                    drawRain(in: &context, size: size, elapsed: elapsed)
                case .snow:
                    drawSnow(in: &context, size: size, elapsed: elapsed)
                case .clear, .cloudy, .fog:
                    break
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawRain(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        for particle in rainParticles {
            let cycle = (particle.fallOffset + elapsed * particle.fallSpeed)
                .truncatingRemainder(dividingBy: 1.0)
            let drift = reduceMotion ? 0 : sin(elapsed * particle.driftSpeed) * particle.driftAmount
            let x = (particle.relativeX + drift) * size.width
            let yEnd = cycle * (size.height + particle.size) - particle.size
            let yStart = yEnd - particle.size

            var path = Path()
            path.move(to: CGPoint(x: x, y: yStart))
            path.addLine(to: CGPoint(x: x + 3, y: yEnd))
            context.stroke(path, with: .color(.white.opacity(particle.opacity)), lineWidth: 1.2)
        }
    }

    private func drawSnow(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        for particle in snowParticles {
            let cycle = (particle.fallOffset + elapsed * particle.fallSpeed)
                .truncatingRemainder(dividingBy: 1.0)
            let drift = reduceMotion ? 0 : sin(elapsed * particle.driftSpeed + particle.fallOffset * 10) * particle.driftAmount
            let x = (particle.relativeX + drift) * size.width
            let y = cycle * (size.height + particle.size * 2) - particle.size
            let center = CGPoint(x: x, y: y)

            // Three crossing lines through the center -- a small,
            // angular six-point asterisk rather than a soft dot, so
            // snow reads as sharp/crystalline even at falling-particle
            // scale (section 9).
            var path = Path()
            for i in 0..<3 {
                let angle = Double(i) * (Double.pi / 3)
                let dx = cos(angle) * particle.size
                let dy = sin(angle) * particle.size
                path.move(to: CGPoint(x: center.x - dx, y: center.y - dy))
                path.addLine(to: CGPoint(x: center.x + dx, y: center.y + dy))
            }
            context.stroke(path, with: .color(.white.opacity(particle.opacity)), lineWidth: 1.0)
        }
    }
}

#Preview("Rain") {
    WeatherEffectView()
        .environment(EnvironmentManager(
            weatherMode: .randomized,
            weatherSource: FixedWeatherSource(condition: .rain)
        ))
        .frame(width: 500, height: 360)
        .background(Color.black)
}

#Preview("Snow") {
    WeatherEffectView()
        .environment(EnvironmentManager(
            weatherMode: .randomized,
            weatherSource: FixedWeatherSource(condition: .snow)
        ))
        .frame(width: 500, height: 360)
        .background(Color.black)
}
