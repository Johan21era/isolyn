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
                        camera: camera,
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
///
/// FIX-28 (audit OA-4 / remediation roadmap P2a): every placement,
/// extent, and fit-scale decision now lives in `SnakeChainLayout` below
/// -- pure data in, pure data out, unit-testable headlessly. This view
/// renders exactly what it returns. THIS SUB-STEP IS DELIBERATELY
/// BEHAVIOR-NEUTRAL: formulas moved verbatim; the auto-fit scale and
/// content-aware camera bounds apply in the very next commit (P2b/P2c).
private struct SnakeChainBoard: View {

    let snapshot: GameSnapshot
    let appearance: DominoAppearance
    let canPlay: Bool
    let selectedTile: Tile?
    let availableSize: CGSize
    let camera: BoardCamera
    let selectedSideIsPlayable: (ChainSide) -> Bool
    let onPlaySide: (ChainSide) -> Void
    let onHoverPip: (Int?) -> Void

    private var orientedTiles: [SnakeChainLayout.Oriented] {
        SnakeChainLayout.orient(chain: snapshot.chain, leftEnd: snapshot.chainLeftEnd)
    }

    var body: some View {
        let metrics = SnakeChainLayout.compute(
            orientedTiles: orientedTiles, availableSize: availableSize)

        // FIX-28 P2b/P2c application. The ONE UNIFORM scale from the pure
        // layout keeps the §2/§3 exact-2:1 domino law intact BY CONSTRUCTION
        // at any scale; it engages only past SnakeChainLayout.fitThreshold,
        // so ordinary games never see it. Whatever overflow survives past
        // the minScale floor is handed to the camera as extra pan range
        // (halved: the offset translates the plane's CENTER), so the tail
        // of even a pathological chain stays reachable. Mutations happen in
        // onAppear/onChange closures -- never during body evaluation.
        let residualX = max(0, metrics.contentWidth * metrics.suggestedScale - availableSize.width) / 2
        let residualY = max(0, metrics.contentHeight * metrics.suggestedScale - availableSize.height) / 2
        let boundsSignature = "\(Int(residualX))|\(Int(residualY))"

        ZStack {
            ForEach(Array(metrics.placed.enumerated()), id: \.offset) { _, placed in
                IsolynDominoTile(
                    displayingLeft: placed.tile.left,
                    right: placed.tile.right,
                    isDouble: placed.vertical,
                    height: SnakeChainLayout.tileShortAxis,
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
        // ONE uniform auto-fit scale (§17 "scale the board intelligently";
        // completes the mandate's responsive clause).
        .scaleEffect(metrics.suggestedScale)
        .animation(.easeOut(duration: 0.18), value: snapshot.stateVersion)
        .onAppear { raiseCameraBounds(residualX, residualY) }
        .onChange(of: boundsSignature) { _, _ in raiseCameraBounds(residualX, residualY) }
    }

    /// Bounds only ever GROW toward the fitted extent (defaults preserved;
    /// reset-view zeroes OFFSETS, never bounds). Called from lifecycle
    /// closures only.
    private func raiseCameraBounds(_ residualX: CGFloat, _ residualY: CGFloat) {
        camera.maxOffsetX = max(camera.maxOffsetX, BoardCamera.defaultMaxOffsetX + residualX)
        camera.maxOffsetY = max(camera.maxOffsetY, BoardCamera.defaultMaxOffsetY + residualY)
    }

    // MARK: Playable-end markers (§8: unmistakable, restrained, valid-only)

    @ViewBuilder
    private func endpointMarkers(_ metrics: SnakeChainLayout.Metrics) -> some View {
        let handHasMoveOn: (ChainSide) -> Bool = { side in
            snapshot.legalMoves.contains { $0.side == side }
        }
        if snapshot.chain.isEmpty {
            if canPlay && (handHasMoveOn(.left) || handHasMoveOn(.right)) {
                EndMarker(pip: nil, active: canPlay && selectedTile != nil, size: SnakeChainLayout.markerDiameter) {
                    // Any selected tile opens the chain.
                    if let tile = selectedTile,
                       let move = Set(snapshot.legalMoves).first(where: { $0.tile == tile }) {
                        onPlaySide(move.side)
                    }
                }
                .position(availableSize.width / 2, availableSize.height / 2)
            }
        } else {
            if let pos = metrics.headPosition, handHasMoveOn(.left) {
                EndMarker(pip: snapshot.chainLeftEnd,
                          active: canPlay && selectedTile != nil && selectedSideIsPlayable(.left),
                          size: SnakeChainLayout.markerDiameter) { onPlaySide(.left) }
                .onHover { onHoverPip($0 ? snapshot.chainLeftEnd : nil) }
                .position(pos)
            }
            if let pos = metrics.tailPosition, handHasMoveOn(.right) {
                EndMarker(pip: snapshot.chainRightEnd,
                          active: canPlay && selectedTile != nil && selectedSideIsPlayable(.right),
                          size: SnakeChainLayout.markerDiameter) { onPlaySide(.right) }
                .onHover { onHoverPip($0 ? snapshot.chainRightEnd : nil) }
                .position(pos)
            }
        }
    }
}

// MARK: - Pure snake-chain layout (FIX-28 / remediation roadmap P2a)

/// Every placement/extent/fit decision for the board as pure data --
/// no SwiftUI types beyond geometry primitives, no view state, fully
/// unit-testable headlessly (`Tests/IsolynAppTests/BoardLayoutTests.swift`).
///
/// The placement formulas below are VERBATIM the ones this file has always
/// used (serpentine runs, perpendicular doubles, corner tiles as
/// perpendicular row-end caps with guaranteed pitch clearance). Only the
/// home moved -- plus the NEW extent/scale fields the auto-fit work needs:
/// `contentWidth`/`contentHeight` (bounding box of everything drawn,
/// markers included) and `suggestedScale` (ONE uniform factor, clamped
/// `minScale…1`, engaged only past `fitThreshold` occupancy -- uniform
/// scaling multiplies both axes equally, so the mandate §2/§3 exact-2:1
/// law holds BY CONSTRUCTION at any scale).
enum SnakeChainLayout {
    struct Oriented: Equatable { let left: Int; let right: Int; let isDouble: Bool }
    struct Placed { let x: CGFloat; let y: CGFloat; let tile: Oriented; let vertical: Bool }
    struct Metrics {
        let placed: [Placed]
        let headPosition: CGPoint?
        let tailPosition: CGPoint?
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let suggestedScale: CGFloat
    }

    // Canonical board metrics (§16 spacing scale; §7 gap 0–6px) --
    // previously private constants on the view; hoisted so layout math
    // and rendering share one source of truth.
    static let tileShortAxis: CGFloat = 26
    static let hGap: CGFloat = 4
    /// Row pitch leaves room for perpendicular doubles (long axis 52)
    /// to protrude into the inter-row band without touching neighbours.
    static var rowPitch: CGFloat { tileShortAxis * 2 + 4 }
    static let markerDiameter: CGFloat = 34
    /// Auto-fit engagement point (fraction of an axis in use).
    static let fitThreshold: CGFloat = 0.94
    /// Auto-fit floor -- never shrink tiles past readability (§17 order:
    /// reduce spacing, reduce scale WITHIN LIMITS, then pan).
    static let minScale: CGFloat = 0.62

    /// Walks the raw chain left-to-right, flipping each tile to match its
    /// neighbour so displayed pips physically touch. Orientation is never
    /// stored anywhere (the engine derives it; so does rendering).
    static func orient(chain: [Tile], leftEnd: Int?) -> [Oriented] {
        var result: [Oriented] = []
        guard let start = leftEnd else { return result }
        var touching = start
        for tile in chain {
            guard tile.hasFace(touching) else {
                result.append(Oriented(left: tile.low, right: tile.high, isDouble: tile.low == tile.high))
                continue
            }
            let other = tile.otherFace(touching)
            result.append(Oriented(left: touching, right: other, isDouble: tile.low == tile.high))
            touching = other
        }
        return result
    }

    static func compute(orientedTiles: [Oriented], availableSize: CGSize) -> Metrics {
        let W = availableSize.width
        let H = availableSize.height
        let tileW = tileShortAxis * 2
        let pitchX = tileW + hGap
        let cols = max(3, Int((W - 24) / pitchX))
        let midX = W / 2
        let midY = H / 2

        func rowY(_ row: Int) -> CGFloat {
            midY - rowPitch / 2 + CGFloat(row) * rowPitch
        }

        var placed: [Placed] = []
        var row = 0
        var dir: CGFloat = 1                      // +1 → rightwards, −1 ← leftwards
        var col = 0
        let startX = midX - CGFloat(cols) * pitchX / 2 + pitchX / 2
        var centerX = startX

        func advance(_ n: Int = 1) {
            centerX += CGFloat(n * Int(dir)) * pitchX
            // FIX-28 discovery: this line read `col += n` -- UNSIGNED. `col`
            // therefore counted UP forever even on leftward runs, so after
            // the first corner NO second corner could ever fire ((dir<0 &&
            // col==0) unreachable; (dir>0 && col==cols-1) already passed)
            // and any chain longer than one row silently walked off the
            // board's left edge instead of snaking. Latent since the snake
            // board shipped -- invisible with real mid-game chains (<13
            // tiles), exposed immediately by BoardLayoutTests' synthetic
            // long chains. Signed advance makes col track the actual
            // column position in BOTH directions.
            col += n * Int(dir)
        }

        var i = 0
        while i < orientedTiles.count {
            let t = orientedTiles[i]
            let remainingAfter = orientedTiles.count - i - 1
            let needsTurn = remainingAfter > 0 && ((dir > 0 && col == cols - 1) || (dir < 0 && col == 0))

            if needsTurn {
                // CORNER: this tile turns the run -- rendered VERTICAL as a
                // perpendicular end-cap IN its own row cell; the next row
                // starts in this same column. Pitch (56) clears the long
                // axis (52) with 4pt air, guaranteeing no overlap (§7).
                placed.append(Placed(x: centerX, y: rowY(row), tile: t, vertical: true))
                row += 1
                dir *= -1
                i += 1
                continue
            }

            placed.append(Placed(x: centerX, y: rowY(row), tile: t, vertical: t.isDouble))
            advance()
            i += 1
        }

        guard let first = placed.first, let last = placed.last else {
            return Metrics(placed: [], headPosition: nil, tailPosition: nil,
                           contentWidth: 0, contentHeight: 0, suggestedScale: 1)
        }
        let headDirIn: CGFloat = 1
        let tailDir = dir
        let headPos = CGPoint(x: first.x - headDirIn * (tileShortAxis + 22), y: first.y)
        let tailPos = CGPoint(x: last.x + tailDir * (tileShortAxis + 22), y: last.y)

        // Extent: each tile's own half-extents (vertical tiles reach
        // ±shortAxis on Y -- the perpendicular-double protrusion --
        // horizontal ones ±shortAxis on X), plus both end markers'
        // clearance rings.
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for p in placed {
            let halfX: CGFloat = p.vertical ? tileShortAxis / 2 : tileShortAxis
            let halfY: CGFloat = p.vertical ? tileShortAxis : tileShortAxis / 2
            minX = min(minX, p.x - halfX); maxX = max(maxX, p.x + halfX)
            minY = min(minY, p.y - halfY); maxY = max(maxY, p.y + halfY)
        }
        let reach = markerDiameter / 2
        minX = min(minX, headPos.x - reach, tailPos.x - reach)
        maxX = max(maxX, headPos.x + reach, tailPos.x + reach)
        minY = min(minY, headPos.y - reach, tailPos.y - reach)
        maxY = max(maxY, headPos.y + reach, tailPos.y + reach)

        let contentW = maxX - minX
        let contentH = maxY - minY

        return Metrics(placed: placed, headPosition: headPos, tailPosition: tailPos,
                       contentWidth: contentW, contentHeight: contentH,
                       suggestedScale: fitScale(contentWidth: contentW, contentHeight: contentH,
                                                availableSize: availableSize))
    }

    /// ONE uniform factor covering the tighter of the two axes; exactly 1
    /// while things fit; floored at `minScale` so extreme chains stop
    /// shrinking and rely on pan instead (§17's priority order, encoded).
    static func fitScale(contentWidth: CGFloat, contentHeight: CGFloat, availableSize: CGSize) -> CGFloat {
        guard contentWidth > 0, contentHeight > 0 else { return 1 }
        let widthRatio = availableSize.width * fitThreshold / contentWidth
        let heightRatio = availableSize.height * fitThreshold / contentHeight
        return min(1, max(minScale, widthRatio), max(minScale, heightRatio))
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
