#pragma once
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

// Whether a specific proposed Move is legal for a specific player against
// a specific GameState. Does no win/close-priority filtering -- see
// docs/design/STRATEGY_NOTES.md for the full reasoning; in short, "may not
// refuse to win/close" restates ordinary Mandatory Play (make some legal
// move if one exists), it does not make a winning/closing move the only
// legal one. A move is legal exactly when the tile is in the player's
// hand, and either the chain is empty (any tile, any side) or the tile
// has a face matching the specified side's currently exposed value.
class MoveValidator {
public:
    static bool isLegal(const GameState& state, int playerIndex, const Move& move);
};

} // namespace isolyn
