import SwiftUI

/// A small, unobtrusive current-time readout in the environment's own
/// local timezone. Reads directly from `EnvironmentManager.state`
/// rather than computing its own time (section 31's rule extended to
/// this element too) -- if the environment's notion of "now" is ever
/// wrong, this label is wrong along with everything else, which is the
/// correct failure mode (one source of truth, not two clocks that could
/// disagree).
struct EnvironmentTimeLabel: View {
    @Environment(EnvironmentManager.self) private var environmentManager

    var body: some View {
        Text(formattedTime)
            .font(IsolynTheme.caption(12))
            .foregroundStyle(IsolynTheme.ivoryMuted)
            .monospacedDigit()
    }

    private var formattedTime: String {
        Self.formatter(for: environmentManager.state.timeZoneIdentifier)
            .string(from: environmentManager.state.resolvedAt)
    }

    /// FIX-23 (audit F-09): DateFormatter construction is notoriously
    /// expensive and this label re-evaluates every refresh tick. One
    /// cached formatter per timezone identifier; the label body is
    /// MainActor-confined so dictionary access is serialized by
    /// isolation. Cache grows only with distinct timezones encountered
    /// (one for virtually every user).
    @MainActor
    private static var formatterCache: [String: DateFormatter] = [:]

    @MainActor
    private static func formatter(for timeZoneIdentifier: String) -> DateFormatter {
        if let cached = formatterCache[timeZoneIdentifier] { return cached }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: timeZoneIdentifier)
        f.dateFormat = "h:mm a"
        formatterCache[timeZoneIdentifier] = f
        return f
    }
}

#Preview("Time label") {
    EnvironmentTimeLabel()
        .environment(EnvironmentManager())
        .padding()
        .background(Color.black)
}
