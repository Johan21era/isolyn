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
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: environmentManager.state.timeZoneIdentifier)
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: environmentManager.state.resolvedAt)
    }
}

#Preview("Time label") {
    EnvironmentTimeLabel()
        .environment(EnvironmentManager())
        .padding()
        .background(Color.black)
}
