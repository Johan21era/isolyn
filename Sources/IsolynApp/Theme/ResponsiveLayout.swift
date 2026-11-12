import SwiftUI

/// Shared layout rules for the app's fixed-capability desktop surfaces.
///
/// The window can be resized from its 900x620 minimum through a full
/// MacBook display, so screens must not rely on a single padding value or
/// let content stretch to the window edges. These values keep the readable
/// column centered and give the board a larger, separate cap.
enum IsolynLayout {
    static let minWindowWidth: CGFloat = 900
    static let minWindowHeight: CGFloat = 620
    static let maxContentWidth: CGFloat = 1120
    static let maxBoardWidth: CGFloat = 1600
    static let compactBreakpoint: CGFloat = 1040

    /// Breathing room scales with the window, then stops growing once the
    /// centered content column has reached its comfortable width.
    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<960:
            return 24
        case ..<1280:
            return 40
        default:
            return 56
        }
    }
}

/// Centers a bounded content column inside its parent. Use this for
/// headers, action rows, lobby panels, and any other horizontal band that
/// should stay visually anchored as the window grows.
struct CenteredContent<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(maxWidth: CGFloat = IsolynLayout.maxContentWidth,
         @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .frame(maxWidth: maxWidth)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
