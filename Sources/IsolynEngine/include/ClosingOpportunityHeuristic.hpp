#pragma once
#include <vector>

namespace isolyn {

// Scores how favorable an already-Closed position is for `playerIndex`,
// given the round scores it would produce (RulesEngine::computeRoundScores,
// indexed the same way) and who is credited as the closer
// (RulesEngine::determineCloser). Two components: the points
// `playerIndex` would add to his running total this round (more is
// better), plus a fixed bonus if `playerIndex` is the closer, since the
// closer always starts the next round regardless of the scoring outcome
// (Rules Spec Sec. 4) -- exactly the tradeoff docs/design/STRATEGY_NOTES.md
// documents: a player may accept a worse points outcome specifically
// because starting the next round is worth it.
//
// Only meaningful for an already-closed position -- scoring a position
// that isn't Closed is EvaluationEngine's responsibility to gate, not
// this class's to detect.
class ClosingOpportunityHeuristic {
public:
    // Placeholder weight, not a calibrated constant -- DifficultyModel
    // and real search-driven tuning (Phase 7) are what eventually
    // calibrate this against actual search outcomes, not a number picked
    // here in advance of any evidence.
    static constexpr double kNextRoundStartBonus = 5.0;

    static double score(const std::vector<int>& roundScores, int playerIndex, int closerPlayerIndex);
};

} // namespace isolyn
