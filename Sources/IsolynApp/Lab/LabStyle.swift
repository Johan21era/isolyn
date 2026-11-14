import SwiftUI

/// The Lab's shared surfaces. Softer than the game screens on purpose: the lab
/// is a workspace, not a table, so cards get a quiet gradient, a hairline and a
/// soft shadow instead of hard edges.
struct LabCard: ViewModifier {
    var emphasised: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [IsolynTheme.ebonyElevated, IsolynTheme.ebony.opacity(0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(IsolynTheme.ebonyLine.opacity(emphasised ? 0.9 : 0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 5)
    }
}

extension View {
    func labCard(emphasised: Bool = false) -> some View {
        modifier(LabCard(emphasised: emphasised))
    }
}

struct LabStatusPill: View {
    enum Tone {
        case active, finished, paused, failed
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(IsolynTheme.caption(10))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch tone {
        case .active, .finished: return IsolynTheme.brass
        case .paused: return IsolynTheme.ivoryMuted
        case .failed: return Color(red: 0.85, green: 0.42, blue: 0.36)
        }
    }

    private var background: Color {
        switch tone {
        case .active, .finished: return IsolynTheme.brass.opacity(0.14)
        case .paused: return IsolynTheme.ebonyLine.opacity(0.35)
        case .failed: return Color(red: 0.72, green: 0.28, blue: 0.24).opacity(0.18)
        }
    }
}

struct LabSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(IsolynTheme.caption(10))
            .tracking(2)
            .foregroundStyle(IsolynTheme.ivoryMuted)
    }
}

/// A quiet secondary action, used where a full button would compete.
struct LabLink: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(IsolynTheme.caption(12))
                .foregroundStyle(IsolynTheme.brass)
        }
        .buttonStyle(.plain)
    }
}
