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
        .frame(width: availableSize.width, height: availableSize.height)
        .background(
            InspectionEventMonitor(
                button: inspectionSettings.mouseButton,
                tracker: hoverTracker,
                onInspect: onInspectFace
            )
        )
        // ONE uniform auto-fit scale (§17 "scale the board intelligently";
        // completes the mandate's responsive clause).
        .scaleEffect(metrics.suggestedScale)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: snapshot.stateVersion)
        .onAppear { raiseCameraBounds(residualX, residualY) }
        .onChange(of: boundsSignature) { _, _ in raiseCameraBounds(residualX, residualY) }
        .onChange(of: snapshot.stateVersion) { _, _ in hoverTracker.clearAll() }
        .onChange(of: camera.offsetX) { _, _ in hoverTracker.clearAll() }
        .onChange(of: camera.offsetY) { _, _ in hoverTracker.clearAll() }
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
    static let hGap: CGFloat = 4
    /// Row pitch leaves room for perpendicular doubles (long axis 76)
    /// to protrude into the inter-row band without touching neighbours.
    static var rowPitch: CGFloat { tileShortAxis * 2 + 4 }
    /// Invisible end-target hit area. The visible affordance stays a thin
    /// 2.25pt tick, but a release anywhere inside this generous square (plus
    /// `HandDropResolver.dropPadding`) counts as landing on the end.
    static let endTargetDiameter: CGFloat = 96
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

        // A vertical tile is only half as wide as a horizontal one. Advancing
        // a full cell after it left ~23pt of dead air on both sides of every
        // double -- the exact "space is so big for doubles" gap. Advance by
        // the two tiles' real half-widths instead, so perpendicular doubles
        // and corner caps sit at the same 4pt visual gap as every other tile.
        func isTurn(at index: Int, column: Int, direction: CGFloat) -> Bool {
            let remainingAfter = orientedTiles.count - index - 1
            return remainingAfter > 0 &&
                ((direction > 0 && column == cols - 1) || (direction < 0 && column == 0))
        }

        var i = 0
        while i < orientedTiles.count {
            let t = orientedTiles[i]
            let needsTurn = isTurn(at: i, column: col, direction: dir)

            if needsTurn {
                // CORNER: this tile turns the run -- rendered VERTICAL as a
                // perpendicular end-cap IN its own row cell; the next row
                // starts in this same column. The cell pitch still leaves
                // the long axis room, but horizontal neighbours were already
                // advanced against this tile's narrow visual width.
                placed.append(Placed(x: centerX, y: rowY(row), tile: t, vertical: true))
                row += 1
                dir *= -1
                i += 1
                continue
            }

            let vertical = t.isDouble
            placed.append(Placed(x: centerX, y: rowY(row), tile: t, vertical: vertical))

            let nextColumn = col + Int(dir)
            let nextIsVertical = i + 1 < orientedTiles.count &&
                (orientedTiles[i + 1].isDouble ||
                 isTurn(at: i + 1, column: nextColumn, direction: dir))
            let currentHalfWidth = vertical ? tileShortAxis / 2 : tileShortAxis
            let nextHalfWidth = nextIsVertical ? tileShortAxis / 2 : tileShortAxis
            centerX += dir * (currentHalfWidth + hGap + nextHalfWidth)
            col = nextColumn
            i += 1
        }

        guard let first = placed.first, let last = placed.last else {
            return Metrics(placed: [], headPosition: nil, tailPosition: nil,
                           contentWidth: 0, contentHeight: 0, suggestedScale: 1)
        }
        let headDirIn: CGFloat = 1
        let tailDir = dir
        let firstHalfWidth = first.vertical ? tileShortAxis / 2 : tileShortAxis
        let lastHalfWidth = last.vertical ? tileShortAxis / 2 : tileShortAxis
        let headPos = CGPoint(x: first.x - headDirIn * (firstHalfWidth + 22), y: first.y)
        let tailPos = CGPoint(x: last.x + tailDir * (lastHalfWidth + 22), y: last.y)

        // Extent is the actual domino geometry only. Endpoint hit targets
        // are invisible now, so their clearance must not push the visible
        // chain off-center on a wide table.
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for p in placed {
            let halfX: CGFloat = p.vertical ? tileShortAxis / 2 : tileShortAxis
            let halfY: CGFloat = p.vertical ? tileShortAxis : tileShortAxis / 2
            minX = min(minX, p.x - halfX); maxX = max(maxX, p.x + halfX)
            minY = min(minY, p.y - halfY); maxY = max(maxY, p.y + halfY)
        }

        let contentW = maxX - minX
        let contentH = maxY - minY

        // The snake algorithm starts at the left edge of a column grid so
        // that long chains have a stable row structure. For ordinary short
        // chains that leaves the board visually off-center on a wide display.
        // Translate the completed plane's bounding box to the table center
        // whenever it already fits; oversized chains keep their established
        // coordinates and rely on auto-fit plus camera pan.
        var finalPlaced = placed
        var finalHead = headPos
        var finalTail = tailPos
        if contentW <= W && contentH <= H {
            let shiftX = midX - (minX + maxX) / 2
            let shiftY = midY - (minY + maxY) / 2
            finalPlaced = placed.map {
                Placed(x: $0.x + shiftX, y: $0.y + shiftY,
                       tile: $0.tile, vertical: $0.vertical)
            }
            finalHead = CGPoint(x: headPos.x + shiftX, y: headPos.y + shiftY)
            finalTail = CGPoint(x: tailPos.x + shiftX, y: tailPos.y + shiftY)
        }

        return Metrics(placed: finalPlaced, headPosition: finalHead, tailPosition: finalTail,
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
