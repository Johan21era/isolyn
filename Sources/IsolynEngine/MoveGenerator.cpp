#include "MoveGenerator.hpp"

#include <cassert>

namespace isolyn {

std::size_t MoveGenerator::generateInto(const GameState& state,
                                        int playerIndex,
                                        std::array<Move, kMaxMoves>& moves) noexcept {
    std::size_t count = 0;
    const auto& hand = state.hand(playerIndex);
    auto append = [&](DominoTile tile, GameState::ChainSide side) {
        assert(count < kMaxMoves);
        moves[count++] = Move{tile, side};
    };

    if (state.chain().isEmpty()) {
        // Side is irrelevant for an opening play -- GameState::playTile
        // ignores it and opens the chain regardless. Left is used here
        // only as a stable, deterministic placeholder value.
        for (const auto& tile : hand) {
            append(tile, GameState::ChainSide::Left);
        }
        return count;
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
            append(tile, GameState::ChainSide::Left);
        }
        if (tile.hasFace(rightEnd)) {
            append(tile, GameState::ChainSide::Right);
        }
    }

    return count;
}

std::vector<Move> MoveGenerator::generate(const GameState& state, int playerIndex) {
    std::vector<Move> moves;
    const auto& hand = state.hand(playerIndex);
    moves.reserve(hand.size() * 2);

    if (state.chain().isEmpty()) {
        for (const auto& tile : hand) {
            moves.push_back(Move{tile, GameState::ChainSide::Left});
        }
        return moves;
    }

    const int leftEnd = state.chain().leftEnd();
    const int rightEnd = state.chain().rightEnd();
    for (const auto& tile : hand) {
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

int MoveGenerator::countLegalMoves(const GameState& state, int playerIndex) {
    const auto& hand = state.hand(playerIndex);
    if (state.chain().isEmpty()) {
        return static_cast<int>(hand.size());
    }

    const int leftEnd = state.chain().leftEnd();
    const int rightEnd = state.chain().rightEnd();
    int count = 0;
    for (const auto& tile : hand) {
        if (tile.hasFace(leftEnd)) ++count;
        if (tile.hasFace(rightEnd)) ++count;
    }
    return count;
}

bool MoveGenerator::isPositionClosed(const GameState& state) {
    if (state.boneyard().drawableCount() > 0) return false;
    for (int p = 0; p < state.playerCount(); ++p) {
        if (hasAnyLegalMove(state, p)) return false;
    }
    return true;
}

} // namespace isolyn
