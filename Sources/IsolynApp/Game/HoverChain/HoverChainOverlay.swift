import SwiftUI
import IsolynEngineBridge

/// A small, quiet number-family inspector. It is opened explicitly by the
/// configured mouse button (right-click by default), never by incidental
/// proximity unless the player turns auto-hover on in Settings.
struct HoverChainOverlay: View {
    let chain: HoverChain
    let appearance: DominoAppearance
    var onClose: (() -> Void)? = nil

    // Semantic colors are intentionally distinct from the customizable
    // domino body. They only communicate knowledge state.
    private static let semanticColors: [TileKnowledge: Color] = [
        .historical: Color(red: 0.62, green: 0.59, blue: 0.53),
        .mine: Color(red: 0.25, green: 0.72, blue: 0.38),
        .unknown: Color(red: 0.42, green: 0.44, blue: 0.48),
        .lockedOff: Color(red: 0.36, green: 0.48, blue: 0.85),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            tileRow
            footer
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Family \(chain.targetNumber)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IsolynTheme.ivory)

            Spacer()

            Text(chain.activeNodeKind == .complete ? "OVERVIEW" : chain.activeNodeKind.label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.38))

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close number family inspector")
            }
        }
    }

    private var tileRow: some View {
        HStack(spacing: 4) {
            ForEach(chain.entries) { entry in
                IsolynDominoTile(
                    displayingLeft: entry.low,
                    right: entry.high,
                    isDouble: entry.isDouble,
                    height: 20,
                    appearance: appearance,
                    semanticEdge: shouldShowEdge(for: entry.knowledge)
                        ? edgeColor(for: entry.knowledge)
                        : nil
                )
                .accessibilityLabel("\(entry.label), \(knowledgeLabel(entry.knowledge))")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if chain.activeNodeKind == .baseUninformed {
            Text("All dominoes containing \(chain.targetNumber).")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.34))
        } else {
            HStack(spacing: 9) {
                legend("played", color: Self.semanticColors[.historical] ?? .gray)
                legend("yours", color: Self.semanticColors[.mine] ?? .gray)
                legend("unknown", color: Self.semanticColors[.unknown] ?? .gray)
                legend("locked", color: Self.semanticColors[.lockedOff] ?? .gray)
                if chain.activeNodeKind == .predictive || chain.activeNodeKind == .complete {
                    legend("predicted", color: Color(red: 0.94, green: 0.3, blue: 0.22))
                }
            }
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 2, height: 8)
            Text(title)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    private func edgeColor(for knowledge: TileKnowledge) -> Color {
        switch knowledge {
        case .predictedOpponent(let probability):
            return Color(red: 0.94, green: 0.3, blue: 0.22)
                .opacity(min(probability / 0.7, 1))
        default:
            return Self.semanticColors[knowledge] ?? Color.white.opacity(0.4)
        }
    }

    private func shouldShowEdge(for knowledge: TileKnowledge) -> Bool {
        switch chain.activeNodeKind {
        case .baseUninformed:
            return false
        case .historicalInformed:
            return knowledge == .historical
        case .presentInformed:
            return knowledge == .mine || knowledge == .unknown
        case .lockedOff:
            return knowledge == .lockedOff
        case .predictive:
            if case .predictedOpponent = knowledge { return true }
            return false
        case .complete:
            return true
        }
    }

    private func knowledgeLabel(_ knowledge: TileKnowledge) -> String {
        switch knowledge {
        case .historical: return "played"
        case .mine: return "yours"
        case .unknown: return "unknown"
        case .lockedOff: return "locked off"
        case .predictedOpponent(let probability): return "predicted opponent (\(Int(probability * 100))%)"
        }
    }
}
