#pragma once
#include "GameState.hpp"

namespace isolyn {

// A general "how much value is at risk in my hand right now" signal: the
// negative of playerIndex's current remaining hand value. Lower
// remaining value is better regardless of whether the round has actually
// ended -- this heuristic says something meaningful without needing a
// Close or a Domino, unlike ClosingOpportunityHeuristic, which
// specifically scores already-closed positions.
class ExpectedValueHeuristic {
public:
    static double score(const GameState& state, int playerIndex);
};

} // namespace isolyn
