import Foundation

/// A small, deterministic random source -- Swift's standard library
/// doesn't ship a seedable one. SplitMix64: simple, fast, good enough
/// statistical quality for placing stars (this is not cryptographic).
/// Same seed always produces the same sequence, which is exactly what
/// makes the star field reproducible across launches and unit-testable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// One procedurally-placed star. Position is relative (0...1), not in
/// points, so the same field re-lays-out cleanly at any window size
/// instead of needing regeneration per-size.
struct Star: Equatable, Sendable {
    var relativeX: Double
    var relativeY: Double
    var radius: Double
    var baseBrightness: Double
    var twinklePhase: Double
    var twinkleSpeed: Double
}

/// Procedural star placement -- deliberately not the supplied reference
/// photos. Section 38's asset policy is explicit that those are
/// inspiration, not shippable assets; this recreates their *character*
/// (many small, mostly-uniform points, a handful brighter, generously
/// spaced) rather than their pixels.
enum StarField {
    static let defaultCount = 160
    static let defaultSeed: UInt64 = 0x1D0157

    /// A fixed default seed, not true randomness, is deliberate: the
    /// field should look the same on every launch, both because that's
    /// a more "designed" result than a different random scatter every
    /// time, and because it makes the layout itself reproducible if
    /// it's ever worth testing or screenshotting directly.
    static func generate(count: Int = defaultCount, seed: UInt64 = defaultSeed) -> [Star] {
        var rng = SeededGenerator(seed: seed)
        return (0..<max(0, count)).map { _ in
            Star(
                relativeX: Double.random(in: 0...1, using: &rng),
                relativeY: Double.random(in: 0...1, using: &rng),
                radius: Double.random(in: 0.6...1.8, using: &rng),
                baseBrightness: Double.random(in: 0.45...1.0, using: &rng),
                twinklePhase: Double.random(in: 0..<(2 * Double.pi), using: &rng),
                twinkleSpeed: Double.random(in: 0.3...0.9, using: &rng)
            )
        }
    }
}
