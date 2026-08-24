#include "MoveValidator.hpp"
#include <algorithm>

namespace isolyn {

bool MoveValidator::isLegal(const GameState& state, int playerIndex, const Move& move) {
    const auto& hand = state.hand(playerIndex);
    if (std::find(hand.begin(), hand.end(), move.tile) == hand.end()) {
        return false;
    }

    if (state.chain().isEmpty()) {
        return true;
    }

    const int end = (move.side == GameState::ChainSide::Left)
                         ? state.chain().leftEnd()
                         : state.chain().rightEnd();
    return move.tile.hasFace(end);
}

} // namespace isolyn
