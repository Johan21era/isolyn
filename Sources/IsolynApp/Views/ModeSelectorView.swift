import SwiftUI

/// Choosing among the three real, engine-backed match formats
/// (`GameMode.hpp`: OneVsOne, OneVsOneVsOne, TwoVsTwo).
///
/// The lobby is deliberately spare: black field, one title, three compact
/// format choices, an inline opponent selector, and one start action. It
/// centers vertically when the window is tall enough and scrolls only when
/// the content genuinely cannot fit.
struct ModeSelectorView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedID: String? = MatchFormat.oneVOne.rawValue
    @State private var opponent: OpponentMode = .human
    @State private var aiLevel: AILevel = .club

    private let options: [ModeOption] = [
        ModeOption(
            id: MatchFormat.oneVOne.rawValue,
            title: "Duel",
            subtitle: "One on one"
        ),
        ModeOption(
            id: MatchFormat.oneVOneVOne.rawValue,
            title: "Three-Way",
            subtitle: "Every player for themself"
        ),
        ModeOption(
            id: MatchFormat.twoVTwo.rawValue,
            title: "Partners",
            subtitle: "Two teams of two"
        ),
    ]

    var body: some View {
        GeometryReader { proxy in
            let padding = IsolynLayout.horizontalPadding(for: proxy.size.width)

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 72)

                        VStack(spacing: 26) {
                            header
                            modeGrid
                            setupControls
                            startArea
                        }
                        .frame(maxWidth: 920)
                        .padding(.horizontal, padding)
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: 72)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)

                topBar(padding: padding)
            }
        }
    }

    private var header: some View {
        Text("Choose your table")
            .font(IsolynTheme.display(32))
            .foregroundStyle(IsolynTheme.ivory)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var modeGrid: some View {
        HStack(spacing: 12) {
            ForEach(options) { option in
                ModeCard(option: option, isSelected: selectedID == option.id) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedID = option.id
                    }
                }
            }
        }
        .frame(maxWidth: 920)
    }

    private var setupControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text("Opponent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IsolynTheme.ivoryMuted)

                HStack(spacing: 0) {
                    ForEach(OpponentMode.allCases) { mode in
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                opponent = mode
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(
                                    opponent == mode ? IsolynTheme.ivory : IsolynTheme.ivoryMuted
                                )
                                .frame(width: 96, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(opponent == mode ? 0.13 : 0))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
            }

            if opponent == .computer {
                HStack(spacing: 14) {
                    Text("Strength")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IsolynTheme.ivoryMuted)

                    Menu {
                        ForEach(AILevel.allCases) { level in
                            Button(level.title) { aiLevel = level }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(aiLevel.title)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IsolynTheme.ivory)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var startArea: some View {
        Button {
            startMatch()
        } label: {
            Text("Start Match")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    selectedID == nil ? IsolynTheme.ivoryMuted.opacity(0.4) : IsolynTheme.ivory
                )
                .frame(width: 300, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(selectedID == nil ? 0.045 : 0.12))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedID == nil)
        .frame(maxWidth: .infinity)
    }

    private func topBar(padding: CGFloat) -> some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.screen = .entry
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, padding)
        .padding(.top, 16)
    }

    private func startMatch() {
        guard let selectedID, let format = MatchFormat(rawValue: selectedID) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            appState.screen = .game(format, opponent, aiLevel)
        }
    }
}
