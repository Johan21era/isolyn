#pragma once
#include "GameState.hpp"

namespace isolyn {

// The number of currently-legal moves playerIndex has, given the current
// chain. More options is generally better -- flexibility to adapt rather
// than being forced into a single, possibly bad, play. Deliberately a
// raw count, not normalized against hand size -- normalization/weighting
// against the other heuristic components is EvaluationEngine's job, not
// this class's.
class MobilityHeuristic {
public:
    static double score(const GameState& state, int playerIndex);
};

} // namespace isolyn
