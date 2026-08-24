#pragma once
#include "GameState.hpp"

namespace isolyn {

// How much playerIndex's opponents are restricted: the total legal moves
// available to every OTHER player, negated (fewer opponent options is
// better for playerIndex -- "opponent restriction" from the evaluation
// framework's own component list). Sums across all other players rather
// than picking a single "the opponent", so this is meaningful in 1v1v1
// and 2v2 too, not just 1v1.
class BlockingHeuristic {
public:
    static double score(const GameState& state, int playerIndex);
};

} // namespace isolyn
