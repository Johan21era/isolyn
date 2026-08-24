import SwiftUI
import Observation
import IsolynEngineBridge

/// Persisted, live-editable domino appearance state.
/// Completely isolated from game state — changing any field here never
/// invalidates engine knowledge, hover classification, or camera position.
/// Persists via UserDefaults (JSON-encoded) so settings survive relaunch.
@MainActor
@Observable
final class AppearanceManager {
    private(set) var appearance: DominoAppearance

    private static let storageKey = "isolyn.dominoAppearance.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(DominoAppearance.self, from: data) {
            self.appearance = saved
        } else {
            self.appearance = .classicIvory
        }
    }

    // MARK: - Mutations (each updates the single canonical model)

    func setBodyColor(hex: String) {
        guard Color(hex: hex) != nil else { return } // reject malformed silently
        appearance.bodyColorHex = hex
        persist()
    }

    func setPipColor(hex: String) {
        guard Color(hex: hex) != nil else { return }
        appearance.pipColorHex = hex
        persist()
    }

    func setEdgeMode(_ mode: EdgeHighlightMode) {
        appearance.edgeMode = mode
        persist()
    }

    func setEdgeColor(hex: String) {
        guard Color(hex: hex) != nil else { return }
        appearance.edgeColorHex = hex
        persist()
    }

    func setEdgeIntensity(_ value: Double) {
        appearance.edgeIntensity = max(0, min(1, value))
        persist()
    }

    func applyPreset(_ preset: DominoAppearance) {
        appearance = preset
        persist()
    }

    /// Sets body color from a hue slider position, preserving saturation/brightness.
    /// FIX-21 (N-1): reads S/B purely from the stored hex string via the
    /// pure conversion helpers -- the old path went through a Color-keyed
    /// cache that was never populated, so S/B resolved to zero and any
    /// hue drag snapped the tile body to black.
    func setBodyHue(_ hue: Double) {
        let hsB = Color.hsb(fromHex: appearance.bodyColorHex)
        appearance.bodyColorHex = Color.hexString(
            fromHue: hue,
            saturation: hsB.saturation,
            brightness: hsB.brightness
        )
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(appearance) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
