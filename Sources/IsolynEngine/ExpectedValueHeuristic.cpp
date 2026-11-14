#include "ExpectedValueHeuristic.hpp"
#include "RulesEngine.hpp"

namespace isolyn {

double ExpectedValueHeuristic::score(const GameState& state, int playerIndex) {
    // RULEBOOK.md R-19: one definition of a hand's worth. Summing raw pips here
    // while scoring used handPoints made the scalar and batch evaluations
    // disagree by exactly ten whenever a hand held only the double blank.
    return -static_cast<double>(RulesEngine::handPoints(state.hand(playerIndex)));
}

} // namespace isolyn
