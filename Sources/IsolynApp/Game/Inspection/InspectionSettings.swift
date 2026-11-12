import Foundation
import Observation

/// The mouse button that opens the number-family inspector while the pointer
/// is over a domino. Left click is deliberately not offered: it is the play
/// gesture, and inspection must never compete with it.
enum InspectionMouseButton: String, CaseIterable, Identifiable, Codable {
    case right = "Right click"
    case middle = "Middle click"
    case extra = "Extra button"

    var id: String { rawValue }
}

@MainActor
@Observable
final class InspectionSettings {
    private(set) var autoHoverEnabled: Bool
    private(set) var mouseButton: InspectionMouseButton

    private static let storageKey = "isolyn.inspection.v1"

    private struct Stored: Codable {
        var autoHoverEnabled: Bool
        var mouseButton: InspectionMouseButton
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Stored.self, from: data) {
            autoHoverEnabled = saved.autoHoverEnabled
            mouseButton = saved.mouseButton
        } else {
            autoHoverEnabled = false
            mouseButton = .right
        }
    }

    func setAutoHoverEnabled(_ enabled: Bool) {
        autoHoverEnabled = enabled
        persist()
    }

    func setMouseButton(_ button: InspectionMouseButton) {
        mouseButton = button
        persist()
    }

    private func persist() {
        let stored = Stored(autoHoverEnabled: autoHoverEnabled, mouseButton: mouseButton)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
