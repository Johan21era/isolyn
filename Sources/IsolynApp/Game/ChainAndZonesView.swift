import SwiftUI
import IsolynEngineBridge

/// The domino board (dominoes_ui_fix_non_negotiable.md §4–§8).
///
/// The chain is THE primary visual object: a connected snake of canonical
/// single-rectangle dominoes laid on one coherent surface — horizontal
/// runs, perpendicular doubles, and clean 90° turns at row breaks. No
/// layout scaffolding is visible; containers exist purely for positioning.
///
/// Playable ends are marked ON THE BOARD at the exact connection points,
/// and ONLY when that end genuinely accepts at least one tile in the
/// current player's hand (§8: never highlight invalid locations).
///
/// Camera pan / gesture arbitration / hover-chain overlay integrate exactly
/// as before — those systems were hardened earlier today and are orthogonal
/// to presentation.
struct ChainAndZonesView: View {
    let snapshot: GameSnapshot?
    let canPlay: Bool
    let appearance: DominoAppearance
    @Binding var selectedTile: Tile?
    let camera: BoardCamera
    let arbiter: GestureArbiter
    let hoverController: HoverChainController
    let onPlay: (Move) -> Void

    @State private var lastMouseLocation: CGPoint? = nil

    var body: some View {
        ZStack {
            if let snap = snapshot {
                GeometryReader { geo in
                    SnakeChainBoard(
                        snapshot: snap,
                        appearance: appearance,
                        canPlay: canPlay,
                        selectedTile: selectedTile,
                        availableSize: geo.size,
                        selectedSideIsPlayable: selectedSideIsPlayable,
                        onPlaySide: playOnSide,
                        onHoverPip: { pip in
                            guard !arbiter.isDragging else { return }
                            if let pip {
                                hoverController.cancelScheduledDismissal()
                                hoverController.setTarget(pip, snapshot: snapshot)
                            } else {
                                hoverController.scheduleDismissal()
                            }
                        }
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                // Camera pan translates the whole board plane; markers,
                // dominoes and hover targets move together.
                .offset(x: camera.offsetX, y: camera.offsetY)
            }
            // Hover-chain overlay floats above the board (unchanged system).
            if let chain = hoverController.builtChain, !camera.isDragging {
                VStack {
                    HStack { Spacer()
                        HoverChainOverlay(
                            chain: chain,
                            appearance: appearance,
                            onClose: { hoverController.dismiss() }
                        )
                        .padding(.trailing, 20)
                        .onHover { over in
                            if over { hoverController.cancelScheduledDismissal() }
                            else { hoverController.scheduleDismissal() }
                        }
                    }
                    Spacer()
                }.allowsHitTesting(true).zIndex(50).transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(boardDragGesture.simultaneously(with: tapGesture))
        .onTapGesture {} // consume bare clicks so they don't fall through
    }

    // MARK: - Selection resolution

    private func selectedSideIsPlayable(_ side: ChainSide) -> Bool {
        guard let tile = selectedTile, let snap = snapshot else { return false }
        return Set(snap.legalMoves).contains { $0.tile == tile && $0.side == side }
    }

    private func playOnSide(_ side: ChainSide) {
        guard let tile = selectedTile, let snap = snapshot,
              let move = Set(snap.legalMoves).first(where: { $0.tile == tile && $0.side == side }) else { return }
        selectedTile = nil
        hoverController.dismiss()   // board changed; analysis is stale
        onPlay(move)
    }

    // MARK: - Gestures (camera pan owns drags past threshold; bare taps clear selection)

    private var boardDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if arbiter.owner == .idle {
                    arbiter.pointerDown(at: value.startLocation)
                    camera.beginDrag(at: value.startLocation)
                }
                arbiter.pointerMoved(to: value.location, targetIsDomino: false)
                if arbiter.isBoardPanning {
                    camera.updateDrag(translation: value.translation)
                    hoverController.suspend()
                }
            }
            .onEnded { _ in
                _ = arbiter.pointerUp()
                camera.endDrag(lastLocation: lastMouseLocation)
                Task { try? await Task.sleep(nanoseconds: 200_000_000)
                    hoverController.resume(snapshot: snapshot, target: hoverController.activeTarget)
                }
            }
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 1).onEnded {
            _ = arbiter.pointerUp()
            selectedTile = nil
        }
    }
}

// MARK: - The snake chain

/// Lays the chain as a serpentine: horizontal runs of single-rectangle
/// dominoes, doubles rendered perpendicular, and a vertical corner tile
/// turning the run at every row break (§6). Deterministic from the
/// snapshot; positions are computed once per layout pass and placed with
/// `.position`, so nothing but dominoes ever becomes visible (§5).
private struct SnakeChainBoard: View {
    // Canonical board metrics (§16 spacing scale; §7 gap 0–6px).
    static let tileShortAxis: CGFloat = 26
    static let hGap: CGFloat = 4
    /// Row pitch leaves room for perpendicular doubles (long axis 52)
    /// to protrude into the inter-row band without touching neighbours.
    static var rowPitch: CGFloat { tileShortAxis * 2 + 4 }
    static let markerDiameter: CGFloat = 34

    let snapshot: GameSnapshot
    let appearance: DominoAppearance
    let canPlay: Bool
    let selectedTile: Tile?
    let availableSize: CGSize
    let selectedSideIsPlayable: (ChainSide) -> Bool
    let onPlaySide: (ChainSide) -> Void
    let onHoverPip: (Int?) -> Void

    private var orientedTiles: [OrientedTile] {
        var result: [OrientedTile] = []
        guard let leftEnd = snapshot.chainLeftEnd else { return result }
        var touching = leftEnd
        for tile in snapshot.chain {
            guard tile.hasFace(touching) else {
                result.append(OrientedTile(left: tile.low, right: tile.high, isDouble: tile.low == tile.high))
                continue
            }
            let other = tile.otherFace(touching)
            result.append(OrientedTile(left: touching, right: other, isDouble: tile.low == tile.high))
            touching = other
        }
        return result
    }

    struct OrientedTile { let left: Int; let right: Int; let isDouble: Bool }
    struct Placed {
        let x: CGFloat; let y: CGFloat          // center in board space
        let tile: OrientedTile
        let vertical: Bool
    }

    var body: some View {
        let metrics = computeLayout()
        ZStack {
            ForEach(Array(metrics.placed.enumerated()), id: \.offset) { _, placed in
                IsolynDominoTile(
                    displayingLeft: placed.tile.left,
                    right: placed.tile.right,
                    isDouble: placed.vertical,
                    height: Self.tileShortAxis,
                    appearance: appearance
                )
                .position(placed.x, placed.y)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            endpointMarkers(metrics)

            if metrics.placed.isEmpty && !canPlay {
                Text("Round opening…")
                    .font(IsolynTheme.caption(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .animation(.easeOut(duration: 0.18), value: snapshot.stateVersion)
    }

    // MARK: Layout computation (pure; runs per render)

    private func computeLayout() -> (placed: [Placed],
                                     head: CGPoint?, tail: CGPoint?,
                                     headRowY: CGFloat?, tailRowY: CGFloat?,
                                     headDir: CGFloat, tailDir: CGFloat) {
        let W = availableSize.width
        let H = availableSize.height
        let tileW = Self.tileShortAxis * 2
        let pitchX = tileW + Self.hGap
        let cols = max(3, Int((W - 24) / pitchX))
        let midX = W / 2
        let midY = H / 2

        // Row center-lines measured relative to board center.
        func rowY(_ row: Int) -> CGFloat {
            let offsetFromMid = CGFloat(row) * Self.rowPitch
            // Center the whole snake vertically-ish: first row above mid.
            return midY - Self.rowPitch / 2 + offsetFromMid
        }

        var placed: [Placed] = []
        var row = 0
        var dir: CGFloat = 1                      // +1 → rightwards, −1 ← leftwards
        var col = 0
        let startX = midX - CGFloat(cols) * pitchX / 2 + pitchX / 2
        var centerX = startX

        func advance(_ n: Int = 1) {
            centerX += CGFloat(n * Int(dir)) * pitchX
            col += n
        }

        let tiles = orientedTiles
        var i = 0
        while i < tiles.count {
            let t = tiles[i]
            let remainingAfter = tiles.count - i - 1
            let needsTurn = remainingAfter > 0 && ((dir > 0 && col == cols - 1) || (dir < 0 && col == 0))

            if needsTurn {
                // CORNER: this tile turns the run. Rendered VERTICAL as a
                // perpendicular end-cap IN its own row cell (the classic
                // table look). The next row starts in this same column, so
                // the corner's lower face visually feeds the return run:
                // row pitch (56) clears its long axis (52) with 4pt air,
                // guaranteeing zero shape overlap while edges read as
                // physically joined (§7).
                placed.append(Placed(x: centerX, y: rowY(row),
                                     tile: t, vertical: true))
                row += 1
                dir *= -1
                i += 1
                continue
            }

            let vertical = t.isDouble
            placed.append(Placed(x: centerX, y: rowY(row), tile: t, vertical: vertical))
            advance()
            // NOTE: no plain wrap branch — EVERY row break goes through a
            // corner tile above, which flips direction and drops a row.
            // The run can therefore never silently walk off-canvas.
            i += 1
        }

        guard let first = placed.first, let last = placed.last else {
            return ([], nil, nil, nil, nil, 1, 1)
        }
        let headDirIn: CGFloat = 1
        // Markers sit just beyond each open end along its run direction,
        // always on the row center-line (a perpendicular cap's exposed
        // face is still reached horizontally from outside the run).
        let tailDir = dir
        let headPos = CGPoint(x: first.x - headDirIn * (Self.tileShortAxis + 22),
                              y: first.y)
        let tailPos = CGPoint(x: last.x + tailDir * (Self.tileShortAxis + 22),
                              y: last.y)

        return (placed, headPos, tailPos, first.y, last.y, headDirIn, tailDir)
    }

    // MARK: Playable-end markers (§8: unmistakable, restrained, valid-only)

    @ViewBuilder
    private func endpointMarkers(_ m: (placed: [Placed], head: CGPoint?, tail: CGPoint?,
                                       headRowY: CGFloat?, tailRowY: CGFloat?,
                                       headDir: CGFloat, tailDir: CGFloat)) -> some View {
        let handHasMoveOn: (ChainSide) -> Bool = { side in
            snapshot.legalMoves.contains { $0.side == side }
        }
        if snapshot.chain.isEmpty {
            if canPlay && (handHasMoveOn(.left) || handHasMoveOn(.right)) {
                EndMarker(pip: nil, active: canPlay && selectedTile != nil, size: Self.markerDiameter) {
                    // Any selected tile opens the chain.
                    if let tile = selectedTile,
                       let move = Set(snapshot.legalMoves).first(where: { $0.tile == tile }) {
                        onPlaySide(move.side)
                    }
                }
                .position(availableSize.width / 2, availableSize.height / 2)
            }
        } else {
            if let pos = m.head, handHasMoveOn(.left) {
                EndMarker(pip: snapshot.chainLeftEnd,
                          active: canPlay && selectedTile != nil && selectedSideIsPlayable(.left),
                          size: Self.markerDiameter) { onPlaySide(.left) }
                .onHover { onHoverPip($0 ? snapshot.chainLeftEnd : nil) }
                .position(pos)
            }
            if let pos = m.tail, handHasMoveOn(.right) {
                EndMarker(pip: snapshot.chainRightEnd,
                          active: canPlay && selectedTile != nil && selectedSideIsPlayable(.right),
                          size: Self.markerDiameter) { onPlaySide(.right) }
                .onHover { onHoverPip($0 ? snapshot.chainRightEnd : nil) }
                .position(pos)
            }
        }
    }

}

// MARK: - Endpoint marker

/// A quiet brass ring carrying the matching pip value. Static by default;
/// the brief pulse appears only when the CURRENTLY SELECTED tile can land
/// here (§25: purposeful, calm). Never shown for invalid ends.
private struct EndMarker: View {
    let pip: Int?
    let active: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(IsolynTheme.brass.opacity(active ? 0.95 : 0.55),
                                  lineWidth: active ? 2 : 1.5)
                    .background(Circle().fill(IsolynTheme.ebonyElevated.opacity(0.85)))
                if let pip {
                    Text("\(pip)")
                        .font(IsolynTheme.display(15))
                        .monospacedDigit()
                        .foregroundStyle(active ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? IsolynTheme.brass : IsolynTheme.ivoryMuted)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(active && pulse ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
        .onChange(of: active) { _, newValue in pulse = newValue }
        .onAppear { pulse = active }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Places the selected domino here.")
    }

    private var accessibilityText: String {
        if let pip { return "Open end showing \(pip)\(active ? ", accepts selected tile" : "")" }
        return "Empty table — place the opening domino"
    }
}

// MARK: - Position helper

extension View {
    /// Positions this view by its CENTER within the parent coordinate space.
    fileprivate func position(_ x: CGFloat, _ y: CGFloat) -> some View {
        self.position(CGPoint(x: x, y: y))
    }
}
