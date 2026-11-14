#include "ClosingOpportunityHeuristic.hpp"

namespace isolyn {

double ClosingOpportunityHeuristic::score(const std::vector<int>& roundScores, int playerIndex, int closerPlayerIndex) {
    // roundScores holds the points this round ADDS to each participant's
    // running total (RULEBOOK.md R-03/R-05: the winner is credited with the
    // loser's hand), so a larger number is better and the sign is positive.
    // It was negated when the array meant "points charged".
    double value = static_cast<double>(roundScores[static_cast<std::size_t>(playerIndex)]);
    if (playerIndex == closerPlayerIndex) {
        value += kNextRoundStartBonus;
    }
    return value;
}

} // namespace isolyn
