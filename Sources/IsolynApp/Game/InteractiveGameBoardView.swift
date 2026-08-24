import SwiftUI
import IsolynEngineBridge

/// Integrates the three interactive systems around the game board:
/// 1. Camera pan (click-drag navigation with inertia)
/// 2. Hover chain (progressive number-family analysis overlay)
/// 3. Settings drawer (live appearance customization)
///
/// Each system is an isolated @Observable class — a camera drag never
/// invalidates hover knowledge; a color change never recomputes the engine.
struct InteractiveGameBoardView: View {
    let format: MatchFormat

    // Core game state
    @State private var viewModel: GameViewModel

    // System 1: Camera
    @State private var camera = BoardCamera()
    @State private var arbiter = GestureArbiter()
    @State private var dragStartLocation: CGPoint? = nil

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
        .alert(alertTitle, isPresented: Binding(
            get: { viewModel.alertError != nil || viewModel.setupError != nil },
            set: { if !$0 { viewModel.dismissAlert() } }
        )) { Button("OK", role: .cancel) { viewModel.dismissAlert() } } message: { Text(alertMessage) }
    }

    // MARK: - Board content (wrapped in camera transform)

    private var boardContent: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(IsolynTheme.ebonyLine)

            // The pannable/zoomable surface
            boardSurface

            Divider().overlay(IsolynTheme.ebonyLine)
            controlsRow
            rackArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IsolynTheme.ebony.ignoresSafeArea())
        .overlay(alignment: .trailing) { settingsEdgeControl }
    }

    // MARK: - Pannable board surface

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
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .clipped()
    }

    // MARK: Header (same as Phase 2, plus time label)

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(format.rawValue.uppercased())
                    .font(IsolynTheme.caption(11)).tracking(2).foregroundStyle(IsolynTheme.brass)
                turnBanner
            }
            Spacer()
            scoreChips
            Spacer()
            opponentCountsView
            EnvironmentTimeLabel()
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
    }

    private var turnBanner: some View {
        Group {
            if let snap = viewModel.snapshot, snap.roundOutcome == .inProgress {
                Text("Player \(snap.currentPlayerIndex + 1)'s turn")
                    .font(IsolynTheme.title(15)).foregroundStyle(IsolynTheme.ivory)
            } else {
                Text("Round complete").font(IsolynTheme.title(15)).foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
    }

    private var scoreChips: some View {
        let scores = viewModel.participantScores
        let labels = viewModel.mode == .twoVTwo ? ["Team A", "Team B"] : (0..<scores.count).map { "P\($0+1)" }
        return HStack(spacing: 16) {
            ForEach(Array(scores.enumerated()), id: \.offset) { i, score in
                VStack(spacing: 1) {
                    Text(labels[i]).font(IsolynTheme.caption(10)).foregroundStyle(IsolynTheme.ivoryMuted)
                    Text("\(score)").font(IsolynTheme.display(20)).foregroundStyle(IsolynTheme.ivory).monospacedDigit()
                }
            }
        }
    }

    private var opponentCountsView: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.opponentCounts, id: \.player) { entry in
                VStack(spacing: 2) {
                    PipGlyph(count: min(max(entry.tiles, 0), 6), color: IsolynTheme.ivoryMuted)
                        .frame(width: 18, height: 18)
                    Text("P\(entry.player+1): \(entry.tiles)")
                        .font(IsolynTheme.caption(11)).foregroundStyle(IsolynTheme.ivoryMuted)
                }.accessibilityLabel("Player \(entry.player+1) holds \(entry.tiles) tiles")
            }
        }
    }

    // MARK: Controls row

    private var controlsRow: some View {
        HStack(spacing: 18) {
            drawButton
            analysisButton
            cameraResetButton
            passButton
            Spacer()
            if viewModel.analysisRunning { ProgressView().controlSize(.small) }
            analysisSummary
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
    }

    private var drawButton: some View {
        let n = viewModel.snapshot?.boneyardDrawableCount ?? 0
        return Button { Task { await viewModel.voluntaryDraw() } } label: {
            Label(n > 0 ? "Draw (\(n))" : "Draw", systemImage: "square.stack.3d.down.forward")
        }
        .buttonStyle(.plain).font(IsolynTheme.body(13))
        .foregroundStyle(viewModel.canVoluntaryDraw ? IsolynTheme.ivory : IsolynTheme.ivoryMuted.opacity(0.4))
        .disabled(!viewModel.canVoluntaryDraw)
    }

    private var analysisButton: some View {
        Button {
            let believer = viewModel.snapshot?.currentPlayerIndex ?? 0
            Task { await viewModel.toggleAnalysis(believer: believer) }
        } label: {
            Label(viewModel.analysisRunning ? "Cancel" : "Analyze",
                  systemImage: viewModel.analysisRunning ? "stop.circle" : "brain.head.profile")
        }
        .buttonStyle(.plain).font(IsolynTheme.body(13)).foregroundStyle(IsolynTheme.ivory)
        .disabled(!viewModel.canPlayTiles && !viewModel.analysisRunning)
    }

    private var cameraResetButton: some View {
        Button {
            camera.reset()
            arbiter.cancel()
        } label: {
            Image(systemName: "arrow.uturn.backward.center")
        }
        .buttonStyle(.plain).font(IsolynTheme.body(13))
        .foregroundStyle(camera.offsetX != 0 || camera.offsetY != 0 ? IsolynTheme.brass : IsolynTheme.ivoryMuted.opacity(0.3))
        .accessibilityLabel("Reset board position")
    }

    @ViewBuilder
    private var passButton: some View {
        if viewModel.mustPass {
            Button("Pass turn") { Task { await viewModel.passTurn() } }
                .buttonStyle(PrimaryCapsuleButtonStyle())
        }
    }

    @ViewBuilder
    private var analysisSummary: some View {
        if let outcome = viewModel.analysisOutcome {
            HStack(spacing: 8) {
                TileView(tile: outcome.recommendedMove.tile, tileSize: 18, state: .playable)
                Text(outcome.completed ? "engine suggests" : "partial (\(outcome.samplesCompleted)/\(outcome.samplesConfigured))")
                    .font(IsolynTheme.caption(11)).foregroundStyle(IsolynTheme.ivoryMuted)
            }
        } else if viewModel.analysisWasCancelled {
            Text("analysis cancelled").font(IsolynTheme.caption(11))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.7))
        }
    }

    // MARK: Rack

    private var rackArea: some View {
        VStack(spacing: 6) {
            if let snap = viewModel.snapshot {
                HandRackView(
                    hand: snap.ownHand,
                    legalMoves: viewModel.legalMoveSet,
                    selectedTile: $selectedTile,
                    interactive: viewModel.isMyTurn
                ) { move in Task { await viewModel.play(move) } }
            }
            Text(hintText).font(IsolynTheme.caption(11))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.75))
        }
        .frame(maxWidth: .infinity).padding(.bottom, 16)
    }

    private var hintText: String {
        if viewModel.mustPass { return "No moves and the boneyard is dry — pass." }
        if !viewModel.isMyTurn { return "Another player is acting…" }
        guard let s = viewModel.snapshot else { return "" }
        if s.legalMoves.isEmpty { return "Drawing forced tiles…" }
        return selectedTile == nil ? "Select a glowing tile, then tap an end." : "Tap a highlighted end to place."
    }

    // MARK: Settings edge control + drawer

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

    // MARK: Alerts / failure

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
}
