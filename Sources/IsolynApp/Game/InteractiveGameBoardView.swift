import SwiftUI
import IsolynEngineBridge

/// The game screen (dominoes_ui_fix_non_negotiable.md §28 composition):
///
///     HEADER      mode · turn · scores            (compact, dense)
///     BOARD       the snake chain                 (primary visual object)
///     ACTIONS     Draw / Analyze / Reset view     (intentional controls)
///     HAND        canonical dominoes              (immediately recognizable)
///     STATUS      instruction · opponents         (secondary, quiet)
///
/// Integrates the hardened interaction systems unchanged: camera pan,
/// gesture arbitration, hover-chain overlay, appearance settings.
struct InteractiveGameBoardView: View {
    let format: MatchFormat

    // Core game state
    @State private var viewModel: GameViewModel

    // System 1: Camera
    @State private var camera = BoardCamera()
    @State private var arbiter = GestureArbiter()

    // System 2: Hover chain
    @State private var hoverController = HoverChainController()

    // System 3: Appearance + settings drawer
    @State private var appearanceManager = AppearanceManager()
    @State private var settingsOpen = false

    // Selection
    @State private var selectedTile: Tile?

    init(format: MatchFormat) {
        self.format = format
        _viewModel = State(initialValue: GameViewModel(mode: format))
    }

    var body: some View {
        ZStack {
            if let error = viewModel.setupError {
                setupFailure(error)
            } else if viewModel.phase == .loading && viewModel.snapshot == nil {
                ProgressView("Dealing…").controlSize(.large).foregroundStyle(IsolynTheme.ivory)
            } else {
                boardContent
            }

            if viewModel.phase == .roundOver || viewModel.phase == .matchOver {
                RoundEndOverlay(viewModel: viewModel).transition(.opacity)
            }

            settingsDrawerOverlay
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .animation(.easeInOut(duration: 0.25), value: settingsOpen)
        .task { await viewModel.refresh() }
        // FIX-16 contract: leaving the screen always cancels analyses and
        // closes bridge handles.
        .onDisappear { viewModel.shutdown() }
        .alert(alertTitle, isPresented: Binding(
            get: { viewModel.alertError != nil || viewModel.setupError != nil },
            set: { if !$0 { viewModel.dismissAlert() } }
        )) { Button("OK", role: .cancel) { viewModel.dismissAlert() } } message: { Text(alertMessage) }
    }

    // MARK: - Layout skeleton (§28 hierarchy — order is law)

    private var boardContent: some View {
        VStack(spacing: 0) {
            header                                  // compact, info-dense
            Divider().overlay(IsolynTheme.ebonyLine)

            boardSurface                            // primary visual object

            Divider().overlay(IsolynTheme.ebonyLine)
            actionBar                               // intentional controls
            handArea                                // the player's dominoes
            Divider().overlay(IsolynTheme.ebonyLine.opacity(0.6))
            statusStrip                             // secondary information
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IsolynTheme.ebony.ignoresSafeArea())
        .overlay(alignment: .trailing) { settingsEdgeControl }
    }

    // MARK: Board surface

    private var boardSurface: some View {
        ChainAndZonesView(
            snapshot: viewModel.snapshot,
            canPlay: viewModel.canPlayTiles,
            appearance: appearanceManager.appearance,
            selectedTile: $selectedTile,
            camera: camera,
            arbiter: arbiter,
            hoverController: hoverController,
            onPlay: { move in Task { await viewModel.play(move) } }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // board owns the main region (§26 P1)
        .clipped()
    }

    // MARK: Header (§11: mode · turn · player-score-score-player)

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(format.rawValue.uppercased())
                    .font(IsolynTheme.caption(12)).tracking(2).foregroundStyle(IsolynTheme.brass)
                turnBanner
            }

            Spacer()

            scoreBar

            Spacer()

            EnvironmentTimeLabel()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var turnBanner: some View {
        Group {
            if let snap = viewModel.snapshot, snap.roundOutcome == .inProgress {
                Text("Player \(snap.currentPlayerIndex + 1)'s turn")
                    .font(IsolynTheme.title(15)).foregroundStyle(IsolynTheme.ivory)
            } else {
                Text("Round complete")
                    .font(IsolynTheme.title(15)).foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
    }

    /// Compact score containers flanking a shared brass label — the exact
    /// `[ Player 1 ]  SCORE  [ Player 2 ]` hierarchy from §11/§12.
    private var scoreBar: some View {
        let scores = viewModel.participantScores
        let names = participantNames(count: max(scores.count, 2))
        return HStack(spacing: 12) {
            if scores.isEmpty {
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    scoreChip(name: name, score: nil, highlight: i == currentParticipantIndex)
                }
            } else {
                ForEach(Array(scores.enumerated()), id: \.offset) { i, score in
                    scoreChip(name: names[i], score: score, highlight: i == currentParticipantIndex)
                }
            }
        }
    }

    private var currentParticipantIndex: Int {
        guard let s = viewModel.snapshot else { return 0 }
        return viewModel.mode == .twoVTwo ? s.currentPlayerIndex % 2 : s.currentPlayerIndex
    }

    private func participantNames(count: Int) -> [String] {
        viewModel.mode == .twoVTwo
            ? (0..<max(count, 2)).map { $0 == 0 ? "TEAM A" : "TEAM B" }
            : (0..<max(count, 2)).map { "PLAYER \($0 + 1)" }
    }

    private func scoreChip(name: String, score: Int?, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(IsolynTheme.caption(10)).tracking(1.5)
                .foregroundStyle(highlight ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
            Text(score.map(String.init) ?? "0")
                .font(IsolynTheme.display(20)).monospacedDigit()
                .foregroundStyle(highlight ? IsolynTheme.ivory : IsolynTheme.ivoryMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(IsolynTheme.ebonyElevated.opacity(highlight ? 1 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(highlight ? IsolynTheme.brass.opacity(0.55) : IsolynTheme.ebonyLine,
                              lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) score \(score ?? 0)\(highlight ? ", acting now" : "")")
    }

    // MARK: Action bar (§13: icon + label + real hit areas)

    private var actionBar: some View {
        HStack(spacing: 12) {
            actionButton(
                title: viewModel.canVoluntaryDraw ? "Draw (\(viewModel.snapshot?.boneyardDrawableCount ?? 0))" : "Draw",
                systemImage: "square.stack.3d.down.forward",
                enabled: viewModel.canVoluntaryDraw
            ) { Task { await viewModel.voluntaryDraw() } }

            actionButton(
                title: viewModel.analysisRunning ? "Cancel" : "Analyze",
                systemImage: viewModel.analysisRunning ? "stop.circle" : "brain.head.profile",
                enabled: viewModel.canPlayTiles || viewModel.analysisRunning
            ) { Task { await toggleAnalysis() } }

            actionButton(
                title: "Reset View",
                systemImage: "arrow.uturn.backward.center",
                enabled: camera.offsetX != 0 || camera.offsetY != 0
            ) {
                camera.reset()
                arbiter.cancel()
            }

            if viewModel.mustPass {
                Button { Task { await viewModel.passTurn() } } label: {
                    Label("Pass Turn", systemImage: "forward.end")
                        .font(IsolynTheme.body(13))
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
            }

            Spacer()

            if viewModel.analysisRunning {
                ProgressView().controlSize(.small)
            }
            analysisSummary
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    /// One coherent control treatment for every gameplay action: icon +
    /// label inside a fixed-height chip with hover/disabled states (§13).
    private func actionButton(title: String, systemImage: String,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(IsolynTheme.body(13))
                .foregroundStyle(enabled ? IsolynTheme.ivory : IsolynTheme.ivoryMuted.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(IsolynTheme.ebonyElevated.opacity(enabled ? 0.9 : 0.45))
                )
                .overlay(
                    Capsule().strokeBorder(
                        enabled ? IsolynTheme.ebonyLine : IsolynTheme.ebonyLine.opacity(0.4),
                        lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var analysisSummary: some View {
        if let outcome = viewModel.analysisOutcome {
            HStack(spacing: 8) {
                IsolynDominoTile(leftPips: outcome.recommendedMove.tile.low,
                                 rightPips: outcome.recommendedMove.tile.high,
                                 height: 14, state: .playable)
                Text(outcome.completed ? "engine suggests" : "partial (\(outcome.samplesCompleted)/\(outcome.samplesConfigured))")
                    .font(IsolynTheme.caption(12)).foregroundStyle(IsolynTheme.ivoryMuted)
            }
        } else if viewModel.analysisWasCancelled {
            Text("analysis cancelled").font(IsolynTheme.caption(12))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.7))
        }
    }

    // MARK: Hand (§9)

    private var handArea: some View {
        Group {
            if let snap = viewModel.snapshot {
                HandRackView(
                    hand: snap.ownHand,
                    legalMoves: viewModel.legalMoveSet,
                    selectedTile: $selectedTile,
                    interactive: viewModel.isMyTurn
                ) { move in Task { await viewModel.play(move) } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    // MARK: Status strip (§14: secondary, centered instruction + opponents)

    private var statusStrip: some View {
        HStack(spacing: 16) {
            opponentCounts
            Spacer()
            Text(hintText)   // §14: 12–13px, muted, centered by the spacer pair
                .font(IsolynTheme.caption(12))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.85))
                .multilineTextAlignment(.center)
            Spacer()
            Color.clear.frame(width: 120) // balances opponents block so the hint truly centers
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var opponentCounts: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.opponentCounts, id: \.player) { entry in
                HStack(spacing: 4) {
                    Text("P\(entry.player + 1)")
                        .font(IsolynTheme.caption(11)).tracking(1)
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Text("\(entry.tiles)")
                        .font(IsolynTheme.body(13)).monospacedDigit()
                        .foregroundStyle(IsolynTheme.ivory)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Player \(entry.player + 1) holds \(entry.tiles) tiles")
            }
        }
    }

    private var hintText: String {
        if viewModel.mustPass { return "No moves and the boneyard is dry — pass." }
        if !viewModel.isMyTurn { return "Another player is acting…" }
        guard let s = viewModel.snapshot else { return "" }
        if s.legalMoves.isEmpty { return "Drawing forced tiles…" }
        return selectedTile == nil
            ? "Select a glowing domino, then tap its end marker."
            : "Tap the highlighted end marker to place."
    }

    // MARK: Settings edge control + drawer (unchanged systems)

    private var settingsEdgeControl: some View {
        Button { settingsOpen.toggle(); arbiter.cancel() } label: {
            Image(systemName: settingsOpen ? "chevron.right" : "paintbrush")
                .font(.system(size: 13))
                .foregroundStyle(settingsOpen ? IsolynTheme.ivoryMuted : IsolynTheme.brass)
                .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settingsOpen ? "Close settings" : "Open appearance settings")
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var settingsDrawerOverlay: some View {
        if settingsOpen {
            HStack(spacing: 0) {
                Spacer().allowsHitTesting(false)
                SettingsDrawer(isOpen: $settingsOpen, appearanceManager: appearanceManager) {
                    withAnimation(.easeInOut(duration: 0.25)) { settingsOpen = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .zIndex(100)
        }
    }

    // MARK: Alerts / failure (unchanged)

    private var alertTitle: String { viewModel.setupError != nil ? "Match setup failed" : "Engine said no" }
    private var alertMessage: String {
        if let e = viewModel.setupError { return e }
        switch viewModel.alertError {
        case .staleRequest: return "The board moved on mid-tap. Refreshed — try again."
        case .invalidMove: return "That placement isn't legal right now."
        case .notYourTurn: return "It isn't this seat's turn."
        case .noLegalMove: return "No legal move here."
        case .boneyardEmpty: return "The boneyard is empty."
        case .roundAlreadyOver: return "This round already finished."
        case .sessionClosed: return "The round session was closed."
        case .invalidRequest: return "That request didn't make sense to the engine."
        case .engineFailure(let d), .bridgeFailure(let d): return d
        case .none: return "Something went wrong."
        }
    }

    private func setupFailure(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(IsolynTheme.brass)
            Text(message).font(IsolynTheme.body(14)).foregroundStyle(IsolynTheme.ivoryMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(IsolynTheme.ebony.ignoresSafeArea())
    }

    private func toggleAnalysis() async {
        let believer = viewModel.snapshot?.currentPlayerIndex ?? 0
        await viewModel.toggleAnalysis(believer: believer)
    }
}
