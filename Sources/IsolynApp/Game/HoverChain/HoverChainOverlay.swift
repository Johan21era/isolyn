import SwiftUI
import IsolynEngineBridge

/// Visual overlay showing the hover chain for one target number.
/// Displays all 7 number-family dominoes with their knowledge-classification
/// edge treatment, plus the active node indicator.
///
/// Deliberately compact — this is an analytical lens, not a dashboard.
struct HoverChainOverlay: View {
    let chain: HoverChain
    let appearance: DominoAppearance

    // Semantic colors — centralized, distinct from user-customizable colors
    private static let semanticColors: [TileKnowledge: Color] = [
        .historical: Color(red: 0.45, green: 0.42, blue: 0.38),  // restrained warm gray-brown
        .mine: Color(red: 0.12, green: 0.55, blue: 0.20),         // dark vibrant green
        .unknown: Color(red: 0.28, green: 0.28, blue: 0.30),      // dark gray
        .lockedOff: Color(red: 0.15, green: 0.22, blue: 0.48),    // midnight creamy blue
        // Predictive is dynamic per-probability, handled inline
    ]

    var body: some View {
        VStack(spacing: 10) {
            header
            tileRow
            nodeIndicator
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IsolynTheme.ebonyElevated.opacity(0.96))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(IsolynTheme.ebonyLine, lineWidth: 1)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("TARGET: \(chain.targetNumber)")
                .font(IsolynTheme.title(14))
                .foregroundStyle(IsolynTheme.brass)
            Spacer()
            Text("\(chain.activeNodeKind.label) — \(chain.activeNodeKind.rawValue + 1) / \(HoverChainNodeKind.allCases.count)")
                .font(IsolynTheme.caption(11))
                .foregroundStyle(IsolynTheme.ivoryMuted)
        }
    }

    // MARK: Tile row

    private var tileRow: some View {
        HStack(spacing: 6) {
            ForEach(chain.entries) { entry in
                entryView(entry)
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: HoverChainEntry) -> some View {
        let edgeColor = edgeColor(for: entry.knowledge)
        let showEdge = shouldShowEdge(for: entry.knowledge)

        TileView(
            displayingLeft: displayLeft(entry),
            right: displayRight(entry),
            isDouble: entry.isDouble,
            tileSize: 22,
            state: .idle
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(edgeColor, lineWidth: showEdge ? 2 : 0)
                .opacity(showEdge ? 1 : 0)
        )
        .accessibilityLabel("\(entry.label) — \(knowledgeLabel(entry.knowledge))")
    }

    /// In the base-uninformed node, ALL tiles render as canonical low|high.
    /// In informed nodes, tiles still show their identity but the EDGE carries
    /// the classification signal (never the body/pip colors).
    private func displayLeft(_ entry: HoverChainEntry) -> Int { entry.low }
    private func displayRight(_ entry: HoverChainEntry) -> Int { entry.high }

    // MARK: Node indicator

    private var nodeIndicator: some View {
        Text(chain.activeNodeKind.description)
            .font(IsolynTheme.caption(10))
            .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    // MARK: Edge color resolution

    private func edgeColor(for knowledge: TileKnowledge) -> Color {
        switch knowledge {
        case .predictedOpponent(let prob):
            // Bright tangy red, opacity scaled by confidence for honesty
            return Color(red: 0.95, green: 0.25, blue: 0.15).opacity(min(prob / 0.7, 1.0))
        default:
            return Self.semanticColors[knowledge] ?? IsolynTheme.ivoryMuted
        }
    }

    private func shouldShowEdge(for knowledge: TileKnowledge) -> Bool {
        switch chain.activeNodeKind {
        case .baseUninformed:
            return false // base shows no classification edges at all
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
            return true // show every classification's edge
        }
    }

    private func knowledgeLabel(_ knowledge: TileKnowledge) -> String {
        switch knowledge {
        case .historical: return "played"
        case .mine: return "yours"
        case .unknown: return "unknown"
        case .lockedOff: return "locked off"
        case .predictedOpponent(let p): return "predicted opponent (\(Int(p * 100))%)"
        }
    }
}
