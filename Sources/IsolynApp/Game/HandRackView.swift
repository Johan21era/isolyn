import SwiftUI
import IsolynEngineBridge

/// The player's hand (dominoes_ui_fix_non_negotiable.md §9/§10).
///
/// A real collection of dominoes: every tile is the CANONICAL
/// single-rectangle renderer at identical dimensions — only values differ.
/// Selecting lifts a tile slightly and outlines it WITHOUT reflowing the
/// row (scale/offset never affect layout). No fake slots, no empty
/// containers; the row is exactly as long as the hand.
struct HandRackView: View {
    let hand: [Tile]
    let legalMoves: Set<Move>
    @Binding var selectedTile: Tile?
    let interactive: Bool
    var onPlay: (Move) -> Void

    private let tileShortAxis: CGFloat = 34   // prominent, readable hand tiles
    private let spacing: CGFloat = 8          // §16 scale

    var body: some View {
        let sorted = hand.sorted { a, b in
            if a.high != b.high { return a.high > b.high }
            return a.low > b.low
        }

        HStack(spacing: spacing) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, tile in
                tileButton(tile)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func tileButton(_ tile: Tile) -> some View {
        let playableSides = playableSides(for: tile)
        let isSelected = selectedTile == tile
        let state: TileState = {
            if !interactive { return .dimmed }
            if isSelected { return .selected }
            if playableSides.isEmpty { return .dimmed }
            return .playable
        }()

        return Button {
            handleTap(tile, sides: playableSides)
        } label: {
            IsolynDominoTile(leftPips: tile.low, rightPips: tile.high,
                             height: tileShortAxis, state: state)
                // Lift on selection WITHOUT layout shift: offset/scale are
                // render-only, so neighbours never jump (§9).
                .offset(y: isSelected ? -6 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!interactive || playableSides.isEmpty)
        .accessibilityLabel("Domino \(tile.high)-\(tile.low)\(playableSides.isEmpty ? "" : ", playable")")
        .accessibilityHint(isSelected ? "Selected. Choose an end marker on the board." : "Selects this domino.")
        .animation(.easeOut(duration: 0.14), value: isSelected)   // §25 window
    }

    /// Which sides this tile can legally land on right now.
    private func playableSides(for tile: Tile) -> Set<ChainSide> {
        Set(legalMoves.filter { $0.tile == tile }.map { $0.side })
    }

    private func handleTap(_ tile: Tile, sides: Set<ChainSide>) {
        guard interactive else { return }
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
}
