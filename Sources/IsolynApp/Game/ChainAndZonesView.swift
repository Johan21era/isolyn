import SwiftUI
import IsolynEngineBridge

/// The pannable chain area with integrated camera, gesture arbitration,
/// and hover-chain overlay. All three systems coexist here.
struct ChainAndZonesView: View {
    let snapshot: GameSnapshot?
    let canPlay: Bool
    let appearance: DominoAppearance
    @Binding var selectedTile: Tile?
    let camera: BoardCamera
    let arbiter: GestureArbiter
    let hoverController: HoverChainController
    let onPlay: (Move) -> Void

    @State private var currentDragTranslation: CGSize = .zero
    @State private var lastMouseLocation: CGPoint? = nil

    var body: some View {
        ZStack {
            // Camera-transformed content
            VStack(spacing: 10) {
                if let snap = snapshot {
                    ChainTilesView(snapshot: snap, appearance: appearance)
                    endZones(for: snap)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .offset(x: camera.offsetX, y: camera.offsetY)

            // Hover chain overlay (floats above board)
            if let chain = hoverController.builtChain, !camera.isDragging {
                VStack {
                    HStack { Spacer()
                        HoverChainOverlay(
                            chain: chain,
                            appearance: appearance,
                            onClose: { hoverController.dismiss() }
                        )
                        .padding(.trailing, 20)
                        // Hovering the panel itself keeps it open.
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
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                lastMouseLocation = location
            case .ended:
                // Don't dismiss immediately — allow pointer to enter overlay
                break
            }
        }
        .gesture(boardDragGesture.simultaneously(with: tapGesture))
        .onTapGesture {} // consume bare clicks so they don't fall through
    }

    // MARK: - End zone buttons

    @ViewBuilder
    private func endZones(for snap: GameSnapshot) -> some View {
        if snap.chain.isEmpty && canPlay {
            openChainZone
        } else if !snap.chain.isEmpty {
            HStack(spacing: 60) {
                endZone(side: .left, pip: snap.chainLeftEnd ?? 0)
                endZone(side: .right, pip: snap.chainRightEnd ?? 0)
            }
        }
    }

    private var openChainZone: some View {
        let playable = isSelectedPlayable
        return Button { playOpening() } label: {
            Label("Open", systemImage: "plus.diamond")
                .font(IsolynTheme.body(13))
                .foregroundStyle(playable ? IsolynTheme.ebony : IsolynTheme.ivoryMuted)
                .padding(.horizontal, 22).padding(.vertical, 9)
                .background(Capsule().fill(playable ? IsolynTheme.brass : IsolynTheme.ebonyElevated))
        }.buttonStyle(.plain).disabled(!playable)
    }

    private func endZone(side: ChainSide, pip: Int) -> some View {
        let playable = selectedSideIsPlayable(side)
        return Button { playOnSide(side) } label: {
            VStack(spacing: 3) {
                Text("\(pip)").font(IsolynTheme.display(17)).monospacedDigit()
                Text(side == .left ? "LEFT" : "RIGHT").font(IsolynTheme.caption(9)).tracking(1.5)
            }
            .foregroundStyle(playable ? IsolynTheme.ebony : IsolynTheme.ivoryMuted)
            .padding(.horizontal, 26).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(
                playable ? IsolynTheme.brass : IsolynTheme.ebonyElevated))
        }.buttonStyle(.plain).disabled(!playable)
        .onHover { hovering in
            if hovering && !arbiter.isDragging {
                // Endpoint hover triggers the number-family analysis and
                // cancels any pending dismissal (pointer is back).
                hoverController.cancelScheduledDismissal()
                hoverController.setTarget(pip, snapshot: snapshot)
            } else if !hovering {
                // FIX-26 (N-3): leaving the zone starts the grace-period
                // countdown; hovering the overlay itself cancels it.
                hoverController.scheduleDismissal()
            }
        }
    }

    // MARK: - Gestures

    /// Board pan via click-drag on any non-domino surface.
    /// Uses GestureArbiter for classification: once past threshold → board pan owns.
    private var boardDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if arbiter.owner == .idle {
                    arbiter.pointerDown(at: value.startLocation)
                    camera.beginDrag(at: value.startLocation)
                    currentDragTranslation = .zero
                }
                arbiter.pointerMoved(to: value.location, targetIsDomino: false)
                if arbiter.isBoardPanning {
                    currentDragTranslation = value.translation
                    camera.updateDrag(translation: value.translation)
                    hoverController.suspend() // freeze hover during pan
                }
            }
            .onEnded { value in
                let wasTap = arbiter.pointerUp()
                camera.endDrag(lastLocation: lastMouseLocation)
                currentDragTranslation = .zero
                if !wasTap {
                    // Resume hover after a brief settle delay
                    Task { try? await Task.sleep(nanoseconds: 200_000_000)
                        hoverController.resume(snapshot: snapshot, target: hoverTargetAtLastLocation)
                    }
                }
            }
    }

    /// Bare tap (down→up without threshold crossing).
    private var tapGesture: some Gesture {
        TapGesture(count: 1).onEnded {
            _ = arbiter.pointerUp() // returns true for tap; clear selection
            selectedTile = nil
        }
    }

    // MARK: - Selection helpers

    private var isSelectedPlayable: Bool {
        guard let tile = selectedTile else { return false }
        guard let snap = snapshot else { return false }
        return Set(snap.legalMoves).contains { $0.tile == tile }
    }

    private func selectedSideIsPlayable(_ side: ChainSide) -> Bool {
        guard let tile = selectedTile, let snap = snapshot else { return false }
        return Set(snap.legalMoves).contains { $0.tile == tile && $0.side == side }
    }

    private func playOnSide(_ side: ChainSide) {
        guard let tile = selectedTile, let snap = snapshot,
              let move = Set(snap.legalMoves).first(where: { $0.tile == tile && $0.side == side }) else { return }
        selectedTile = nil
        hoverController.dismiss()   // FIX-26: board changed; analysis is stale
        onPlay(move)
    }

    private func playOpening() {
        guard let tile = selectedTile, let snap = snapshot,
              let move = Set(snap.legalMoves).first(where: { $0.tile == tile }) else { return }
        selectedTile = nil
        hoverController.dismiss()   // FIX-26: board changed; analysis is stale
        onPlay(move)
    }

    // MARK: - Hover resolution

    // FIX-26 note: whole-tile world-space hover was never built; the only
    // real entry points are the per-end-zone .onHover handlers above. The
    // old no-op handleHover(at:) stub that pretended otherwise is deleted
    // -- comments must not promise behavior that does not exist.

    private var hoverTargetAtLastLocation: Int? {
        // Re-resolve from last known position after drag settles.
        // Simplified: keep last active target if still visible.
        return hoverController.activeTarget
    }
}

// MARK: - Chain tiles with appearance

struct ChainTilesView: View {
    let snapshot: GameSnapshot
    let appearance: DominoAppearance

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(orientedTiles.enumerated()), id: \.offset) { _, dt in
                    IsolynDominoTile(displayingLeft: dt.left, right: dt.right,
                                     isDouble: dt.isDouble,
                                     height: 22, appearance: appearance)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(minHeight: 70)
    }

    private struct OrientedTile { let left: Int; let right: Int; let isDouble: Bool }

    private var orientedTiles: [OrientedTile] {
        var result: [OrientedTile] = []
        guard let leftEnd = snapshot.chainLeftEnd else { return result }
        var touching = leftEnd
        for tile in snapshot.chain {
            guard tile.hasFace(touching) else {
                result.append(OrientedTile(left: tile.low, right: tile.high, isDouble: tile.low == tile.high)); continue
            }
            let other = tile.low == touching ? tile.high : tile.low
            result.append(OrientedTile(left: touching, right: other, isDouble: tile.low == tile.high))
            touching = other
        }
        return result
    }
}
