import XCTest
import SwiftUI
@testable import IsolynApp

/// FIX-21 (roadmap N-1): pins the PURE hex<->HSB conversion helpers that
/// replaced the broken Color-keyed cache. The bug these tests guard
/// against: any future reintroduction of stateful/lossy conversion that
/// makes a hue drag snap colors to black or lose saturation/brightness.
final class ColorMathTests: XCTestCase {

    // MARK: - Known-value conversions (no round-trip trust required)

    func test_pureRed_resolvesExactly() {
        let rgb = Color.resolveHex("#FF0000")
        XCTAssertNotNil(rgb)
        XCTAssertEqual(rgb!.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rgb!.g, 0.0, accuracy: 1e-9)
        XCTAssertEqual(rgb!.b, 0.0, accuracy: 1e-9)
    }

    func test_hsbOfPureRed_isFullSaturationFullBrightnessHueZero() {
        let hsb = Color.hsb(fromHex: "#FF0000")
        XCTAssertEqual(hsb.hue, 0.0, accuracy: 1e-6)
        XCTAssertEqual(hsb.saturation, 1.0, accuracy: 1e-9)
        XCTAssertEqual(hsb.brightness, 1.0, accuracy: 1e-9)
    }

    func test_hue360_equivalentToHueZero() {
        // Hue wraps; both must produce the same red.
        XCTAssertEqual(
            Color.hexString(fromHue: 0, saturation: 1, brightness: 1),
            Color.hexString(fromHue: 360, saturation: 1, brightness: 1)
        )
    }

    func test_classicIvoryBodyHex_roundTripsStably() {
        // The default tile body color must survive hex -> HSB -> hex with
        // no visible drift (this is exactly the operation the hue slider
        // performs on every drag tick).
        let original = "#F2EDE4"
        let hsb = Color.hsb(fromHex: original)
        let back = Color.hexString(fromHue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
        XCTAssertEqual(back, original)
    }

    func test_hueRotation_preservesSaturationAndBrightness() {
        let original = "#BC9248" // brass edge color
        let hsb = Color.hsb(fromHex: original)
        for hue in stride(from: 0.0, through: 330.0, by: 30.0) {
            let rotated = Color.hsb(fromHex: Color.hexString(fromHue: hue, saturation: hsb.saturation, brightness: hsb.brightness))
            XCTAssertEqual(rotated.saturation, hsb.saturation, accuracy: 1e-6,
                           "saturation must survive hue rotation to \(hue)")
            XCTAssertEqual(rotated.brightness, hsb.brightness, accuracy: 1e-6,
                           "brightness must survive hue rotation to \(hue)")
        }
    }

    // MARK: - The exact regression: hue drag must NEVER zero out S/B

    func test_setBodyHuePath_neverCollapsesToBlack() {
        // Mirrors AppearanceManager.setBodyHue's arithmetic. Before FIX-21
        // this produced #000000 for EVERY hue because the cache-backed
        // hsB lookup always missed.
        let bodyHex = "#F2EDE4"
        let hsB = Color.hsb(fromHex: bodyHex)
        XCTAssertGreaterThan(hsB.brightness, 0.5, "ivory brightness must be high, not cache-miss zero")
        for hue in [0.0, 120.0, 240.0] {
            let rotatedHex = Color.hexString(fromHue: hue, saturation: hsB.saturation, brightness: hsB.brightness)
            let rgb = Color.resolveHex(rotatedHex)!
            let isBlack = rgb.r < 0.01 && rgb.g < 0.01 && rgb.b < 0.01
            XCTAssertFalse(isBlack, "hue \(hue) collapsed the ivory body to black -- N-1 regression")
        }
    }

    // MARK: - Malformed input honesty

    func test_malformedHex_resolvesToNil() {
        XCTAssertNil(Color.resolveHex("nothex"))
        XCTAssertNil(Color.resolveHex("#12345"))
        XCTAssertNil(Color.resolveHex("#GGGGGG"))
    }
}
