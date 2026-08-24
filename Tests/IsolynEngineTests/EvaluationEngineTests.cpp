#include "EvaluationEngine.hpp"
#include "MobilityHeuristic.hpp"
#include "BlockingHeuristic.hpp"
#include "ExpectedValueHeuristic.hpp"
#include "ClosingOpportunityHeuristic.hpp"
#include "MoveGenerator.hpp"
#include "TestHarness.hpp"

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("MobilityHeuristic: counts exactly the number of legal moves available");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 5), DominoTile(5, 2), DominoTile(3, 3) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // opens: leftEnd = 5, rightEnd = 6
        // remaining hand: [5-2, 3-3]. 5-2 matches leftEnd(5). 3-3 matches nothing.
        check(MobilityHeuristic::score(state, 0) == 1.0, "exactly one legal move (5-2) is available");
    }

    section("BlockingHeuristic: negative of total opponent mobility");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 5), DominoTile(1, 1) },
            { DominoTile(5, 2), DominoTile(6, 3) }, // both tiles match one end each
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // leftEnd = 5, rightEnd = 6
        check(BlockingHeuristic::score(state, 0) == -2.0, "player 1 has 2 legal moves; blocking score for player 0 is their negation");
    }

    section("ExpectedValueHeuristic: negative of the player's own remaining hand value");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 5), DominoTile(3, 2) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        // 6-5 = 11, 3-2 = 5, total = 16.
        check(ExpectedValueHeuristic::score(state, 0) == -16.0, "hand value 11+5=16, negated");
    }

    section("ClosingOpportunityHeuristic: rewards being the closer, penalizes points charged");
    {
        std::vector<int> roundScores = { 24, 0 };
        double closerScore = ClosingOpportunityHeuristic::score(roundScores, 0, 0); // player 0 IS the closer
        double nonCloserScore = ClosingOpportunityHeuristic::score(roundScores, 1, 0); // player 1 is not
        check(closerScore == -24.0 + ClosingOpportunityHeuristic::kNextRoundStartBonus,
              "player 0 is charged 24 but gets the next-round-start bonus for being the closer");
        check(nonCloserScore == 0.0, "player 1 isn't charged anything and isn't the closer -- exactly 0");
    }

    section("EvaluationEngine: total is the weighted sum of its components (all weights currently 1.0)");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 5), DominoTile(5, 2) }, { DominoTile(1, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // leftEnd=5, rightEnd=6; not closed (5-2 still matches)

        auto breakdown = EvaluationEngine::evaluate(GameMode::OneVsOne, state, 0);
        check(breakdown.closingOpportunity == 0.0, "the position isn't Closed, so closingOpportunity contributes nothing");
        double expectedTotal = breakdown.mobility + breakdown.blocking + breakdown.expectedValue + breakdown.closingOpportunity;
        check(breakdown.total == expectedTotal, "total is exactly the sum of components at the current (all 1.0) weights");
    }

    section("EvaluationEngine: closingOpportunity activates only when the position is genuinely Closed");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 4), DominoTile(2, 2) },
            { DominoTile(4, 4), DominoTile(1, 1) },
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(1, DominoTile(4, 4), GameState::ChainSide::Left); // leftEnd = rightEnd = 4
        state.playTile(0, DominoTile(6, 4), GameState::ChainSide::Left); // leftEnd = 6, rightEnd = 4 -- now Closed

        check(MoveGenerator::isPositionClosed(state), "sanity check: 2-2 and 1-1 match neither end, boneyard is empty");
        auto breakdown = EvaluationEngine::evaluate(GameMode::OneVsOne, state, 0);
        check(breakdown.closingOpportunity != 0.0, "the position is Closed, so closingOpportunity contributes a real value");
    }

    section("EvaluationEngine: 2v2 closingOpportunity correctly combines team hand values");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 4) }, // player 0 (team 0)
            { DominoTile(4, 4) }, // player 1 (team 1) -- opens
            { DominoTile(1, 1) }, // player 2 (team 0)
            { DominoTile(2, 3) }, // player 3 (team 1)
        };
        GameState state(GameMode::TwoVsTwo, hands, {});
        state.playTile(1, DominoTile(4, 4), GameState::ChainSide::Left); // leftEnd = rightEnd = 4
        state.playTile(0, DominoTile(6, 4), GameState::ChainSide::Left); // leftEnd = 6, rightEnd = 4

        check(MoveGenerator::isPositionClosed(state), "sanity check: nobody has a legal move, and 2v2 has no boneyard");

        auto breakdown = EvaluationEngine::evaluate(GameMode::TwoVsTwo, state, 0);
        // Team 0 (players 0,2): hand values 0 + 2 = 2. Team 1 (players 1,3): hand values 0 + 5 = 5.
        // Team 0 has the lower combined value -> gets 0 points; team 1 gets 5.
        // Player 0's team (team 0) also made the closing play -> gets the next-round-start bonus.
        check(breakdown.closingOpportunity == 0.0 + ClosingOpportunityHeuristic::kNextRoundStartBonus,
              "player 0's team is charged 0 points (lower combined hand) and gets the closer bonus");
    }

    if (failureCount() == 0) {
        std::cout << "\nEvaluationEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nEvaluationEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
