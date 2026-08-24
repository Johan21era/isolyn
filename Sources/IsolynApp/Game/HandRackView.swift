import SwiftUI
import IsolynEngineBridge

/// The active player's rack. Sorted high-desc/low-desc for scannability;
/// legality dimming comes from the view model's legalMoveSet so a tile with
/// no matching end grays out the instant it's dealt -- instant feedback, with
/// the bridge's authoritative InvalidMove still standing behind every submit.
struct HandRackView: View {
    let hand: [Tile]
    let legalMoves: Set<Move>
    @Binding var selectedTile: Tile?
    let interactive: Bool
    var onPlay: (Move) -> Void

    var body: some View {
        let sorted = hand.sorted { a, b in
            if a.high != b.high { return a.high > b.high }
            return a.low > b.low
        }

        HStack(spacing: 10) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, tile in
                tileButton(tile)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
            IsolynDominoTile(tile: tile, height: 24, state: state)
        }
        .buttonStyle(.plain)
        .disabled(!interactive || playableSides.isEmpty)
        .accessibilityLabel("Domino \(tile.high)-\(tile.low)\(playableSides.isEmpty ? "" : ", playable")")
        .accessibilityHint(isSelected ? "Selected. Choose an end." : "Selects this domino.")
    }

    /// Which sides this tile can legally land on right now.
    private func playableSides(for tile: Tile) -> Set<ChainSide> {
        Set(legalMoves.filter { $0.tile == tile }.map { $0.side })
    }

    private func handleTap(_ tile: Tile, sides: Set<ChainSide>) {
        guard interactive else { return }
        // Tap-tap flow: selecting an already-selected tile whose ONLY legal
        // placement is unambiguous plays it immediately; otherwise selection
        // waits for an end-zone tap below the chain.
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
