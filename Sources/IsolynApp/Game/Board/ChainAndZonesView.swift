import SwiftUI
import IsolynEngineBridge

/// The domino board (docs/history/2026-08-ui-rebuild-mandate.md §4–§8).
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
    let inspectionSettings: InspectionSettings
    @Binding var selectedTile: Tile?
    let camera: BoardCamera
    let arbiter: GestureArbiter
    let hoverController: HoverChainController
    let onPlay: (Move) -> Void
    let onDropTargetsChanged: ([ChainSide: CGRect]) -> Void

    var body: some View {
        ZStack {
            if let snap = snapshot {
                GeometryReader { geo in
                    SnakeChainBoard(
                        snapshot: snap,
                        appearance: appearance,
                        canPlay: canPlay,
                        selectedTile: selectedTile,
                        inspectionSettings: inspectionSettings,
                        onInspectFace: { number in
                            hoverController.cancelScheduledDismissal()
                            hoverController.setTarget(number, snapshot: snapshot)
                        },
                        availableSize: geo.size,
                        camera: camera,
                        selectedSideIsPlayable: selectedSideIsPlayable,
                        onPlaySide: playOnSide,
                        onHoverPip: { pip in
                            guard inspectionSettings.autoHoverEnabled,
                                  !arbiter.isDragging else { return }
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
                        .padding(.top, 8)
                        .padding(.trailing, 20)
                        .onHover { over in
                            if over {
                                hoverController.cancelScheduledDismissal()
                            } else if inspectionSettings.autoHoverEnabled {
                                hoverController.scheduleDismissal()
                            }
                        }
                    }
                    Spacer()
                }.allowsHitTesting(true).zIndex(50).transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(boardDragGesture.simultaneously(with: tapGesture))
        .onTapGesture {} // consume bare clicks so they don't fall through
        .onPreferenceChange(BoardDropTargetFrames.self) { frames in
            onDropTargetsChanged(frames)
        }
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
            .onEnded { value in
                _ = arbiter.pointerUp()
                // Hand the release point to the camera directly. The old
                // separate @State was never assigned, so inertia always
                // received nil and the board stopped dead on release.
                camera.endDrag(lastLocation: value.location)
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
    let inspectionSettings: InspectionSettings
    let onInspectFace: (Int) -> Void
    let availableSize: CGSize
    let camera: BoardCamera
    let selectedSideIsPlayable: (ChainSide) -> Bool
    let onPlaySide: (ChainSide) -> Void
    let onHoverPip: (Int?) -> Void

    @State private var hoverTracker = InspectionHoverTracker()

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
            #if DEBUG
            // Readout belongs to THIS board, not a shared global: a top-bar
            // label was written by a different board instance than the one on
            // screen, which reported numbers that did not match the drawing.
            VStack {
                Spacer()
                Text("\(Int(availableSize.width))×\(Int(availableSize.height)) n\(metrics.placed.count) s\(String(format: "%.2f", metrics.suggestedScale)) r\(Set(metrics.placed.map { Int($0.y) }).count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.bottom, 2)
            }
            .allowsHitTesting(false)
            #endif

            ForEach(Array(metrics.placed.enumerated()), id: \.offset) { index, placed in
                IsolynDominoTile(
                    displayingLeft: placed.tile.left,
                    right: placed.tile.right,
                    isDouble: placed.vertical,
                    height: SnakeChainLayout.tileShortAxis,
                    appearance: appearance
                )
                .overlay(alignment: .leading) {
                    if index == 0, hasMove(on: .left) {
                        EndEdgeHighlight(active: selectedSideIsPlayable(.left), leading: true)
                    }
                }
                .overlay(alignment: .trailing) {
                    if index == metrics.placed.count - 1, hasMove(on: .right) {
                        EndEdgeHighlight(active: selectedSideIsPlayable(.right), leading: false)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        // Horizontal tiles split left/right; vertical tiles
                        // split top/bottom. In both cases the leading half
                        // is half the short axis from the origin.
                        let leading = placed.vertical
                            ? point.y < SnakeChainLayout.tileShortAxis
                            : point.x < SnakeChainLayout.tileShortAxis
                        hoverTracker.set(
                            index: index,
                            face: leading ? placed.tile.left : placed.tile.right
                        )
                    case .ended:
                        hoverTracker.clear(index: index)
                    }
                }
                .position(placed.x, placed.y)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.72).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }

            if metrics.placed.isEmpty && canPlay {
                // A quiet 2:1 silhouette for the opening placement. The
                // invisible target at the center handles the actual tap.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: SnakeChainLayout.tileShortAxis * 2,
                           height: SnakeChainLayout.tileShortAxis)
                    .position(availableSize.width / 2, availableSize.height / 2)
                    .allowsHitTesting(false)
            }

            endpointTargets(metrics)

            if metrics.placed.isEmpty && !canPlay {
                Text("Round opening…")
                    .font(IsolynTheme.caption(12))
                    .foregroundStyle(IsolynTheme.ivoryMuted)
            }
        }
        .onAppear {
            #if DEBUG
            LayoutProbe.shared.record(availableSize: availableSize,
                               tileCount: metrics.placed.count,
                               scale: metrics.suggestedScale,
                               content: CGSize(width: metrics.contentWidth,
                                               height: metrics.contentHeight),
                               placed: metrics.placed.map { ($0.x, $0.y, $0.vertical) })
            #endif
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .background(
            InspectionEventMonitor(
                button: inspectionSettings.mouseButton,
                tracker: hoverTracker,
                onInspect: onInspectFace
            )
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: snapshot.stateVersion)
        .onAppear { raiseCameraBounds(residualX, residualY) }
        .onChange(of: boundsSignature) { _, _ in raiseCameraBounds(residualX, residualY) }
        .onChange(of: snapshot.stateVersion) { _, _ in hoverTracker.clearAll() }
        .onChange(of: camera.offsetX) { _, _ in hoverTracker.clearAll() }
        .onChange(of: camera.offsetY) { _, _ in hoverTracker.clearAll() }
        .onChange(of: metrics.placed.count) { _, _ in
            #if DEBUG
            LayoutProbe.shared.record(availableSize: availableSize,
                               tileCount: metrics.placed.count,
                               scale: metrics.suggestedScale,
                               content: CGSize(width: metrics.contentWidth,
                                               height: metrics.contentHeight),
                               placed: metrics.placed.map { ($0.x, $0.y, $0.vertical) })
            #endif
        }
        .onDisappear { hoverTracker.clearAll() }
    }

    /// Bounds only ever GROW toward the fitted extent (defaults preserved;
    /// reset-view zeroes OFFSETS, never bounds). Called from lifecycle
    /// closures only.
    private func raiseCameraBounds(_ residualX: CGFloat, _ residualY: CGFloat) {
        camera.maxOffsetX = max(camera.maxOffsetX, BoardCamera.defaultMaxOffsetX + residualX)
        camera.maxOffsetY = max(camera.maxOffsetY, BoardCamera.defaultMaxOffsetY + residualY)
    }

    // MARK: Playable-end targets (§8: valid-only, now visually quiet)

    private func hasMove(on side: ChainSide) -> Bool {
        canPlay && snapshot.legalMoves.contains { $0.side == side }
    }

    @ViewBuilder
    private func endpointTargets(_ metrics: SnakeChainLayout.Metrics) -> some View {
        let handHasMoveOn: (ChainSide) -> Bool = { side in
            snapshot.legalMoves.contains { $0.side == side }
        }
        if snapshot.chain.isEmpty {
            if canPlay && (handHasMoveOn(.left) || handHasMoveOn(.right)) {
                EndTarget(side: .left, label: "Empty table, place the opening domino") {
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
                EndTarget(side: .left, label: "Open left end showing \(snapshot.chainLeftEnd.map(String.init) ?? "unknown")") {
                    onPlaySide(.left)
                }
                .onHover { onHoverPip($0 ? snapshot.chainLeftEnd : nil) }
                .position(pos)
            }
            if let pos = metrics.tailPosition, handHasMoveOn(.right) {
                EndTarget(side: .right, label: "Open right end showing \(snapshot.chainRightEnd.map(String.init) ?? "unknown")") {
                    onPlaySide(.right)
                }
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
    static let tileShortAxis: CGFloat = 38
    /// Longest run the table allows, in points (~9 tiles). A real game turns
    /// well before the edge of the room it is played in; without this cap a
    /// desktop-width window lets a whole chain run in one straight line.

    /// Visible separation between dominoes. At 4pt a run of flat tiles reads as
    /// one continuous bar (a live report: "the left side has almost all of the
    /// dominoes fucked up"); physical dominoes sitting on a table have a clear
    /// edge between them.
    static let hGap: CGFloat = 10
    /// Row pitch leaves room for perpendicular doubles (long axis 76)
    /// to protrude into the inter-row band without touching neighbours.
    static var rowPitch: CGFloat { tileShortAxis * 2 + hGap }
    /// Invisible end-target hit area. The visible affordance stays a thin
    /// 2.25pt tick, but a release anywhere inside this generous square (plus
    /// `HandDropResolver.dropPadding`) counts as landing on the end.
    static let endTargetDiameter: CGFloat = 96
    /// Auto-fit engagement point (fraction of an axis in use).
    static let fitThreshold: CGFloat = 0.94
    /// Auto-fit floor -- never shrink tiles past readability (§17 order:
    /// reduce spacing, reduce scale WITHIN LIMITS, then pan).
    static let minScale: CGFloat = 0.62

    /// The board also grows to use the table it has. Without this a short
    /// chain sat as a small block in the middle of a wide window.
    static let maxScale: CGFloat = 1.9

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

    private static func layoutPath(orientedTiles: [Oriented], availableSize: CGSize, short: CGFloat)
        -> (placed: [Placed], escaped: Bool, head: CGPoint, tail: CGPoint,
            contentWidth: CGFloat, contentHeight: CGFloat) {
        let long = short * 2
        let gap = hGap
        let margin: CGFloat = 10
        let W = availableSize.width
        let H = availableSize.height

        guard !orientedTiles.isEmpty else {
            return ([], false, .zero, .zero, 0, 0)
        }

        // A real chain is laid in runs. Each run is a straight line; when it
        // reaches the edge of the table the NEXT tile is turned across the run
        // and the following run starts directly below it, heading back the
        // other way. Runs are one tile-and-a-gap apart, which is exactly the
        // clearance a crosswise double needs, so runs can never touch however
        // many doubles the chain contains.
        // Runs sit one gap apart, as they do on a real table. A crosswise
        // double sticks out half a tile, so the row beneath it is nudged down
        // by the safety net below -- that ragged local bow is what a real
        // chain does around its doubles.
        // Two parallel runs each need room for a crosswise double, which
        // stands half a tile proud on both sides: short + 2 * (long - short)/2
        // = long. Plus one gap. Rows this far apart can NEVER need nudging,
        // so the chain stays regular instead of staggering tile by tile.
        let rowPitch = long + gap
        let minX = margin
        // A chain laid edge to edge reads as a stripe, however correct its
        // geometry -- a live report of exactly that. A real game coils in the
        // middle of the table: runs get about two thirds of the width, bounded
        // so a run is never fewer than six tiles nor absurd on an ultrawide
        // board. Tiles themselves never change size.
        let tilePitch = short * 2 + gap
        let idealRun = W * 0.66
        let tableWidth = min(max(idealRun, tilePitch * 6), tilePitch * 14, W - margin * 2)
        let maxX = minX + tableWidth

        // Start a full long-axis below the top margin: a crosswise double in
        // the opening run extends short/2 above its line, so centring the
        // first row on short/2 alone would clip 9pt off the top of a 6-6.
        var rowY = margin + long / 2
        var east = true
        var cursorX = minX
        var placed: [Placed] = []
        var rects: [CGRect] = []

        func rect(center: CGPoint, vertical: Bool) -> CGRect {
            let w = vertical ? short : long
            let h = vertical ? long : short
            return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        }

        // A run must stop early enough that its own corner still fits inside
        // the table. Filling to the edge forced the corner back over the last
        // tile, which tripped the safety net and pushed the corner and the
        // tile after it downwards -- the dangling tiles a live test caught.
        let cornerReserve = min(short + gap, tableWidth / 2)

        for (index, tile) in orientedTiles.enumerated() {
            let width = tile.isDouble ? short : long
            let room = east ? (maxX - cornerReserve) - cursorX
                            : cursorX - (minX + cornerReserve)
            // The last tile never turns: a corner exists to start another run,
            // and with nothing left to place it is just a stub hanging off the
            // end of the chain. Let the chain finish in line instead.
            let isLastTile = index == orientedTiles.count - 1
            if room >= width || isLastTile {
                let center = CGPoint(x: east ? cursorX + width / 2 : cursorX - width / 2,
                                     y: rowY)
                placed.append(Placed(x: center.x, y: center.y, tile: tile,
                                     vertical: tile.isDouble))
                rects.append(rect(center: center, vertical: tile.isDouble))
                cursorX += east ? width + gap : -(width + gap)
                continue
            }

            // End of the run: this tile is the corner, lying across it. The
            // corner sits ON its run's line, not below it. Offset below (the
            // old geometry) its long face reached into the band and collided
            // with the first tile of the return run whenever that tile was a
            // crosswise double; the de-overlap net then shoved that tile down
            // 19pt, which is the staircase a live test caught.
            //
            // On the line, the corner spans [rowY - 38, rowY + 38] and the
            // worst case beneath it -- a double at rowY + rowPitch -- starts
            // 4pt clear: (rowY + 80 - 38) - (rowY + 38) = 4 = the tile gap.
            let cornerX = east ? min(cursorX + short / 2, maxX - short / 2)
                               : max(cursorX - short / 2, minX + short / 2)
            let cornerY = rowY
            let corner = CGPoint(x: cornerX, y: cornerY)
            placed.append(Placed(x: corner.x, y: corner.y, tile: tile, vertical: true))
            rects.append(rect(center: corner, vertical: true))

            rowY += rowPitch
            east.toggle()
            // The return run starts from the corner's far EDGE, not its centre.
            // Using the centre put the first tile half a tile to the side, so
            // the corner and that tile overlapped diagonally and the turn read
            // as a pile of verticals -- the right-hand mess a live test caught.
            // Heading east, the next tile extends right from its left edge;
            // heading west, from its right edge.
            cursorX = corner.x + (east ? -short / 2 : short / 2)
        }

        // Safety net: no tile may ever be drawn on top of another. The row
        // logic only aims a tile at an occupied spot when the table is too
        // small for the chain; in that case the tile drops to the next free
        // row instead. Overlap is the one thing a real chain cannot do.
        var cleanPlaced: [Placed] = []
        var cleanRects: [CGRect] = []
        for tile in placed {
            var candidate = tile
            var attempts = 0
            var probe = rect(center: CGPoint(x: candidate.x, y: candidate.y),
                             vertical: candidate.vertical)
            while cleanRects.contains(where: { $0.intersects(probe) }) && attempts < 200 {
                candidate = Placed(x: candidate.x, y: candidate.y + short / 2,
                                   tile: candidate.tile, vertical: candidate.vertical)
                probe = rect(center: CGPoint(x: candidate.x, y: candidate.y),
                             vertical: candidate.vertical)
                attempts += 1
            }
            cleanPlaced.append(candidate)
            cleanRects.append(probe)
        }
        placed = cleanPlaced
        rects = cleanRects

        var minPX = CGFloat.infinity, maxPX = -CGFloat.infinity
        var minPY = CGFloat.infinity, maxPY = -CGFloat.infinity
        for r in rects {
            minPX = min(minPX, r.minX); maxPX = max(maxPX, r.maxX)
            minPY = min(minPY, r.minY); maxPY = max(maxPY, r.maxY)
        }
        let contentW = maxPX - minPX
        let contentH = maxPY - minPY

        let first = placed[0]
        let last = placed[placed.count - 1]
        var head = CGPoint(x: first.x - (first.vertical ? 0 : long / 2) - gap,
                           y: first.y)
        var tail = CGPoint(x: last.x + (last.vertical ? 0 : long / 2) + gap,
                           y: last.y)
        var finalPlaced = placed

        // Centre the finished chain when it already fits; an oversized one
        // keeps its coordinates and relies on the uniform scale plus pan.
        if contentW <= W && contentH <= H {
            let shiftX = W / 2 - (minPX + maxPX) / 2
            let shiftY = H / 2 - (minPY + maxPY) / 2
            finalPlaced = placed.map {
                Placed(x: $0.x + shiftX, y: $0.y + shiftY,
                       tile: $0.tile, vertical: $0.vertical)
            }
            head = CGPoint(x: head.x + shiftX, y: head.y + shiftY)
            tail = CGPoint(x: tail.x + shiftX, y: tail.y + shiftY)
        }

        return (finalPlaced, false, head, tail, contentW, contentH)
    }


    /// The table's real behaviour: use smaller tiles until the chain can be
    /// laid out without a gap. A chain that needs an escape step at full size
    /// is re-laid at 90% and tried again, down to the readability floor. The
    /// resulting size is reported as `suggestedScale`, which the board applies
    /// to positions and tile size together -- so adjacency and the 2:1 law
    /// survive the shrink exactly.
    static func compute(orientedTiles: [Oriented], availableSize: CGSize) -> Metrics {
        let path = layoutPath(orientedTiles: orientedTiles,
                              availableSize: availableSize,
                              short: tileShortAxis)
        guard !path.placed.isEmpty else {
            return Metrics(placed: [], headPosition: nil, tailPosition: nil,
                           contentWidth: 0, contentHeight: 0, suggestedScale: 1)
        }
        return Metrics(placed: path.placed, headPosition: path.head, tailPosition: path.tail,
                       contentWidth: path.contentWidth, contentHeight: path.contentHeight,
                       suggestedScale: fitScale(contentWidth: path.contentWidth,
                                                contentHeight: path.contentHeight,
                                                availableSize: availableSize))
    }


    /// Physical dominoes do not change size to match the window. Scaling the
    /// board to fit made a long chain a thin stripe of unreadable tiles and a
    /// short one an oversized block -- two live complaints from one policy.
    /// The chain now keeps its true size and turns at the table edge; a chain
    /// taller than the table is reached by panning, which already exists.
    static func fitScale(contentWidth: CGFloat, contentHeight: CGFloat, availableSize: CGSize) -> CGFloat {
        _ = contentWidth; _ = contentHeight; _ = availableSize
        return 1
    }
}

// MARK: - Endpoint affordances

/// A thin mark on the open edge of an end tile. It exists only when a real
/// move is available there, and brightens only when the selected tile can
/// land on it. No ring, no pip badge, no pulse.
private struct EndEdgeHighlight: View {
    let active: Bool
    let leading: Bool

    var body: some View {
        Capsule()
            .fill(IsolynTheme.ivory.opacity(active ? 0.8 : 0.3))
            .frame(width: 2.25, height: SnakeChainLayout.tileShortAxis * 0.68)
            .offset(x: leading ? -3 : 3)
            .shadow(color: IsolynTheme.ivory.opacity(active ? 0.18 : 0), radius: 2)
            .animation(.easeOut(duration: 0.14), value: active)
            .allowsHitTesting(false)
    }
}

/// The hit area stays large, but the visual is carried by the edge mark on
/// the tile itself. This keeps placement reachable without adding UI.
private struct EndTarget: View {
    let side: ChainSide
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(width: SnakeChainLayout.endTargetDiameter,
                       height: SnakeChainLayout.endTargetDiameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BoardDropTargetFrames.self,
                    value: [side: proxy.frame(in: .named(GameSurfaceCoordinateSpace.name))]
                )
            }
        )
        .accessibilityLabel(label)
        .accessibilityHint("Places the selected domino here.")
    }
}

enum GameSurfaceCoordinateSpace {
    static let name = "gameSurface"
}

private struct BoardDropTargetFrames: PreferenceKey {
    static let defaultValue: [ChainSide: CGRect] = [:]

    static func reduce(value: inout [ChainSide: CGRect], nextValue: () -> [ChainSide: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Position helper

extension View {
    /// Positions this view by its CENTER within the parent coordinate space.
    fileprivate func position(_ x: CGFloat, _ y: CGFloat) -> some View {
        self.position(CGPoint(x: x, y: y))
    }
}
