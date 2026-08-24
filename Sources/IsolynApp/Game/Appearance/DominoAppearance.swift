import SwiftUI

// MARK: - Edge Highlight Mode

/// Controls whether/how edge highlighting renders on dominoes.
/// `.none` is a TRUE rendering-off state — no fallback, no faint glow.
enum EdgeHighlightMode: String, CaseIterable, Codable, Sendable {
    case none = "None"
    case subtle = "Subtle"
    case standard = "Standard"
    case strong = "Strong"

    var intensity: Double {
        switch self {
        case .none: return 0.0
        case .subtle: return 0.15
        case .standard: return 0.35
        case .strong: return 0.6
        }
    }
}

// MARK: - Domino Appearance Model

/// Pure presentation state for how every domino renders.
/// Completely isolated from game state — changing any field here must never
/// invalidate engine knowledge, hover-chain classification, or camera position.
struct DominoAppearance: Codable, Equatable, Sendable {
    var bodyColorHex: String = "#F2EDE4"
    var pipColorHex: String = "#1A1712"
    var edgeMode: EdgeHighlightMode = .standard
    var edgeColorHex: String = "#BC9248"
    var edgeIntensity: Double = 0.35

    // Derived SwiftUI colors (computed from hex, not stored separately)
    var bodyColor: Color { Color(hex: bodyColorHex) ?? Color(red: 0.949, green: 0.925, blue: 0.867) }
    var pipColor: Color { Color(hex: pipColorHex) ?? Color(red: 0.071, green: 0.063, blue: 0.051) }
    var edgeColor: Color { Color(hex: edgeColorHex) ?? Color(red: 0.737, green: 0.573, blue: 0.283) }

    // MARK: Presets

    static let classicIvory = DominoAppearance()
    static let midnight = DominoAppearance(
        bodyColorHex: "#2A2A35", pipColorHex: "#D0CCC0",
        edgeMode: .subtle, edgeColorHex: "#6A6A80", edgeIntensity: 0.15)
    static let graphite = DominoAppearance(
        bodyColorHex: "#3C3C3C", pipColorHex: "#E8E8E8",
        edgeMode: .standard, edgeColorHex: "#888888", edgeIntensity: 0.3)
    static let snow = DominoAppearance(
        bodyColorHex: "#FAFAFA", pipColorHex: "#222222",
        edgeMode: .none, edgeColorHex: "#CCCCCC", edgeIntensity: 0.0)

    static let presets: [(name: String, appearance: DominoAppearance)] = [
        ("Classic Ivory", .classicIvory),
        ("Midnight", .midnight),
        ("Graphite", .graphite),
        ("Snow", .snow),
    ]
}

// MARK: - Hex Color Utilities
//
// FIX-21 (roadmap N-1): this section used to route hue math through a
// static `_hexCache` dictionary keyed on SwiftUI `Color` values -- but
// `Color.init(hex:)` never registered anything in it, so every lookup
// missed: `setBodyHue` read saturation/brightness as (0,0) and snapped
// tiles to BLACK, the slider thumb always sat at hue 0, and the cache
// was unsynchronized global mutable state besides. All conversions are
// now PURE FUNCTIONS over hex strings. No caches, no hidden state,
// nothing to desynchronize.

extension Color {
    /// Parses `#RRGGBB` or `RRGGBB`. Returns nil on malformed input.
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255.0,
            green: Double((val >> 8) & 0xFF) / 255.0,
            blue: Double(val & 0xFF) / 255.0
        )
    }

    // MARK: Pure-Swift color math (hex <-> HSB; no stored state anywhere)

    static func resolveHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        return (
            r: Double((val >> 16) & 0xFF) / 255.0,
            g: Double((val >> 8) & 0xFF) / 255.0,
            b: Double(val & 0xFF) / 255.0
        )
    }

    /// HSB extracted directly from a hex string. Malformed input yields
    /// (0, 0, 0); callers that care should validate with init?(hex:)
    /// first (the appearance manager always stores validated hex).
    static func hsb(fromHex hex: String) -> (hue: Double, saturation: Double, brightness: Double) {
        guard let rgb = resolveHex(hex) else { return (0, 0, 0) }
        return rgbToHsb(rgb)
    }

    /// Pure HSB -> #RRGGBB uppercase hex.
    static func hexString(fromHue hue: Double, saturation: Double, brightness: Double) -> String {
        rgbToHexString(hsbToRgb(hue: hue, saturation: saturation, brightness: brightness))
    }

    static func rgbToHexString(_ rgb: (r: Double, g: Double, b: Double)) -> String {
        let r = Int(round(rgb.r * 255)), g = Int(round(rgb.g * 255)), b = Int(round(rgb.b * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func rgbToHsb(_ rgb: (r: Double, g: Double, b: Double)) -> (hue: Double, saturation: Double, brightness: Double) {
        let maxV = max(rgb.r, rgb.g, rgb.b)
        let minV = min(rgb.r, rgb.g, rgb.b)
        let delta = maxV - minV
        let brightness = maxV
        let saturation = maxV > 0 ? delta / maxV : 0
        var hue: Double = 0
        if delta > 0 {
            if maxV == rgb.r {
                hue = ((rgb.g - rgb.b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == rgb.g {
                hue = (rgb.b - rgb.r) / delta + 2
            } else {
                hue = (rgb.r - rgb.g) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        return (hue, saturation, brightness)
    }

    static func hsbToRgb(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double) {
        let c = brightness * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let rgb: (Double, Double, Double)
        switch hue {
        case 0..<60: rgb = (c, x, 0)
        case 60..<120: rgb = (x, c, 0)
        case 120..<180: rgb = (0, c, x)
        case 180..<240: rgb = (0, x, c)
        case 240..<300: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }
}
