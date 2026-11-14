import SwiftUI
import IsolynEngineBridge
import Foundation
import AppKit

/// The player's hand (docs/history/2026-08-ui-rebuild-mandate.md §9/§10).
///
/// A real collection of dominoes: every tile is the CANONICAL
/// single-rectangle renderer at identical dimensions — only values differ.
/// Selecting lifts a tile slightly and outlines it WITHOUT reflowing the
/// row (scale/offset never affect layout). No fake slots, no empty
/// containers; the row is exactly as long as the hand.
///
/// Dragging is a first-class interaction here: the rack reports the pointer
/// in the shared game-surface coordinate space, the table owns the floating
/// preview, and a release over a legal end target plays the move. Tapping
/// remains the deliberate fallback for ambiguous ends.
struct HandRackView: View {
    let hand: [Tile]
    let legalMoves: Set<Move>
    /// True when both open chain ends show the same number. Double-clicking a
    /// tile that fits both is then a genuinely equivalent choice, so the rack
    /// may route it to either side at random.
    let openEndsMatch: Bool
    @Binding var selectedTile: Tile?
    let interactive: Bool
    let draggingTile: Tile?
    var onDragBegan: (Tile, CGPoint, CGSize) -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void
    var onPlay: (Move) -> Void

    static let tileHeight: CGFloat = 48   // larger hand tiles; still fits 7 across
    private let spacing: CGFloat = 6

    @State private var activeDrag: Tile?
    @State private var suppressTapUntil = Date.distantPast
    @State private var lastTapTile: Tile?
    @State private var lastTapAt = Date.distantPast
    @State private var tileFrames: [Tile: CGRect] = [:]

    var body: some View {
        let sorted = hand.sorted { a, b in
            if a.high != b.high { return a.high > b.high }
            return a.low > b.low
        }

        HStack(spacing: spacing) {
            ForEach(sorted, id: \.self) { tile in
                tileView(tile)
                    .opacity(draggingTile == tile ? 0 : 1)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 28).combined(with: .opacity),
                            removal: .scale(scale: 0.82).combined(with: .opacity)
                        )
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onPreferenceChange(HandTileFramesKey.self) { tileFrames = $0 }
        .animation(.easeOut(duration: 0.28), value: sorted)
    }

    private func tileView(_ tile: Tile) -> some View {
        let playableSides = playableSides(for: tile)
        let isSelected = selectedTile == tile
        // An unplayable domino is still a face-up domino. It keeps its
        // full ivory body and only loses the playable outline; it is never
        // faded into the black table.
        let state: TileState = {
            guard interactive else { return .idle }
            if isSelected { return .selected }
            return playableSides.isEmpty ? .idle : .playable
        }()

        return Button {
            // A click can resolve on mouse-up after a short drag; ignore it
            // so the just-dropped tile is not immediately deselected.
            guard Date() >= suppressTapUntil else { return }
            handleTap(tile, sides: playableSides)
        } label: {
            IsolynDominoTile(
                leftPips: tile.low,
                rightPips: tile.high,
                height: Self.tileHeight,
                state: state
            )
            // Lift on selection WITHOUT layout shift: offset/scale are
            // render-only, so neighbours never jump (§9).
            .offset(y: isSelected ? -6 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HandTileFramesKey.self,
                    value: [tile: proxy.frame(in: .named(GameSurfaceCoordinateSpace.name))]
                )
            }
        )
        .highPriorityGesture(dragGesture(for: tile, sides: playableSides))
        // Do not use disabled-button treatment: an unplayable face stays
        // fully ivory. It simply isn't a live interaction target.
        .allowsHitTesting(interactive && !playableSides.isEmpty)
        .accessibilityLabel("Domino \(tile.high)-\(tile.low)\(playableSides.isEmpty ? "" : ", playable")")
        .accessibilityHint(accessibilityHint(sides: playableSides, isSelected: isSelected))
        .animation(.easeOut(duration: 0.14), value: isSelected)   // §25 window
    }

    private func dragGesture(for tile: Tile, sides: Set<ChainSide>) -> some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(GameSurfaceCoordinateSpace.name)
        )
        .onChanged { value in
            guard interactive, !sides.isEmpty else { return }
            if activeDrag == nil {
                activeDrag = tile
                let frame = tileFrames[tile]
                let center = frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? value.startLocation
                let grabOffset = CGSize(
                    width: center.x - value.startLocation.x,
                    height: center.y - value.startLocation.y
                )
                onDragBegan(tile, value.location, grabOffset)
            }
            onDragChanged(value.location)
        }
        .onEnded { value in
            guard activeDrag == tile else { return }
            activeDrag = nil
            // A click gesture can still resolve on mouse-up after a short
            // drag. Swallow that one tap instead of deselecting the tile the
            // player just dropped.
            suppressTapUntil = Date().addingTimeInterval(0.15)
            onDragEnded(value.location)
        }
    }

    /// Which sides this tile can legally land on right now.
    private func playableSides(for tile: Tile) -> Set<ChainSide> {
        Set(legalMoves.filter { $0.tile == tile }.map { $0.side })
    }

    private func handleTap(_ tile: Tile, sides: Set<ChainSide>) {
        guard interactive else { return }
        let now = Date()
        guard now >= suppressTapUntil else { return }

        // A second click inside the system double-click interval is a
        // double-click, not another tap-tap decision. Route only when the
        // result is genuinely equivalent (both open ends match); otherwise
        // preserve the deliberate "choose an end" path.
        if lastTapTile == tile,
           now.timeIntervalSince(lastTapAt) <= NSEvent.doubleClickInterval {
            lastTapTile = nil
            lastTapAt = .distantPast
            handleDoubleClick(tile)
            return
        }

        lastTapTile = tile
        lastTapAt = now

        // Tap-tap flow: selecting an already-selected tile whose ONLY legal
        // placement is unambiguous plays it immediately; otherwise the
        // player taps the matching end marker on the board.
        if selectedTile == tile {
            if sides.count == 1, let only = sides.first,
               let move = legalMoves.first(where: { $0.tile == tile && $0.side == only }) {
                selectedTile = nil
                onPlay(move)
                return
            }
            selectedTile = nil   // deselect
            return
        }
        selectedTile = tile
    }

    private func handleDoubleClick(_ tile: Tile) {
        if let move = HandTapRouter.automaticMove(
            for: tile,
            legalMoves: Array(legalMoves),
            openEndsMatch: openEndsMatch
        ) {
            selectedTile = nil
            onPlay(move)
        } else {
            // Two genuinely different ends: keep the player in charge rather
            // than guessing at a strategic choice.
            selectedTile = nil
        }
    }

    private func accessibilityHint(sides: Set<ChainSide>, isSelected: Bool) -> String {
        if sides.count > 1 && openEndsMatch {
            return isSelected
                ? "Selected. Double-click to place on either matching end."
                : "Selects this domino; double-click to place on either matching end."
        }
        return isSelected ? "Selected. Choose an end on the board." : "Selects this domino."
    }
}

private struct HandTileFramesKey: PreferenceKey {
    static let defaultValue: [Tile: CGRect] = [:]

    static func reduce(value: inout [Tile: CGRect], nextValue: () -> [Tile: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
