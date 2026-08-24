import Foundation

/// One falling weather particle. Position is expressed as a phase
/// (`fallOffset` + elapsed time * `fallSpeed`, wrapped 0...1) rather
/// than stored/mutated coordinates -- same technique as `Star`'s
/// twinkle: a pure function of elapsed time, so nothing needs per-frame
/// state mutation or storage.
struct WeatherParticle: Equatable, Sendable {
    var relativeX: Double
    var fallOffset: Double
    var fallSpeed: Double      // fall cycles per second -- how fast it loops top to bottom
    var size: Double
    var opacity: Double
    var driftAmount: Double    // horizontal sway distance (relative units)
    var driftSpeed: Double     // sway cycles per second
}

/// Procedural rain/snow placement, same deterministic-seed approach as
/// `StarField`. Rain: fast fall, short streaks, little drift. Snow:
/// slow fall, small crystalline shapes (section 9's "sharp crystalline
/// geometry inspired by the supplied snowflake reference" -- at
/// particle scale, captured via angular line strokes rather than a
/// literal reproduction of the reference photo), more drift.
enum WeatherField {
    static func generateRain(count: Int = 90, seed: UInt64 = 0x7A1157) -> [WeatherParticle] {
        var rng = SeededGenerator(seed: seed)
        return (0..<max(0, count)).map { _ in
            WeatherParticle(
                relativeX: Double.random(in: 0...1, using: &rng),
                fallOffset: Double.random(in: 0..<1, using: &rng),
                fallSpeed: Double.random(in: 0.9...1.6, using: &rng),
                size: Double.random(in: 10...22, using: &rng),
                opacity: Double.random(in: 0.25...0.55, using: &rng),
                driftAmount: Double.random(in: 0.01...0.03, using: &rng),
                driftSpeed: Double.random(in: 0.1...0.2, using: &rng)
            )
        }
    }

    static func generateSnow(count: Int = 70, seed: UInt64 = 0x5E0157) -> [WeatherParticle] {
        var rng = SeededGenerator(seed: seed)
        return (0..<max(0, count)).map { _ in
            WeatherParticle(
                relativeX: Double.random(in: 0...1, using: &rng),
                fallOffset: Double.random(in: 0..<1, using: &rng),
                fallSpeed: Double.random(in: 0.12...0.28, using: &rng),
                size: Double.random(in: 2.5...5.5, using: &rng),
                opacity: Double.random(in: 0.5...0.95, using: &rng),
                driftAmount: Double.random(in: 0.03...0.09, using: &rng),
                driftSpeed: Double.random(in: 0.15...0.35, using: &rng)
            )
        }
    }
}
