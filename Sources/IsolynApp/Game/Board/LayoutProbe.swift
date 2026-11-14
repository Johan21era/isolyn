import Foundation
import CoreGraphics

/// TEMPORARY diagnostic. Writes exactly what the board laid out with, so a
/// live report can be checked against the algorithm instead of inferred from
/// pixels in a screenshot. DEBUG-only; deleted once the chain is confirmed.
enum LayoutProbe {
    private static let path = "/tmp/isolyn-layout.log"

    static func record(availableSize: CGSize,
                       tileCount: Int,
                       scale: CGFloat,
                       content: CGSize,
                       placed: [(x: CGFloat, y: CGFloat, vertical: Bool)]) {
        #if DEBUG
        var text = "available=\(Int(availableSize.width))x\(Int(availableSize.height)) "
        text += "tiles=\(tileCount) scale=\(String(format: "%.3f", scale)) "
        text += "content=\(Int(content.width))x\(Int(content.height)) rows="
        let distinct = Set(placed.map { Int($0.y) }).sorted()
        text += distinct.map(String.init).joined(separator: ",")
        text += "\n"
        for (i, p) in placed.enumerated() {
            text += String(format: "%d %.1f %.1f %@\n", i, p.x, p.y, p.vertical ? "V" : "h")
        }
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        #endif
    }
}
