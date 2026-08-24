#include "SearchEngine.hpp"
#include "ProbabilityEngine.hpp"
#include "TestHarness.hpp"
#include <deque>
#include <random>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("SearchEngine: correctly looks ahead to avoid handing the opponent an immediate Domino win");
    {
        // Chain opens with 4-4 (double, both ends show 4). Player 0
        // holds 4-6 and 4-1; player 1 holds only 6-6.
        //
        // Playing 4-6 first changes the touched end to 6 -- which
        // immediately hands player 1's 6-6 a legal move, and since it's
        // their only tile, an immediate Domino win for THEM.
        //
        // Playing 4-1 first changes the touched end to 1 instead -- 6-6
        // still matches nothing, player 1 is stuck with no boneyard to
        // draw from, and player 0's remaining 4-6 still matches the
        // untouched end (4), winning by Domino themselves next turn.
        //
        // A search with enough depth to see player 1's reply must prefer
        // 4-1 over 4-6.
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(4, 6) || t == DominoTile(4, 1) || t == DominoTile(6, 6)) continue;
            padding.push_back(t); // 25 tiles, naturally including 4-4 as the "opener"
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 4, 4);

        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(4, 6), DominoTile(4, 1) }, // player 0 -- the choice under test
            { DominoTile(6, 6) },                     // player 1 -- their only remaining tile
        };
        // 2 (player0) + 1 (player1) + 25 (chain) + 0 (boneyard) = 28.
        GameState state(GameMode::OneVsOne, hands, {}, chain, { PlayRecord{1, DominoTile(4, 4)} }, 0);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(2024);
        SearchEngine::Config config;
        config.maxDepthPlies = 4;
        config.determinizationCount = 1; // nothing is actually uncertain here -- only 6-6 is tracked, and locationCounts forces it to player 1 with certainty
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng);

        check(decision.move.tile == DominoTile(4, 1),
              "the search correctly avoids 4-6 (hands player 1 an immediate Domino win) and finds 4-1 instead");
    }

    section("SearchEngine: with only one legal candidate, it's chosen trivially and correctly evaluated");
    {
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(5, 5) || t == DominoTile(1, 1)) continue;
            padding.push_back(t); // 26 tiles, naturally including 5-2 as the "opener"
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 2, 5); // as if opened with 5-2: leftEnd=2, rightEnd=5

        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(5, 5) }, // player 0's only tile -- will Domino
            { DominoTile(1, 1) },
        };
        // 1 + 1 + 26 + 0 = 28.
        GameState state(GameMode::OneVsOne, hands, {}, chain, { PlayRecord{1, DominoTile(5, 2)} }, 0);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(1);
        SearchEngine::Config config;
        config.maxDepthPlies = 2;
        config.determinizationCount = 1;
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng);

        check(decision.move.tile == DominoTile(5, 5), "the only legal move is correctly identified and chosen");
        check(decision.expectedValuePerPlayer[0] == 0.0,
              "player 0's evaluation reflects an immediate Domino win -- an empty hand scores 0, the best possible ExpectedValueHeuristic outcome");
    }

    if (failureCount() == 0) {
        std::cout << "\nSearchEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nSearchEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
