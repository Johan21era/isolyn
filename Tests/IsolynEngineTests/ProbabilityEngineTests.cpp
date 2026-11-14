#include "ProbabilityEngine.hpp"
#include "GameState.hpp"
#include "TestHarness.hpp"
#include <cmath>

using namespace isolyn;
using namespace isolyn::test;

namespace {
bool approxEqual(double a, double b, double epsilon = 1e-6) {
    return std::abs(a - b) < epsilon;
}
} // namespace

int main() {
    section("ProbabilityEngine: constructFromGameState correctly splits known vs. tracked tiles");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),      // player 0 (believer): indices 0-6
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 14), // player 1: indices 7-13
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 14, allTiles.end()); // indices 14-27, 14 tiles -- 7+7+14=28
        GameState state(GameMode::OneVsOne, hands, boneyard);
        state.playTile(0, allTiles[0], GameState::ChainSide::Left); // player 0 opens with their first tile

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);

        check(!belief.isTracked(allTiles[1]), "player 0's own remaining hand tile is never tracked -- it's fully known to them");
        check(!belief.isTracked(allTiles[0]), "the played, visible chain tile is also never tracked");
        check(belief.isTracked(allTiles[7]), "an opponent's actual tile, unseen to player 0, is tracked");
        check(belief.isTracked(allTiles[14]), "an undrawn boneyard tile is tracked");

        check(approxEqual(belief.totalProbabilityMass(1), 7.0), "opponent's aggregate mass matches their known hand size (7)");
        check(approxEqual(belief.totalProbabilityMass(BeliefState::kBoneyardLocation), 14.0),
              "boneyard's aggregate mass matches its full remaining size (14), since the locked pair isn't revealed yet");
    }

    section("ProbabilityEngine: a locked pair stays uncertain, never pre-revealed (RULEBOOK R-17)");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),       // player 0 (believer)
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 26),  // player 1 -- the exact split doesn't matter here
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 26, allTiles.end()); // exactly 2 -- both locked, identities hidden. 7+19+2=28.
        GameState state(GameMode::OneVsOne, hands, boneyard);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        check(belief.isTracked(allTiles[26]) && belief.isTracked(allTiles[27]),
              "the locked pair stays uncertain -- the belief holder is never told which tiles are locked");
        check(approxEqual(belief.totalProbabilityMass(BeliefState::kBoneyardLocation), 2.0),
              "the boneyard's uncertain mass is its full remaining size (2), not a pre-revealed zero");
    }

    section("ProbabilityEngine: observePlay correctly resolves a tile and rebalances the rest");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 26), // player 0 (believer): indices 0-25, padded
            { allTiles[26], allTiles[27] },                                    // player 1: the only unseen tiles. 26+2=28.
        };
        GameState state(GameMode::OneVsOne, hands, {}); // no boneyard -- keeps this test isolated to hand-vs-hand tracking
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        check(belief.isTracked(allTiles[26]) && belief.isTracked(allTiles[27]), "both opponent tiles start tracked");
        check(approxEqual(belief.probability(allTiles[26], 1), 1.0), "sanity check: with no boneyard, both unseen tiles start 100% opponent");

        state.playTile(1, allTiles[26], GameState::ChainSide::Left);
        ProbabilityEngine::observePlay(belief, state, 1, allTiles[26]);

        check(!belief.isTracked(allTiles[26]), "the played tile is no longer tracked");
        check(approxEqual(belief.probability(allTiles[27], 1), 1.0),
              "with only one opponent tile left to track and their hand size still 1, all remaining mass concentrates there");
    }

    section("ProbabilityEngine: observeDraw correctly calls through to BeliefState's exact update");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 25), // player 0 (believer): indices 0-24, padded
            {},                                                                 // player 1: starts with nothing
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 25, allTiles.end()); // indices 25-27, 3 tiles. 25+0+3=28.
        GameState state(GameMode::OneVsOne, hands, boneyard);
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        check(approxEqual(belief.probability(allTiles[25], BeliefState::kBoneyardLocation), 1.0), "sanity check on the setup");
        check(approxEqual(belief.totalProbabilityMass(1), 0.0), "player 1 holds nothing yet, so their aggregate mass starts at zero");

        state.drawTile(1); // player 1 draws the one drawable tile (allTiles[25], front of the boneyard)
        ProbabilityEngine::observeDraw(belief, state, 1);

        check(approxEqual(belief.totalProbabilityMass(1), 1.0), "player 1's aggregate mass grows by exactly 1, matching their new hand size");
        check(approxEqual(belief.totalProbabilityMass(BeliefState::kBoneyardLocation), 2.0),
              "boneyard's aggregate mass shrinks by exactly 1 -- exact math already verified directly in BeliefStateTests; this checks the plumbing");
        check(approxEqual(belief.probability(allTiles[25], 1), 1.0 / 3.0), "each of the 3 originally-boneyard tiles shares the new uncertainty equally");
        check(approxEqual(belief.probability(allTiles[26], 1), 1.0 / 3.0), "including the tiles that weren't actually drawn -- the believer can't distinguish them");
    }

    section("ProbabilityEngine: expectedRemainingValue sums probability-weighted tile values");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 26; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 1}, {BeliefState::kBoneyardLocation, 1} };
        BeliefState belief(known, {}, locationCounts);

        DominoTile a = DominoTile::fromIndex(26);
        DominoTile b = DominoTile::fromIndex(27);
        double expected = 0.5 * a.value() + 0.5 * b.value();
        check(approxEqual(ProbabilityEngine::expectedRemainingValue(belief, 1), expected),
              "expected value matches the direct hand calculation for this small, fully-known scenario");
    }

    section("ProbabilityEngine: probabilityHoldsAtLeast matches the hand-verified Poisson-binomial DP");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(5, 0) || t == DominoTile(5, 1)) continue;
            known.push_back(t);
        }
        std::map<int, int> locationCounts = { {1, 1}, {BeliefState::kBoneyardLocation, 1} };
        BeliefState belief(known, {}, locationCounts);

        check(approxEqual(belief.probability(DominoTile(5, 0), 1), 0.5), "sanity check on the setup");

        check(approxEqual(ProbabilityEngine::probabilityHoldsAtLeast(belief, 1, 5, 0), 1.0), "at least 0 is always certain");
        check(approxEqual(ProbabilityEngine::probabilityHoldsAtLeast(belief, 1, 5, 1), 0.75), "P(>=1) = P(1)+P(2) = 0.5+0.25 = 0.75");
        check(approxEqual(ProbabilityEngine::probabilityHoldsAtLeast(belief, 1, 5, 2), 0.25), "P(>=2) = P(2) = 0.25, matching the DP exactly");
    }

    if (failureCount() == 0) {
        std::cout << "\nProbabilityEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nProbabilityEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
