import SwiftUI
import IsolynEngineBridge

/// Full-screen reveal after a round ends: outcome headline, every hand turned
/// face up (the exact moment physical dominoes would be), points applied this
/// round with animated deltas, next-starter announcement -- and either
/// "Deal Next Round" or the match-winner celebration.
struct RoundEndOverlay: View {
    let viewModel: GameViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                headline
                revealTable
                if !viewModel.scoreDeltas.isEmpty {
                    deltaRow
                }
                nextStarterBanner
                actionButton
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(IsolynTheme.ebonyElevated.opacity(0.97))
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(IsolynTheme.brass.opacity(0.6), lineWidth: 1.5)
            )
            .padding(.horizontal, 60)
        }
    }

    // MARK: - Pieces

    private var headline: some View {
        let text: String
        switch viewModel.finishedOutcome {
        case .dominoVictory(let p): text = "Domino! Player \(p + 1) goes out clean."
        case .closed(let p): text = "Locked. Player \(p + 1) closed the round."
        case .inProgress: text = "Round complete."
        }
        return Text(text)
            .font(IsolynTheme.display(26))
            .foregroundStyle(IsolynTheme.ivory)
            .multilineTextAlignment(.center)
    }

    /// Reveal rows: one per player. For 2v2 both individual values AND team
    /// labels show -- scoring combined them engine-side, but the reveal is
    /// physical: players see hands.
    @ViewBuilder
    private var revealTable: some View {
        if let snap = viewModel.snapshot {
            let isTeams = snap.mode == .twoVTwo
            let rows = Array(0..<snap.playerCount)
            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { p in
                    RevealRow(playerIndex: p,
                              value: snap.finalHandValues[p],
                              showTeamTag: isTeams)
                }
            }
            .padding(.vertical, 6)
        }
    }


    private var deltaRow: some View {
        HStack(spacing: 18) {
            ForEach(Array(viewModel.scoreDeltas.enumerated()), id: \.offset) { i, delta in
                let label = viewModel.snapshot?.mode == .twoVTwo
                    ? (i == 0 ? "Team A" : "Team B") : "P\(i + 1)"
                HStack(spacing: 4) {
                    Text(label).font(IsolynTheme.caption(12))
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(IsolynTheme.title(14))
                        .foregroundStyle(delta > 0 ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                }
            }
        }
    }

    private var nextStarterBanner: some View {
        Group {
            if matchOver { EmptyView() }
            else if let starter = starterFromScoresContext {
                Text("Player \(starter + 1) opens the next round.")
                    .font(IsolynTheme.body(13))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else { EmptyView() }
        }
    }

    /// The coordinator's lastNextStarter survives until dealNextRound; read
    /// through the VM's snapshot of scores state via optional passthrough.
    private var starterFromScoresContext: Int? {
        viewModel.nextStarterForOverlay
    }

    private var matchOver: Bool { viewModel.phase == .matchOver }

    @ViewBuilder
    private var actionButton: some View {
        if matchOver {
            VStack(spacing: 10) {
                Text("Match over.")
                    .font(IsolynTheme.title(16))
                    .foregroundStyle(IsolynTheme.ivory)
                if let w = viewModel.matchWinnerParticipant {
                    Text("\(winnerName(w)) takes the match.")
                        .font(IsolynTheme.body(14))
                        .foregroundStyle(IsolynTheme.brass)
                }
                Button("New Match") {
                    Task { await viewModel.newMatch() }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
            }
        } else {
            Button("Deal Next Round") {
                Task { await viewModel.dealNextRound() }
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
        }
    }

    private func winnerName(_ participant: Int) -> String {
        viewModel.snapshot?.mode == .twoVTwo
            ? "Team \(participant + 1)"
            : "Player \(participant + 1)"
    }
}

/// One line of the reveal table -- extracted as its own view so the ForEach
/// closure stays trivially typed (Cxx-interop mode poisons generic SwiftUI
/// initializer inference otherwise; this sidesteps it entirely).
private struct RevealRow: View {
    let playerIndex: Int
    let value: Int
    let showTeamTag: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(showTeamTag ? "P\(playerIndex + 1)" : "Player \(playerIndex + 1)")
                .font(IsolynTheme.caption(12))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .frame(width: 64, alignment: .leading)

            Text("\(value) pts")
                .font(IsolynTheme.title(15))
                .foregroundStyle(value == 0 ? IsolynTheme.brass : IsolynTheme.ivory)

            if showTeamTag {
                Text(playerIndex % 2 == 0 ? "(Team A)" : "(Team B)")
                    .font(IsolynTheme.caption(11))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Pure display-side rules mirror (team indexing only, for labels) -- never
/// used for decisions; all real math lives engine-side.
private enum RulesOfDisplay {
    static func teamIndex(forPlayer p: Int) -> Int { p % 2 }
}
