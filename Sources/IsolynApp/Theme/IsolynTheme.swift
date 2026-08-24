import SwiftUI

/// Isolyn's entire visual language in one place: ebony and ivory, the
/// two colors of a real double-six set, plus a single muted brass accent
/// reserved for the one action that matters on any given screen. Every
/// screen in the app pulls from here rather than reaching for ad-hoc
/// colors, so the whole experience reads as one considered object
/// rather than a stack of separately-styled screens.
///
/// Deliberately NOT the dark-ledger palette used elsewhere -- Isolyn is
/// its own product with its own material world (bone/ebony/brass game
/// pieces, not ledger paper), and borrowing a different project's
/// identity here would be a mismatch, not consistency.
enum IsolynTheme {
    // MARK: - Color

    /// The base surface: a warm near-black, closer to aged ebony wood
    /// than to a cold UI black.
    static let ebony = Color(red: 0.071, green: 0.063, blue: 0.051)

    /// A slightly raised surface for cards and panels sitting on top of
    /// `ebony`.
    static let ebonyElevated = Color(red: 0.114, green: 0.102, blue: 0.082)

    /// A third, subtler step -- hairlines, dividers, unselected borders.
    static let ebonyLine = Color(red: 0.22, green: 0.20, blue: 0.17)

    /// Primary text and the pip motif: warm ivory, never stark white.
    static let ivory = Color(red: 0.949, green: 0.925, blue: 0.867)

    /// Secondary text -- captions, helper copy, inactive states.
    static let ivoryMuted = Color(red: 0.949, green: 0.925, blue: 0.867).opacity(0.55)

    /// The single accent color in the entire app. Reserved for the one
    /// primary action on a screen and for the currently-selected state
    /// -- never used decoratively, so it keeps its meaning.
    static let brass = Color(red: 0.737, green: 0.573, blue: 0.283)

    // MARK: - Type

    /// Large, confident display type -- wordmarks, screen titles.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Section and card titles.
    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Body copy, descriptions, button labels.
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// Small labels and eyebrows.
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}
