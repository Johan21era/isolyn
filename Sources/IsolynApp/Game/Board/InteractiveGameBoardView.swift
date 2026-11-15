import SwiftUI
import IsolynEngineBridge
import Observation

/// The play surface, reduced to the objects that matter: the players, the
/// table, the hand, one draw/pass action, and analysis as a secondary choice.
///
/// The board still owns the middle of the screen. Everything that used to
/// compete with it -- mode labels, score cards, opponent-count telemetry,
/// dividers, camera controls, and the floating appearance brush -- is gone.
struct InteractiveGameBoardView: View {
    let format: MatchFormat
    let opponent: OpponentMode

    @Environment(AppState.self) private var appState

    @State private var viewModel: GameViewModel
    @State private var camera = BoardCamera()
    @State private var arbiter = GestureArbiter()
    @State private var hoverController = HoverChainController()
    @State private var appearanceManager = AppearanceManager()
    @State private var inspectionSettings = InspectionSettings()
    @State private var settingsOpen = false
    @State private var selectedTile: Tile?
    @State private var roundOverVisible = false
    @State private var handDragModel = HandDragModel()
    @State private var dropTargets: [ChainSide: CGRect] = [:]
    @State private var boardFrame: CGRect = .zero
    @State private var boneyardAnchor: CGPoint?

    init(format: MatchFormat, opponent: OpponentMode, aiLevel: AILevel,
         setsToWin: Int, targetScore: Int = 151) {
        self.format = format
        self.opponent = opponent
        _viewModel = State(initialValue: GameViewModel(
            mode: format, opponent: opponent, aiLevel: aiLevel,
            setsToWin: setsToWin, targetScore: targetScore
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = viewModel.setupError {
                setupFailure(error)
            } else if viewModel.phase == .loading && viewModel.snapshot == nil {
                ProgressView("Dealing…")
                    .controlSize(.large)
                    .tint(IsolynTheme.ivory)
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            } else {
                gameContent
            }

            HandDragPreview(
                model: handDragModel,
                appearance: appearanceManager.appearance
            )
            .zIndex(80)

            if (viewModel.phase == .roundOver || viewModel.phase == .matchOver), roundOverVisible {
                RoundEndOverlay(
                    viewModel: viewModel,
                    appearance: appearanceManager.appearance,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.28)) { roundOverVisible = false }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if !viewModel.privatePair.isEmpty {
                privatePairOverlay
                    .transition(.opacity)
                    .zIndex(95)
            }

            settingsDrawerOverlay
        }
        .coordinateSpace(name: GameSurfaceCoordinateSpace.name)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .animation(.easeInOut(duration: 0.25), value: settingsOpen)
        .task { await viewModel.refresh() }
        .task(id: viewModel.phase) {
            let isEnd = viewModel.phase == .roundOver || viewModel.phase == .matchOver
            guard isEnd else {
                roundOverVisible = false
                return
            }
            roundOverVisible = false
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            guard viewModel.phase == .roundOver || viewModel.phase == .matchOver else { return }
            withAnimation(.easeInOut(duration: 0.35)) { roundOverVisible = true }
        }
        .onDisappear { viewModel.shutdown() }
        .alert(alertTitle, isPresented: Binding(
            get: { viewModel.alertError != nil || viewModel.setupError != nil },
            set: { if !$0 { viewModel.dismissAlert() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissAlert() }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Table

    private var gameContent: some View {
        GeometryReader { proxy in
            let padding = IsolynLayout.horizontalPadding(for: proxy.size.width)

            VStack(spacing: 0) {
                topBar(padding: padding)
                playerStrip
                    .padding(.top, 6)

                opponentHandsStrip

                boardSurface
                    .frame(maxHeight: .infinity)

                handDock(padding: padding)
                actionDock(padding: padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { drawFlight(proxy: proxy) }
        }
    }

    // MARK: - Hand drag / drop

    private func beginHandDrag(tile: Tile, at point: CGPoint, grabOffset: CGSize = .zero) {
        selectedTile = tile
        handDragModel.begin(tile, at: point, grabOffset: grabOffset)
        hoverController.dismiss()
    }

    private func updateHandDrag(at point: CGPoint) {
        handDragModel.move(to: point)
    }

    private func endHandDrag(at point: CGPoint) {
        guard let tile = handDragModel.end() else { return }

        if let move = dropMove(for: tile, at: point) {
            selectedTile = nil
            Task { await viewModel.play(move) }
        } else {
            // Keep the fallback tap path alive when the release missed an end.
            selectedTile = tile
        }
    }

    private func dropMove(for tile: Tile, at point: CGPoint) -> Move? {
        guard let snap = viewModel.snapshot else { return nil }
        if let move = HandDropResolver.move(
            for: tile,
            at: point,
            snapshot: snap,
            targets: dropTargets
        ) {
            return move
        }

        // Resilience if an end target's live frame is momentarily stale
        // (camera transform, resize): a release anywhere over the board is
        // still a play when the tile has exactly one legal placement.
        guard boardFrame.contains(point) else { return nil }
        let matching = snap.legalMoves.filter { $0.tile == tile }
        return matching.count == 1 ? matching[0] : nil
    }

    // MARK: - Draw flight

    private func drawFlight(proxy: GeometryProxy) -> some View {
        ZStack {
            ForEach(viewModel.drawEvents) { event in
                DrawFlightView(
                    event: event,
                    from: drawOrigin(in: proxy.size),
                    to: drawDestination(for: event.seat, in: proxy.size),
                    landsInHand: event.seat == viewModel.snapshot?.requestingPlayerIndex,
                    appearance: appearanceManager.appearance
                )
                .id(event.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// The pile reports its live center; the old action-dock point is only a
    /// fallback for the first frame before that preference arrives.
    private func drawOrigin(in size: CGSize) -> CGPoint {
        boneyardAnchor ?? CGPoint(x: size.width / 2, y: size.height - 72)
    }

    private func drawDestination(for seat: Int, in size: CGSize) -> CGPoint {
        if seat == viewModel.snapshot?.requestingPlayerIndex {
            return CGPoint(x: size.width / 2, y: size.height - 154)
        }
        let count = max(viewModel.snapshot?.playerCount ?? 2, 1)
        let slot = CGFloat(seat) - CGFloat(count - 1) / 2
        return CGPoint(x: size.width / 2 + slot * 86, y: 98)
    }

    private func topBar(padding: CGFloat) -> some View {
        HStack {
            Button {
                leaveGame()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(IsolynTheme.ivory)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to match setup")

            // The summary can be dismissed to study the finished board; this
            // brings it back so the round can still be dealt on.
            if (viewModel.phase == .roundOver || viewModel.phase == .matchOver), !roundOverVisible {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { roundOverVisible = true }
                } label: {
                    Text("Round summary")
                        .font(IsolynTheme.caption(10.5))
                        .foregroundStyle(IsolynTheme.ivoryMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().strokeBorder(IsolynTheme.ivoryMuted.opacity(0.32), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the round summary again")
            }

            Spacer()

            // TEMPORARY diagnostic: the build this window is actually running.
            // Three rounds were spent judging a layout that may not have been
            // in the process on screen; this settles it at a glance.
            Text(Bundle.main.infoDictionary?["IsolynBuild"] as? String ?? "devbuild")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(IsolynTheme.ivoryMuted.opacity(0.5))
                .padding(.trailing, 6)
                .accessibilityHidden(true)

            Button {
                settingsOpen.toggle()
                arbiter.cancel()
            } label: {
                Image(systemName: settingsOpen ? "xmark" : "paintbrush")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settingsOpen ? "Close appearance settings" : "Open appearance settings")
        }
        .padding(.horizontal, padding)
        .padding(.top, 8)
    }

    private var playerStrip: some View {
        HStack(alignment: .top, spacing: 26) {
            ForEach(seatItems) { seat in
                seatView(seat)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private func seatView(_ seat: SeatItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(seat.active ? 0.16 : 0.065))

                Circle()
                    .strokeBorder(
                        seat.active ? Color.white.opacity(0.92) : Color.clear,
                        lineWidth: 1.5
                    )

                Text(seat.monogram)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(seat.active ? IsolynTheme.ivory : IsolynTheme.ivoryMuted)
            }
            .frame(width: 42, height: 42)
            .overlay(alignment: .bottomTrailing) {
                Text(seat.out ? "OUT" : "\(seat.handCount)")
                    .font(.system(size: seat.out ? 6.5 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(width: seat.out ? 24 : 16, height: 16)
                    .background(Capsule().fill(seat.out ? IsolynTheme.brass : IsolynTheme.ivory))
                    .offset(x: 2, y: 2)
            }

            Text(seat.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(seat.active ? IsolynTheme.ivory : IsolynTheme.ivoryMuted)

            Text("\(seat.score)")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(seat.active ? IsolynTheme.ivory : IsolynTheme.ivoryMuted)
        }
        .frame(minWidth: 62)
        .opacity(seat.out ? 0.36 : (seat.active ? 1 : 0.58))
        .animation(.easeOut(duration: 0.18), value: seat.active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            seat.out
                ? "\(seat.name), out of this set, score \(seat.score)"
                : "\(seat.name), \(seat.handCount) tiles, score \(seat.score)\(seat.active ? ", acting now" : "")"
        )
    }

    /// Every hidden hand as a physical row of face-down backs. This is a
    /// separate strip rather than part of each avatar cell so the 1v1 seats
    /// stay centered and symmetric as one opponent's hand grows.
    private var opponentHandsStrip: some View {
        let opponents = seatItems.filter { !$0.isSelf }
        return Group {
            if !opponents.isEmpty {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(opponents) { seat in
                        VStack(spacing: 3) {
                            Text(seat.name.uppercased())
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(
                                    seat.active
                                        ? IsolynTheme.ivoryMuted
                                        : IsolynTheme.ivoryMuted.opacity(0.6)
                                )

                            OpponentHandRack(
                                count: seat.handCount,
                                appearance: appearanceManager.appearance
                            )
                        }
                        .opacity(seat.active ? 1 : 0.78)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 5)
                .accessibilityHidden(true)
            }
        }
    }

    private var boardSurface: some View {
        ZStack(alignment: .topLeading) {
            ChainAndZonesView(
                snapshot: viewModel.snapshot,
                canPlay: viewModel.canPlayTiles,
                appearance: appearanceManager.appearance,
                inspectionSettings: inspectionSettings,
                selectedTile: $selectedTile,
                camera: camera,
                arbiter: arbiter,
                hoverController: hoverController,
                onPlay: { move in Task { await viewModel.play(move) } },
                onDropTargetsChanged: { dropTargets = $0 }
            )

            if let snap = viewModel.snapshot, snap.mode == .oneVOne || snap.boneyardDrawableCount > 0 {
                BoneyardView(
                    drawableCount: snap.boneyardDrawableCount,
                    appearance: appearanceManager.appearance,
                    availableHeight: boardFrame.height > 0 ? boardFrame.height : nil,
                    isDrawEnabled: viewModel.canVoluntaryDraw,
                    onDraw: {
                        Task { await viewModel.voluntaryDraw() }
                    }
                )
                .padding(.leading, 18)
                .padding(.top, 16)
                .zIndex(4)
            }
        }
        .frame(maxWidth: IsolynLayout.maxBoardWidth, maxHeight: .infinity)
        .clipped()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BoardFrameKey.self,
                    value: proxy.frame(in: .named(GameSurfaceCoordinateSpace.name))
                )
            }
        )
        .onPreferenceChange(BoardFrameKey.self) { boardFrame = $0 }
        .onPreferenceChange(BoneyardAnchorKey.self) { anchor in
            boneyardAnchor = anchor == .zero ? nil : anchor
        }
    }

    private func handDock(padding: CGFloat) -> some View {
        Group {
            if let snap = viewModel.snapshot {
                HandRackView(
                    hand: snap.ownHand,
                    legalMoves: viewModel.legalMoveSet,
                    openEndsMatch: openEndsMatch,
                    selectedTile: $selectedTile,
                    interactive: viewModel.isMyTurn,
                    draggingTile: handDragModel.tile,
                    onDragBegan: beginHandDrag,
                    onDragChanged: updateHandDrag,
                    onDragEnded: endHandDrag
                ) { move in
                    Task { await viewModel.play(move) }
                }
            }
        }
        .frame(maxWidth: IsolynLayout.maxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, padding)
    }

    private func actionDock(padding: CGFloat) -> some View {
        VStack(spacing: 9) {
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IsolynTheme.ivoryMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.075)))

            HStack(spacing: 9) {
                Button {
                    Task {
                        if viewModel.mustPass {
                            await viewModel.passTurn()
                        } else {
                            await viewModel.voluntaryDraw()
                        }
                    }
                } label: {
                    Text(primaryActionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryActionEnabled ? IsolynTheme.ivory : IsolynTheme.ivoryMuted.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(primaryActionEnabled ? 0.12 : 0.055))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!primaryActionEnabled)

                if viewModel.canLookAtLockedPair {
                    Button {
                        Task { await viewModel.lookAtLockedPair() }
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(IsolynTheme.ivory)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Look at the locked pair privately")
                }

                Button {
                    Task { await toggleAnalysis() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.analysisRunning ? "stop.fill" : "sparkles")
                        Text(viewModel.analysisRunning ? "Stop" : "Analyze")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        analysisEnabled ? IsolynTheme.ivory : IsolynTheme.ivoryMuted.opacity(0.4)
                    )
                    .padding(.horizontal, 15)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(analysisEnabled ? 0.07 : 0.035))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!analysisEnabled)
                .accessibilityLabel(viewModel.analysisRunning ? "Stop analysis" : "Analyze position")
            }
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, padding)
        .padding(.top, 7)
        .padding(.bottom, 14)
    }

    // MARK: - Seat projection

    private struct SeatItem: Identifiable {
        let id: Int
        let name: String
        let monogram: String
        let score: Int
        let handCount: Int
        let active: Bool
        let isSelf: Bool
        /// R-22: this seat crossed 151 and is out of the current set.
        let out: Bool
    }

    private var seatItems: [SeatItem] {
        guard let snap = viewModel.snapshot else { return [] }
        let scores = viewModel.participantScores

        return (0..<snap.playerCount).map { seat in
            let name = displayName(for: seat, mode: snap.mode)
            let scoreIndex = snap.mode == .twoVTwo ? seat % 2 : seat
            let score = scores.indices.contains(scoreIndex) ? scores[scoreIndex] : 0
            let handCount = seat == snap.requestingPlayerIndex
                ? snap.ownHand.count
                : (snap.otherHandSizes.indices.contains(seat) ? snap.otherHandSizes[seat] : 0)

            return SeatItem(
                id: seat,
                name: name,
                monogram: monogram(for: name),
                score: score,
                handCount: handCount,
                active: snap.roundOutcome == .inProgress && snap.currentPlayerIndex == seat,
                isSelf: seat == snap.requestingPlayerIndex,
                out: viewModel.eliminatedPerParticipant.indices.contains(seat)
                    && viewModel.eliminatedPerParticipant[seat]
            )
        }
    }

    private func displayName(for seat: Int, mode: MatchFormat) -> String {
        if seat == 0 { return "You" }
        if mode == .twoVTwo {
            switch seat {
            case 1: return "Rival A"
            case 2: return "Partner"
            case 3: return "Rival B"
            default: return "Rival"
            }
        }
        if mode == .oneVOneVOne {
            return seat == 1 ? "Rival A" : "Rival B"
        }
        return "Rival"
    }

    private func monogram(for name: String) -> String {
        if name == "You" { return "Y" }
        if name == "Partner" { return "P" }
        if name == "Rival A" { return "A" }
        if name == "Rival B" { return "B" }
        if name.hasPrefix("Player ") { return String(name.suffix(1)) }
        return "R"
    }

    // MARK: - Action state

    private var primaryActionTitle: String {
        if viewModel.mustPass { return "Pass turn" }
        let count = viewModel.snapshot?.boneyardDrawableCount ?? 0
        return viewModel.canVoluntaryDraw ? "Draw \(count)" : "Draw"
    }

    private var primaryActionEnabled: Bool {
        viewModel.mustPass || viewModel.canVoluntaryDraw
    }

    private var analysisEnabled: Bool {
        viewModel.analysisRunning || viewModel.canPlayTiles
    }

    /// When both open ends show the same value, placing a matching tile on
    /// either side yields the same pair of new ends. That is the only case
    /// where the hand may auto-route a double-click instead of asking the
    /// player to choose a side.
    private var openEndsMatch: Bool {
        guard let snap = viewModel.snapshot,
              let left = snap.chainLeftEnd,
              let right = snap.chainRightEnd else { return false }
        return left == right
    }

    private var statusText: String {
        if let outcome = viewModel.analysisOutcome, !viewModel.analysisRunning {
            if outcome.isDraw { return "Engine suggests drawing a tile" }
            // Never advertise a move the current board cannot accept: a stale
            // suggestion reads as a legal move and costs the turn.
            let stillLegal = viewModel.snapshot?.legalMoves
                .contains(outcome.recommendedMove) ?? false
            if stillLegal {
                return "Engine suggests \(outcome.recommendedMove.tile.high)–\(outcome.recommendedMove.tile.low)"
            }
        }
        if viewModel.analysisWasCancelled { return "Analysis cancelled" }
        if viewModel.aiThinking { return "Thinking…" }
        if viewModel.isComputerTurn { return "Rival's turn" }
        if viewModel.mustPass { return "Pass to continue" }
        if viewModel.isMyTurn,
           let snap = viewModel.snapshot,
           snap.legalMoves.isEmpty,
           snap.boneyardDrawableCount > 0 {
            return "No legal move — draw to continue"
        }
        if !viewModel.isMyTurn { return "Waiting" }
        if let selected = selectedTile,
           openEndsMatch,
           let snap = viewModel.snapshot,
           snap.legalMoves.filter({ $0.tile == selected }).count > 1 {
            let end = snap.chainLeftEnd.map(String.init) ?? ""
            return "Both ends show \(end) — double-click to place"
        }
        return selectedTile == nil ? "Select a domino" : "Choose an end"
    }

    // MARK: - Navigation / settings

    private func leaveGame() {
        withAnimation(.easeInOut(duration: 0.25)) {
            appState.screen = .modeSelect
        }
    }

    @ViewBuilder
    private var privatePairOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Locked pair")
                    .font(IsolynTheme.display(24))
                    .foregroundStyle(IsolynTheme.ivory)
                Text("Private to this seat. Looking changes nothing.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    ForEach(viewModel.privatePair, id: \.self) { tile in
                        IsolynDominoTile(
                            low: tile.low,
                            high: tile.high,
                            height: 52,
                            appearance: appearanceManager.appearance
                        )
                    }
                }
                .padding(.vertical, 4)
                Button {
                    viewModel.dismissPrivatePair()
                } label: {
                    Text("Close")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IsolynTheme.ivory)
                        .frame(width: 150, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var settingsDrawerOverlay: some View {
        if settingsOpen {
            HStack(spacing: 0) {
                Spacer().allowsHitTesting(false)
                SettingsDrawer(
                    isOpen: $settingsOpen,
                    appearanceManager: appearanceManager,
                    inspectionSettings: inspectionSettings
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) { settingsOpen = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .zIndex(100)
        }
    }

    // MARK: - Alerts / failure

    private var alertTitle: String {
        viewModel.setupError != nil ? "Match setup failed" : "Engine said no"
    }

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
        .background(Color.black.ignoresSafeArea())
    }

    private func toggleAnalysis() async {
        let believer = viewModel.snapshot?.currentPlayerIndex ?? 0
        await viewModel.toggleAnalysis(believer: believer)
    }
}

/// Pointer updates live in this tiny observable object so moving a hand tile
/// only refreshes `HandDragPreview`, not the board layout or the game view.
@MainActor
@Observable
private final class HandDragModel {
    private(set) var tile: Tile?
    private(set) var location: CGPoint = .zero
    private(set) var grabOffset: CGSize = .zero

    func begin(_ tile: Tile, at point: CGPoint, grabOffset: CGSize) {
        self.tile = tile
        location = point
        self.grabOffset = grabOffset
    }

    func move(to point: CGPoint) {
        guard tile != nil else { return }
        location = point
    }

    @discardableResult
    func end() -> Tile? {
        let result = tile
        tile = nil
        return result
    }
}

private struct HandDragPreview: View {
    let model: HandDragModel
    let appearance: DominoAppearance

    var body: some View {
        ZStack {
            if let tile = model.tile {
                IsolynDominoTile(
                    leftPips: tile.low,
                    rightPips: tile.high,
                    height: HandRackView.tileHeight,
                    appearance: appearance,
                    state: .selected
                )
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                .position(
                    CGPoint(
                        x: model.location.x + model.grabOffset.width,
                        y: model.location.y + model.grabOffset.height
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct BoardFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
