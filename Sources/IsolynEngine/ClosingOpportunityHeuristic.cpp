#include "ClosingOpportunityHeuristic.hpp"

namespace isolyn {

double ClosingOpportunityHeuristic::score(const std::vector<int>& roundScores, int playerIndex, int closerPlayerIndex) {
    double value = -static_cast<double>(roundScores[static_cast<std::size_t>(playerIndex)]);
    if (playerIndex == closerPlayerIndex) {
        value += kNextRoundStartBonus;
    }
    return value;
}

} // namespace isolyn
