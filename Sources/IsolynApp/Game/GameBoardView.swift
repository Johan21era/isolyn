import SwiftUI
import IsolynEngineBridge

/// The game screen. Assembles header (scores/opponents), chain + play zones,
/// rack, controls, analysis drawer, and the round-end/match-over overlays --
/// all driven exclusively by GameViewModel's snapshot projection.
struct GameBoardView: View {
    @State private var viewModel: GameViewModel
    @State private var selectedTile: Tile?
    @Environment(\.scenePhase) private var scenePhase

    init(format: MatchFormat) {
        _viewModel = State(initialValue: GameViewModel(mode: format))
    }

    var body: some View {
        ZStack {
            if let error = viewModel.setupError {
                setupFailure(error)
            } else if viewModel.phase == .loading && viewModel.snapshot == nil {
                ProgressView("Dealing…")
                    .controlSize(.large)
                    .foregroundStyle(IsolynTheme.ivory)
            } else {
                board
            }

            if viewModel.phase == .roundOver || viewModel.phase == .matchOver {
                RoundEndOverlay(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .task { await viewModel.refresh() }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { viewModel.alertError != nil || viewModel.setupError != nil },
                set: { if !$0 { viewModel.dismissAlert() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissAlert() }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Board

    private var board: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(IsolynTheme.ebonyLine)
            chainArea
            Divider().overlay(IsolynTheme.ebonyLine)
            controlsRow
            rack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IsolynTheme.ebony.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.mode.rawValue.uppercased())
                    .font(IsolynTheme.caption(11))
                    .tracking(2)
                    .foregroundStyle(IsolynTheme.brass)
                turnBanner
            }

            Spacer()

            scoreChips

            Spacer()

            opponentCountsView
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    private var turnBanner: some View {
        Group {
            if let snap = viewModel.snapshot, snap.roundOutcome == .inProgress {
                Text("Player \(snap.currentPlayerIndex + 1)'s turn")
                    .font(IsolynTheme.title(15))
                    .foregroundStyle(IsolynTheme.ivory)
            } else {
                Text("Round complete")
                    .font(IsolynTheme.title(15))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
    }

    private var scoreChips: some View {
        let scores = viewModel.participantScores
        let labels = viewModel.mode == .twoVTwo
            ? ["Team A", "Team B"] : (0..<scores.count).map { "P\($0 + 1)" }
        return HStack(spacing: 16) {
            ForEach(Array(scores.enumerated()), id: \.offset) { i, score in
                VStack(spacing: 1) {
                    Text(labels[i])
                        .font(IsolynTheme.caption(10))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                    Text("\(score)")
                        .font(IsolynTheme.display(20))
                        .foregroundStyle(IsolynTheme.ivory)
                        .monospacedDigit()
                }
            }
        }
    }

    private var opponentCountsView: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.opponentCounts, id: \.player) { entry in
                VStack(spacing: 2) {
                    PipGlyph(count: min(max(entry.tiles, 0), 6),
                             color: IsolynTheme.ivoryMuted)
                        .frame(width: 18, height: 18)
                    Text("P\(entry.player + 1): \(entry.tiles)")
                        .font(IsolynTheme.caption(11))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                }
                .accessibilityLabel("Player \(entry.player + 1) holds \(entry.tiles) tiles")
            }
        }
    }

    // MARK: Chain + play zones

    @ViewBuilder
    private var chainArea: some View {
        // Renders only once a REAL bridge snapshot exists -- DTOs are never
        // fabricated on this side of the fence.
        if let snap = viewModel.snapshot {
            VStack(spacing: 10) {
                ChainView(snapshot: snap)
                zoneButtons(for: snap)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }

    private func zoneButtons(for snap: GameSnapshot) -> some View {
        Group {
            if snap.chain.isEmpty {
                if viewModel.canPlayTiles {
                    openChainZone
                }
            } else {
                HStack(spacing: 60) {
                    endZone(side: .left, pip: snap.chainLeftEnd ?? 0)
                    endZone(side: .right, pip: snap.chainRightEnd ?? 0)
                }
            }
        }
    }

    private var openChainZone: some View {
        Button {
            playSelectedOpening()
        } label: {
            Label("Open the chain", systemImage: "plus.diamond")
                .font(IsolynTheme.body(13))
                .foregroundStyle(isSelectedTilePlayable ? IsolynTheme.ebony : IsolynTheme.ivoryMuted)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Capsule().fill(
                    isSelectedTilePlayable ? IsolynTheme.brass : IsolynTheme.ebonyElevated))
        }
        .buttonStyle(.plain)
        .disabled(!isSelectedTilePlayable)
        .accessibilityLabel("Open the chain with the selected domino")
    }

    private func endZone(side: ChainSide, pip: Int) -> some View {
        let playable = selectedSideIsPlayable(side)
        return Button {
            playSelected(on: side)
        } label: {
            VStack(spacing: 3) {
                Text("\(pip)").font(IsolynTheme.display(17)).monospacedDigit()
                Text(side == .left ? "LEFT END" : "RIGHT END")
                    .font(IsolynTheme.caption(9))
                    .tracking(1.5)
            }
            .foregroundStyle(playable ? IsolynTheme.ebony : IsolynTheme.ivoryMuted)
            .padding(.horizontal, 26).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(playable ? IsolynTheme.brass : IsolynTheme.ebonyElevated))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(playable ? IsolynTheme.brass : IsolynTheme.ebonyLine, lineWidth: 1))
            .scaleEffect(playable ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .animation(.easeOut(duration: 0.15), value: playable)
        .accessibilityLabel("\(side == .left ? "Left" : "Right") end showing \(pip)\(playable ? ", ready" : "")")
    }

    // MARK: Controls row

    private var controlsRow: some View {
        HStack(spacing: 18) {
            Button {
                Task { await viewModel.voluntaryDraw() }
            } label: {
                Label(drawLabel, systemImage: "square.stack.3d.down.forward")
            }
            .buttonStyle(.plain)
            .font(IsolynTheme.body(13))
            .foregroundStyle(viewModel.canVoluntaryDraw ? IsolynTheme.ivory : IsolynTheme.ivoryMuted.opacity(0.4))
            .disabled(!viewModel.canVoluntaryDraw)

            Button {
                let believer = viewModel.snapshot?.currentPlayerIndex ?? 0
                Task { await viewModel.toggleAnalysis(believer: believer) }
            } label: {
                Label(viewModel.analysisRunning ? "Cancel analysis" : "Analyze",
                      systemImage: viewModel.analysisRunning
                        ? "stop.circle" : "brain.head.profile")
            }
            .buttonStyle(.plain)
            .font(IsolynTheme.body(13))
            .foregroundStyle(IsolynTheme.ivory)
            .disabled(!viewModel.canPlayTiles && !viewModel.analysisRunning)

            if viewModel.mustPass {
                Button {
                    Task { await viewModel.passTurn() }
                } label: {
                    Text("Pass turn")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
            }

            Spacer()

            if viewModel.analysisRunning {
                ProgressView().controlSize(.small)
            }
            analysisSummary
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }

    private var drawLabel: String {
        let n = viewModel.snapshot?.boneyardDrawableCount ?? 0
        return n > 0 ? "Draw (\(n))" : "Draw"
    }

    /// Recommendation strip: appears only when a COMPLETED analysis exists.
    /// Cancelled/zero-sample runs show their honest one-liner instead.
    @ViewBuilder
    private var analysisSummary: some View {
        if let outcome = viewModel.analysisOutcome {
            HStack(spacing: 8) {
                TileView(tile: outcome.recommendedMove.tile, tileSize: 18,
                         state: .playable)
                Text(outcome.completed
                     ? "engine suggests"
                     : "partial (\(outcome.samplesCompleted)/\(outcome.samplesConfigured))")
                    .font(IsolynTheme.caption(11))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        } else if viewModel.analysisWasCancelled {
            Text("analysis cancelled — no recommendation")
                .font(IsolynTheme.caption(11))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.7))
        }
    }

    // MARK: Rack

    private var rack: some View {
        VStack(spacing: 6) {
            if let snap = viewModel.snapshot {
                HandRackView(
                    hand: snap.ownHand,
                    legalMoves: viewModel.legalMoveSet,
                    selectedTile: $selectedTile,
                    interactive: viewModel.isMyTurn
                ) { move in
                    Task { await viewModel.play(move) }
                }
            }
            Text(hintText)
                .font(IsolynTheme.caption(11))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    private var hintText: String {
        if viewModel.mustPass { return "No moves and the boneyard is dry — pass." }
        if !viewModel.isMyTurn { return "Another player is acting…" }
        guard let s = viewModel.snapshot else { return "" }
        if s.legalMoves.isEmpty { return "Drawing forced tiles…" }
        return selectedTile == nil
            ? "Select a glowing tile, then tap an end."
            : "Tap a highlighted end to place your tile."
    }

    // MARK: Selection plumbing

    private var isSelectedTilePlayable: Bool {
        guard let tile = selectedTile else { return false }
        return !viewModel.legalMoveSet.filter { $0.tile == tile }.isEmpty
    }

    private func selectedSideIsPlayable(_ side: ChainSide) -> Bool {
        guard let tile = selectedTile else { return false }
        return viewModel.legalMoveSet.contains { $0.tile == tile && $0.side == side }
    }

    private func playSelected(on side: ChainSide) {
        guard let tile = selectedTile,
              let move = viewModel.legalMoveSet.first(where: { $0.tile == tile && $0.side == side }) else { return }
        selectedTile = nil
        Task { await viewModel.play(move) }
    }

    private func playSelectedOpening() {
        guard let tile = selectedTile,
              let move = viewModel.legalMoveSet.first(where: { $0.tile == tile }) else { return }
        selectedTile = nil
        Task { await viewModel.play(move) }
    }

    // MARK: Alerts / failure

    private var alertTitle: String { viewModel.setupError != nil ? "Match setup failed" : "Engine said no" }

    private var alertMessage: String {
        if let e = viewModel.setupError { return e }
        switch viewModel.alertError {
        case .staleRequest: return "The board moved on mid-tap. Refreshed — try again."
        case .invalidMove: return "That placement isn't legal right now."
        case .notYourTurn: return "It isn't this seat's turn."
        case .noLegalMove: return "There's no legal move to make here."
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
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(IsolynTheme.brass)
            Text(message)
                .font(IsolynTheme.body(14))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IsolynTheme.ebony.ignoresSafeArea())
    }
}
