#include "MoveExecutor.hpp"
#include "MoveValidator.hpp"
#include <cassert>

namespace isolyn {

AppliedMove MoveExecutor::apply(GameState& state, int playerIndex, const Move& move) {
    assert(MoveValidator::isLegal(state, playerIndex, move) &&
           "MoveExecutor::apply requires an already-legal move; validate before calling");
    GameState::PlacementKind kind = state.playTile(playerIndex, move.tile, move.side);
    return AppliedMove{playerIndex, move, kind};
}

void MoveExecutor::undo(GameState& state, const AppliedMove& applied) {
    state.undoPlayTile(applied.playerIndex, applied.move.tile, applied.kind);
}

} // namespace isolyn
