import SwiftUI
import IsolynEngineBridge

/// Round end, reduced to the same visual language as the table: black field,
/// one headline, the actual remaining hands turned face up, and one wide
/// action. The reveal is staged rather than presented as a static table.
struct RoundEndOverlay: View {
    let viewModel: GameViewModel
    let appearance: DominoAppearance
    /// Closing the summary reveals the finished board, which is worth looking
    /// at: the final layout is the physical result of the round. Without this
    /// there was no way to inspect it, only to deal again.
    var onDismiss: () -> Void = {}

    @State private var revealed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.94).ignoresSafeArea()

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        VStack(spacing: 22) {
                            headline
                            revealTable
                            if !viewModel.scoreDeltas.isEmpty {
                                deltaRow
                            }
                            setSummary
                            nextStarterBanner
                            actionButton
                        }
                        .frame(maxWidth: 520)
                        .padding(.horizontal, 28)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)

                // LAST child on purpose: a ZStack stacks later children on top,
                // and the scroll view above covers the whole surface -- placed
                // before it, this button was unreachable and × did nothing.
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(IsolynTheme.ivoryMuted)
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close the summary and view the board")
                        .padding(.top, 16)
                        .padding(.trailing, 18)
                    }
                    Spacer()
                }
                .zIndex(10)
            }
            .onAppear {
                revealed = false
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.42)) { revealed = true }
                }
            }
        }
    }

    // MARK: - Pieces

    private var headline: some View {
        let text: String
        switch viewModel.finishedOutcome {
        case .dominoVictory(let p): text = "Player \(p + 1) goes out."
        case .closed(let p): text = "Player \(p + 1) closes the round."
        case .inProgress: text = "Round complete."
        }
        return Text(text)
            .font(IsolynTheme.display(27))
            .foregroundStyle(IsolynTheme.ivory)
            .multilineTextAlignment(.center)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 10)
    }

    @ViewBuilder
    private var revealTable: some View {
        if let snap = viewModel.snapshot {
            let isTeams = snap.mode == .twoVTwo
            VStack(spacing: 0) {
                ForEach(Array(0..<snap.playerCount), id: \.self) { p in
                    RevealRow(
                        playerIndex: p,
                        value: snap.finalHandValues.indices.contains(p) ? snap.finalHandValues[p] : 0,
                        tiles: snap.revealedHands.indices.contains(p) ? snap.revealedHands[p] : [],
                        showTeamTag: isTeams,
                        appearance: appearance
                    )
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 14)
                    .animation(
                        .easeOut(duration: 0.36).delay(0.08 + Double(p) * 0.07),
                        value: revealed
                    )

                    if p < snap.playerCount - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var deltaRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(viewModel.scoreDeltas.enumerated()), id: \.offset) { i, delta in
                let label = viewModel.snapshot?.mode == .twoVTwo
                    ? (i == 0 ? "Team A" : "Team B") : "Player \(i + 1)"
                Text("\(label) \(delta > 0 ? "+" : "")\(delta)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IsolynTheme.ivory)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.075)))
            }
        }
        .opacity(revealed ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.3), value: revealed)
    }

    @ViewBuilder
    private var setSummary: some View {
        if !viewModel.setWins.isEmpty {
            VStack(spacing: 7) {
                if viewModel.lastSetEnded, let setWinner = viewModel.setWinnerForOverlay {
                    Text("Set \(viewModel.setNumber) to \(participantName(setWinner)).")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(IsolynTheme.brass)
                }
                Text(setWinsText + "  ·  first to \(viewModel.matchSetsToWin)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
            .multilineTextAlignment(.center)
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.32), value: revealed)
        }
    }

    private var nextStarterBanner: some View {
        Group {
            if matchOver {
                EmptyView()
            } else if viewModel.nextRoundStartsSet {
                Text("Set \(viewModel.setNumber + 1) opens with the double-six ritual.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else if let starter = viewModel.nextStarterForOverlay {
                Text("\(participantName(starter)) opens the next round.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                EmptyView()
            }
        }
        .opacity(revealed ? 1 : 0)
    }

    private var setWinsText: String {
        viewModel.setWins.enumerated()
            .map { "\(participantName($0.offset)) \($0.element)" }
            .joined(separator: "  ·  ")
    }

    private func participantName(_ participant: Int) -> String {
        viewModel.snapshot?.mode == .twoVTwo
            ? "Team \(participant + 1)"
            : "Player \(participant + 1)"
    }

    private var matchOver: Bool { viewModel.phase == .matchOver }

    @ViewBuilder
    private var actionButton: some View {
        if matchOver {
            VStack(spacing: 8) {
                Text("Match over")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                if let w = viewModel.matchWinnerParticipant {
                    Text("\(winnerName(w)) takes it.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(IsolynTheme.brass)
                }
                wideButton("New Match") {
                    Task { await viewModel.newMatch() }
                }
            }
        } else {
            wideButton(viewModel.lastSetEnded ? "Deal next set" : "Deal next round") {
                Task { await viewModel.dealNextRound() }
            }
        }
    }

    private func wideButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IsolynTheme.ivory)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 380)
        .disabled(!revealed)
        .opacity(revealed ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.34), value: revealed)
    }

    private func winnerName(_ participant: Int) -> String {
        participantName(participant)
    }
}

private struct RevealRow: View {
    let playerIndex: Int
    let value: Int
    let tiles: [Tile]
    let showTeamTag: Bool
    let appearance: DominoAppearance

    @State private var tilesFlipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(showTeamTag ? "P\(playerIndex + 1)" : "Player \(playerIndex + 1)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted)

                if showTeamTag {
                    Text(playerIndex % 2 == 0 ? "A" : "B")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }

                Spacer(minLength: 0)

                Text("\(value)")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? IsolynTheme.brass : IsolynTheme.ivory)
            }

            if tiles.isEmpty {
                Text(value == 0 ? "Went out" : "No tiles")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.65))
                    .frame(height: 17)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 3) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                            IsolynDominoTile(
                                low: tile.low,
                                high: tile.high,
                                height: 17,
                                appearance: appearance
                            )
                            .rotation3DEffect(
                                .degrees(tilesFlipped ? 0 : -86),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .center
                            )
                            .opacity(tilesFlipped ? 1 : 0)
                            .animation(
                                .easeOut(duration: 0.26)
                                    .delay(Double(index) * 0.035),
                                value: tilesFlipped
                            )
                            .accessibilityLabel("\(tile.high)-\(tile.low)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 17)
            }
        }
        .padding(.vertical, 9)
        .onAppear {
            tilesFlipped = false
            DispatchQueue.main.async {
                withAnimation { tilesFlipped = true }
            }
        }
    }
}
