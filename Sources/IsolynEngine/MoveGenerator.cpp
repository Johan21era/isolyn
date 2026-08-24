#include "MoveGenerator.hpp"

namespace isolyn {

std::vector<Move> MoveGenerator::generate(const GameState& state, int playerIndex) {
    std::vector<Move> moves;
    const auto& hand = state.hand(playerIndex);

    if (state.chain().isEmpty()) {
        // Side is irrelevant for an opening play -- GameState::playTile
        // ignores it and opens the chain regardless. Left is used here
        // only as a stable, deterministic placeholder value.
        for (const auto& tile : hand) {
            moves.push_back(Move{tile, GameState::ChainSide::Left});
        }
        return moves;
    }

    const int leftEnd = state.chain().leftEnd();
    const int rightEnd = state.chain().rightEnd();

    for (const auto& tile : hand) {
        // Deliberately not else-if: if both ends happen to show the same
        // value (which can happen for reasons unrelated to the last tile
        // placed being a double -- it's just a property of the current
        // chain shape) and this tile matches, playing it left vs. right
        // are genuinely distinct legal moves with potentially different
        // resulting end values, not the same move counted twice.
        if (tile.hasFace(leftEnd)) {
            moves.push_back(Move{tile, GameState::ChainSide::Left});
        }
        if (tile.hasFace(rightEnd)) {
            moves.push_back(Move{tile, GameState::ChainSide::Right});
        }
    }

    return moves;
}

bool MoveGenerator::hasAnyLegalMove(const GameState& state, int playerIndex) {
    const auto& hand = state.hand(playerIndex);
    if (state.chain().isEmpty()) {
        return !hand.empty();
    }
    const int leftEnd = state.chain().leftEnd();
    const int rightEnd = state.chain().rightEnd();
    for (const auto& tile : hand) {
        if (tile.hasFace(leftEnd) || tile.hasFace(rightEnd)) return true;
    }
    return false;
}

bool MoveGenerator::isPositionClosed(const GameState& state) {
    if (state.boneyard().drawableCount() > 0) return false;
    for (int p = 0; p < state.playerCount(); ++p) {
        if (hasAnyLegalMove(state, p)) return false;
    }
    return true;
}

} // namespace isolyn
