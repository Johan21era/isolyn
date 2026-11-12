#include "EvaluationEngine.hpp"
#include "DominoSet.hpp"
#include "Dealer.hpp"
#include "MobilityHeuristic.hpp"
#include "BlockingHeuristic.hpp"
#include "ExpectedValueHeuristic.hpp"
#include "ClosingOpportunityHeuristic.hpp"
#include "MoveGenerator.hpp"
#include "TestHarness.hpp"
#include <algorithm>
#include <cmath>
#include <random>
#include <utility>

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

    section("EvaluationEngine: total is the weighted sum of every component");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 5), DominoTile(5, 2) }, { DominoTile(1, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // leftEnd=5, rightEnd=6; not closed (5-2 still matches)

        auto breakdown = EvaluationEngine::evaluate(GameMode::OneVsOne, state, 0);
        check(breakdown.closingOpportunity == 0.0, "the position isn't Closed, so closingOpportunity contributes nothing");
        EvaluationWeights weights;
        double expectedTotal =
            weights.mobility * breakdown.mobility
            + weights.blocking * breakdown.blocking
            + weights.expectedValue * breakdown.expectedValue
            + weights.closingOpportunity * breakdown.closingOpportunity
            + weights.winThreat * breakdown.winThreat
            + weights.pipControl * breakdown.pipControl
            + weights.tempo * breakdown.tempo
            + weights.teamSupport * breakdown.teamSupport;
        check(breakdown.total == expectedTotal, "total is exactly the configured weighted sum of all eight components");
    }

    section("EvaluationEngine: a finished Domino round never rewards the loser's win threat");
    {
        std::vector<std::vector<DominoTile>> hands = { {}, { DominoTile(4, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});

        auto loser = EvaluationEngine::evaluate(GameMode::OneVsOne, state, 1);
        check(loser.winThreat == 0.0, "a non-winner gets no immediate-win bonus after the round is already over");
        check(loser.expectedValue == -5.0, "the non-winner's remaining five pips are charged directly");
        check(loser.total < 0.0, "the finished loss evaluates as a loss, not as a pending win");
    }

    section("EvaluationEngine: immediate Domino threat is the dominant signal");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(5, 5) },
            { DominoTile(5, 2), DominoTile(1, 1) },
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(1, DominoTile(5, 2), GameState::ChainSide::Left); // ends 5 and 2; player 0 has 5-5

        auto breakdown = EvaluationEngine::evaluate(GameMode::OneVsOne, state, 0);
        check(breakdown.winThreat >= 1000.0, "a one-tile hand with a legal finish is scored as an immediate win threat");
        check(breakdown.pipControl >= 0.5, "the winning tile is also counted as control of the exposed 5 end");
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
            { DominoTile(6, 4), DominoTile(0, 0) }, // player 0 (team 0)
            { DominoTile(4, 4), DominoTile(1, 1) }, // player 1 (team 1) -- opens
            { DominoTile(1, 1) }, // player 2 (team 0)
            { DominoTile(2, 3) }, // player 3 (team 1)
        };
        GameState state(GameMode::TwoVsTwo, hands, {});
        state.playTile(1, DominoTile(4, 4), GameState::ChainSide::Left); // leftEnd = rightEnd = 4
        state.playTile(0, DominoTile(6, 4), GameState::ChainSide::Left); // leftEnd = 6, rightEnd = 4

        check(MoveGenerator::isPositionClosed(state), "sanity check: nobody has a legal move, and 2v2 has no boneyard");

        auto breakdown = EvaluationEngine::evaluate(GameMode::TwoVsTwo, state, 0);
        // Team 0 (players 0,2): hand values 0 + 2 = 2. Team 1 (players 1,3): hand values 2 + 5 = 7.
        // Team 0 has the lower combined value -> gets 0 points; team 1 is charged 7.
        // Player 0's team (team 0) also made the closing play -> gets the next-round-start bonus.
        check(breakdown.closingOpportunity == 0.0 + ClosingOpportunityHeuristic::kNextRoundStartBonus,
              "player 0's team is charged 0 points (lower combined hand) and gets the closer bonus");
    }

    section("EvaluationEngine: batch totals match per-player evaluation across modes and edge states");
    {
        std::vector<std::pair<std::string, GameState>> fixtures;
        fixtures.emplace_back("1v1", GameState(
            GameMode::OneVsOne,
            { { DominoTile(6, 5), DominoTile(5, 2) }, { DominoTile(1, 1), DominoTile(3, 2) } },
            {}));
        fixtures.emplace_back("1v1v1", GameState(
            GameMode::OneVsOneVsOne,
            { { DominoTile(6, 5), DominoTile(5, 2) },
              { DominoTile(1, 1), DominoTile(3, 2) },
              { DominoTile(6, 4), DominoTile(2, 2) } },
            {}));
        fixtures.emplace_back("2v2", GameState(
            GameMode::TwoVsTwo,
            { { DominoTile(6, 5), DominoTile(5, 2) },
              { DominoTile(1, 1), DominoTile(3, 2) },
              { DominoTile(6, 4), DominoTile(2, 2) },
              { DominoTile(5, 3), DominoTile(0, 0) } },
            {}));
        fixtures.emplace_back("terminal", GameState(
            GameMode::OneVsOne, { {}, { DominoTile(4, 1) } }, {}));
        fixtures.emplace_back("empty chain", GameState(
            GameMode::OneVsOne,
            { { DominoTile(6, 5) }, { DominoTile(5, 2) } }, {}));

        GameState threatState(
            GameMode::OneVsOne,
            { { DominoTile(5, 5) }, { DominoTile(5, 2), DominoTile(1, 1) } }, {});
        threatState.playTile(1, DominoTile(5, 2), GameState::ChainSide::Left);
        fixtures.emplace_back("immediate threat", std::move(threatState));

        GameState closed2v2(
            GameMode::TwoVsTwo,
            { { DominoTile(6, 4), DominoTile(0, 0) },
              { DominoTile(4, 4), DominoTile(1, 1) },
              { DominoTile(1, 1) },
              { DominoTile(2, 3) } }, {});
        closed2v2.playTile(1, DominoTile(4, 4), GameState::ChainSide::Left);
        closed2v2.playTile(0, DominoTile(6, 4), GameState::ChainSide::Left);
        fixtures.emplace_back("2v2 closed", std::move(closed2v2));

        fixtures.emplace_back("2v2 terminal", GameState(
            GameMode::TwoVsTwo,
            { {}, { DominoTile(4, 1) }, { DominoTile(2, 2) }, { DominoTile(3, 3) } },
            {}));

        for (auto& [label, state] : fixtures) {
            const EvaluationTotals batch = EvaluationEngine::evaluateAll(
                state.mode(), state);
            check(batch.playerCount == state.playerCount(),
                  label + " batch count matches player count");
            for (int p = 0; p < state.playerCount(); ++p) {
                const double individual =
                    EvaluationEngine::evaluate(state.mode(), state, p).total;
                check(std::fabs(batch.totals[static_cast<std::size_t>(p)] - individual) <= 1e-9,
                      label + " batch total matches player " + std::to_string(p));
            }
        }
    }

    section("EvaluationEngine: randomized legal positions preserve batch/scalar parity");
    {
        std::mt19937_64 rng(0x1501C0DEULL);
        const EvaluationWeights customWeights{
            0.37, -1.10, 2.30, 0.70, 1.70, -0.40, 3.10, -0.90};

        auto makePosition = [&](GameMode mode) {
            const int players = Dealer::playerCountForMode(mode);
            const auto& allTiles = DominoSet::allTiles();
            std::vector<DominoTile> pool(allTiles.begin(), allTiles.end());
            std::shuffle(pool.begin(), pool.end(), rng);

            std::vector<std::vector<DominoTile>> hands(
                static_cast<std::size_t>(players));
            constexpr int kHandSize = 7;
            auto cursor = pool.begin();
            for (auto& hand : hands) {
                hand.assign(cursor, cursor + kHandSize);
                cursor += kHandSize;
            }
            std::vector<DominoTile> boneyard(cursor, pool.end());

            GameState state(mode, std::move(hands), std::move(boneyard));
            state.setCurrentPlayerIndex(static_cast<int>(rng() % players));
            const int steps = 6 + static_cast<int>(rng() % 10);
            for (int step = 0; step < steps; ++step) {
                const int player = state.currentPlayerIndex();
                const auto moves = MoveGenerator::generate(state, player);
                if (!moves.empty()) {
                    const Move& move = moves[rng() % moves.size()];
                    state.playTile(player, move.tile, move.side);
                }
                state.setCurrentPlayerIndex((player + 1) % players);
            }
            return state;
        };

        for (GameMode mode : {GameMode::OneVsOne, GameMode::OneVsOneVsOne,
                              GameMode::TwoVsTwo}) {
            int mismatches = 0;
            int countMismatches = 0;
            double maxDelta = 0.0;
            constexpr int kTrials = 250;
            for (int trial = 0; trial < kTrials; ++trial) {
                const GameState state = makePosition(mode);
                const EvaluationWeights& weights =
                    (trial % 5 == 0) ? customWeights : EvaluationWeights{};
                const EvaluationTotals batch =
                    EvaluationEngine::evaluateAll(mode, state, weights);
                if (batch.playerCount != state.playerCount()) ++countMismatches;
                for (int p = 0; p < state.playerCount(); ++p) {
                    const double scalar =
                        EvaluationEngine::evaluate(mode, state, p, weights).total;
                    const double delta =
                        std::fabs(batch.totals[static_cast<std::size_t>(p)] - scalar);
                    maxDelta = std::max(maxDelta, delta);
                    if (delta > 1e-9) ++mismatches;
                }
            }
            check(countMismatches == 0,
                  "randomized batch player counts match for mode " +
                      std::to_string(static_cast<int>(mode)));
            check(mismatches == 0,
                  "randomized batch totals match scalar for 250 positions, mode " +
                      std::to_string(static_cast<int>(mode)) +
                      " (max delta " + std::to_string(maxDelta) + ")");
            check(maxDelta <= 1e-9,
                  "randomized maximum numerical delta stays below 1e-9, mode " +
                      std::to_string(static_cast<int>(mode)));
        }
    }

    if (failureCount() == 0) {
        std::cout << "\nEvaluationEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nEvaluationEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
