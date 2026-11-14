import Foundation
import CoreGraphics
import Observation

/// TEMPORARY diagnostic. Records exactly what the board laid out with and
/// exposes it in the top bar, so a screenshot carries the numbers and nobody
/// has to infer geometry from pixels. Removed once the chain is confirmed.
@MainActor
@Observable
final class LayoutProbe {
    static let shared = LayoutProbe()

    private static let path = "/tmp/isolyn-layout.log"

    private(set) var lastSummary = "—"

    private init() {}

    func record(availableSize: CGSize,
                tileCount: Int,
                scale: CGFloat,
                content: CGSize,
                placed: [(x: CGFloat, y: CGFloat, vertical: Bool)]) {
        let rows = Set(placed.map { Int($0.y) }).count
        lastSummary = "\(Int(availableSize.width))×\(Int(availableSize.height)) "
            + "n\(tileCount) s\(String(format: "%.2f", scale)) r\(rows)"

        var text = "available=\(Int(availableSize.width))x\(Int(availableSize.height)) "
        text += "tiles=\(tileCount) scale=\(String(format: "%.3f", scale)) "
        text += "content=\(Int(content.width))x\(Int(content.height)) rows="
        text += Set(placed.map { Int($0.y) }).sorted().map(String.init).joined(separator: ",")
        text += "\n"
        for (i, p) in placed.enumerated() {
            text += String(format: "%d %.1f %.1f %@\n", i, p.x, p.y, p.vertical ? "V" : "h")
        }
        try? text.write(toFile: Self.path, atomically: true, encoding: .utf8)
    }
}
