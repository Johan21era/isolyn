import SwiftUI

/// Choosing among the three real, engine-backed match formats
/// (`GameMode.hpp`: OneVsOne, OneVsOneVsOne, TwoVsTwo). Each card's pip
/// glyphs are literally the player count on that side, not a generic
/// icon standing in for it.
struct ModeSelectorView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedID: String?
    @State private var opponent: OpponentMode = .human
    @State private var aiLevel: AILevel = .club

    private let options: [ModeOption] = [
        ModeOption(
            id: MatchFormat.oneVOne.rawValue,
            title: "Head to Head",
            subtitle: "One on one",
            detail: "The purest form of the game -- every tile you hold, your opponent is trying to place against you.",
            pipCounts: [1, 1]
        ),
        ModeOption(
            id: MatchFormat.oneVOneVOne.rawValue,
            title: "Three-Way",
            subtitle: "Every player for themself",
            detail: "No partners, no safety net. Three hands, three separate plans, one board.",
            pipCounts: [1, 1, 1]
        ),
        ModeOption(
            id: MatchFormat.twoVTwo.rawValue,
            title: "Partners",
            subtitle: "Two teams of two",
            detail: "You can't see your partner's hand -- but you can learn to read it.",
            pipCounts: [2, 2]
        ),
    ]

    var body: some View {
        ZStack {
            // Background is `EnvironmentView` behind the screen switcher
            // in `RootView` -- see `EntryView` for the same note.

            VStack(alignment: .leading, spacing: 0) {
                backButton
                    .padding(.top, 28)
                    .padding(.leading, 40)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose your match")
                        .font(IsolynTheme.display(32))
                        .foregroundStyle(IsolynTheme.ivory)
                    Text("You can change this before every game.")
                        .font(IsolynTheme.body(14))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .padding(.top, 32)
                .padding(.horizontal, 40)

                HStack(alignment: .top, spacing: 20) {
                    ForEach(options) { option in
                        ModeCard(option: option, isSelected: selectedID == option.id) {
                            selectedID = option.id
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 36)

                HStack(spacing: 18) {
                    Text("Opponent")
                        .font(IsolynTheme.caption(11))
                        .tracking(1.5)
                        .foregroundStyle(IsolynTheme.ivoryMuted)

                    Picker("Opponent", selection: $opponent) {
                        ForEach(OpponentMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)

                    if opponent == .computer {
                        Text("Strength")
                            .font(IsolynTheme.caption(11))
                            .tracking(1.5)
                            .foregroundStyle(IsolynTheme.ivoryMuted)

                        Picker("Strength", selection: $aiLevel) {
                            ForEach(AILevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 22)

                Spacer()

                HStack {
                    Spacer()
                    Button {
                        startMatch()
                    } label: {
                        Text("Start")
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(selectedID == nil)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    private func startMatch() {
        guard let selectedID, let format = MatchFormat(rawValue: selectedID) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            appState.screen = .game(format, opponent, aiLevel)
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                appState.screen = .entry
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .font(IsolynTheme.body(14))
            .foregroundStyle(IsolynTheme.ivoryMuted)
        }
        .buttonStyle(.plain)
    }
}
