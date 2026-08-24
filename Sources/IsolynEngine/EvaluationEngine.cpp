#include "EvaluationEngine.hpp"
#include "BlockingHeuristic.hpp"
#include "ClosingOpportunityHeuristic.hpp"
#include "ExpectedValueHeuristic.hpp"
#include "MobilityHeuristic.hpp"
#include "MoveGenerator.hpp"
#include "RulesEngine.hpp"

namespace isolyn {

namespace {
int handValueOf(const GameState& state, int playerIndex) {
    int total = 0;
    for (const auto& tile : state.hand(playerIndex)) {
        total += tile.value();
    }
    return total;
}
} // namespace

EvaluationBreakdown EvaluationEngine::evaluate(GameMode mode, const GameState& state, int playerIndex) {
    EvaluationBreakdown breakdown{};
    breakdown.mobility = MobilityHeuristic::score(state, playerIndex);
    breakdown.blocking = BlockingHeuristic::score(state, playerIndex);
    breakdown.expectedValue = ExpectedValueHeuristic::score(state, playerIndex);
    breakdown.closingOpportunity = 0.0;

    if (MoveGenerator::isPositionClosed(state)) {
        std::vector<int> participantValues;
        int evaluatedParticipantIndex = playerIndex;
        int closerParticipantIndex;
        int closerPlayer = RulesEngine::determineCloser(mode, state.playHistory());

        if (mode == GameMode::TwoVsTwo) {
            auto team0 = RulesEngine::playersOnTeam(0);
            auto team1 = RulesEngine::playersOnTeam(1);
            int team0Value = RulesEngine::combineTeamValue(handValueOf(state, team0.first), handValueOf(state, team0.second));
            int team1Value = RulesEngine::combineTeamValue(handValueOf(state, team1.first), handValueOf(state, team1.second));
            participantValues = { team0Value, team1Value };
            evaluatedParticipantIndex = RulesEngine::teamIndexForPlayer(playerIndex);
            closerParticipantIndex = RulesEngine::teamIndexForPlayer(closerPlayer);
        } else {
            for (int p = 0; p < state.playerCount(); ++p) {
                participantValues.push_back(handValueOf(state, p));
            }
            closerParticipantIndex = closerPlayer;
        }

        auto roundScores = RulesEngine::computeRoundScores(participantValues);
        breakdown.closingOpportunity =
            ClosingOpportunityHeuristic::score(roundScores, evaluatedParticipantIndex, closerParticipantIndex);
    }

    breakdown.total = EvaluationEngine::kMobilityWeight * breakdown.mobility
                     + EvaluationEngine::kBlockingWeight * breakdown.blocking
                     + EvaluationEngine::kExpectedValueWeight * breakdown.expectedValue
                     + EvaluationEngine::kClosingOpportunityWeight * breakdown.closingOpportunity;
    return breakdown;
}

} // namespace isolyn
