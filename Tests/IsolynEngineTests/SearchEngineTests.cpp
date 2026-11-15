#include "SearchEngine.hpp"
#include "ProbabilityEngine.hpp"
#include "MoveValidator.hpp"
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

    section("SearchEngine: iterative deepening reports a completed depth and exact-endgame use");
    {
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(5, 5) || t == DominoTile(2, 2) ||
                t == DominoTile(1, 1)) continue;
            padding.push_back(t);
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 2, 5);

        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(5, 5), DominoTile(2, 2) },
            { DominoTile(1, 1) },
        };
        GameState state(GameMode::OneVsOne, hands, {}, chain,
                        { PlayRecord{1, DominoTile(2, 5)} }, 0);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(99);
        SearchEngine::Config config;
        config.maxDepthPlies = 3;
        config.determinizationCount = 2;
        config.endgameTileLimit = 8;
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng);

        check(decision.depthReached == 3, "iterative deepening completes the configured depth");
        check(decision.samplesCompleted == 2, "every requested determinization sample is counted");
        check(decision.completed, "the decision is marked complete when both samples finish");
        check(decision.exactEndgame, "the empty-boneyard late endgame is solved exactly");
        check(decision.nodesVisited > 0, "search diagnostics record visited nodes");
    }

    section("SearchEngine: voluntary drawing stays out of the tree by default and is a legal action when enabled");
    {
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(4, 6) || t == DominoTile(4, 1) || t == DominoTile(6, 6) ||
                t == DominoTile(0, 0) || t == DominoTile(5, 5))
                continue;
            padding.push_back(t); // 23 tiles + 3 in hands + 2 in the boneyard = 28
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 4, 4);
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(4, 6), DominoTile(4, 1) },
            { DominoTile(6, 6) },
        };
        std::vector<DominoTile> boneyard = { DominoTile(0, 0), DominoTile(5, 5) };
        GameState state(GameMode::OneVsOne, hands, boneyard, chain,
                        { PlayRecord{1, DominoTile(4, 4)} }, 0);

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(77);

        SearchEngine::Config shipped;
        check(shipped.maxVoluntaryDraws == 0,
              "the shipped default keeps voluntary draws out of the game tree");

        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, shipped, rng);
        check(!decision.isDraw, "a move-only configuration never reports a draw");

        SearchEngine::Config withDraws = shipped;
        withDraws.maxVoluntaryDraws = 1;
        auto drawDecision =
            SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, withDraws, rng);
        const bool legalAction = drawDecision.isDraw
                                     ? state.boneyard().drawableCount() > 0
                                     : MoveValidator::isLegal(state, 0, drawDecision.move);
        check(legalAction,
              "with draws enabled the engine returns either a legal placement or a legal draw");
        // The decision still reports a Move even when the action is a draw: the
        // bridge forwards it as a placeholder and the DTO contract promises it
        // is genuinely legal. The draw index sits one past the end of the
        // candidate list, so this is exactly where an out-of-bounds read hid.
        check(MoveValidator::isLegal(state, 0, drawDecision.move),
              "a draw decision still reports a genuinely legal placeholder move");

        // R-15's live action space is unbounded; the search evaluates one draw
        // at the current decision and re-searches after it, so this bound is a
        // guard for callers that choose to widen the root decision, not a claim
        // that every draw chain is searched in one tree.
        check(SearchEngine::kUnlimitedVoluntaryDraws >= DominoTile::kTileCount,
              "the analysis draw bound covers the whole double-six set");
        SearchEngine::Config unlimitedDraws = shipped;
        unlimitedDraws.maxVoluntaryDraws = SearchEngine::kUnlimitedVoluntaryDraws;
        auto unlimitedDecision =
            SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, unlimitedDraws, rng);
        check(unlimitedDecision.isDraw ||
                  MoveValidator::isLegal(state, 0, unlimitedDecision.move),
              "unlimited-draw analysis still returns a legal action");

        // The deep tiers use PVS/LMR. Keep the default full-width path as the
        // baseline and prove the selective variant still returns a legal action.
        SearchEngine::Config selective = shipped;
        selective.maxDepthPlies = 6;
        selective.determinizationCount = 2;
        selective.useSelectiveSearch = true;
        check(!shipped.useSelectiveSearch,
              "selective search is off by default; the full-width path is the baseline");
        auto selectiveDecision =
            SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, selective, rng);
        check(selectiveDecision.depthReached > 0,
              "selective deep search completes at least one iterative-deepening depth");
        check(selectiveDecision.isDraw ||
                  MoveValidator::isLegal(state, 0, selectiveDecision.move),
              "selective deep search still returns a legal action");
    }

    section("SearchEngine: the opener is never offered a draw -- it must lead with a tile");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(0, 1), DominoTile(2, 3) },
                                                       { DominoTile(1, 2), DominoTile(4, 5) } };
        std::vector<DominoTile> boneyard;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            const bool dealt = t == DominoTile(0, 1) || t == DominoTile(2, 3) ||
                               t == DominoTile(1, 2) || t == DominoTile(4, 5);
            if (!dealt) boneyard.push_back(t); // all 24 remaining tiles stay unseen
        }
        GameState state(GameMode::OneVsOne, hands, boneyard);
        check(state.chain().isEmpty(), "a round with no mandated opener starts on an empty chain");

        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(99);
        SearchEngine::Config config;
        config.maxDepthPlies = 2;
        config.determinizationCount = 1;
        config.maxVoluntaryDraws = 1; // exactly how the bridge runs analysis
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng);
        check(!decision.isDraw, "draws are enabled but the opener must lead, so no draw is chosen");
        check(MoveValidator::isLegal(state, 0, decision.move),
              "the opener's reported move is a legal lead");
    }

    section("SearchEngine: a reused transposition table is invalidated between searches");
    {
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(4, 6) || t == DominoTile(4, 1) ||
                t == DominoTile(6, 6) || t == DominoTile(0, 0) ||
                t == DominoTile(5, 5)) continue;
            padding.push_back(t);
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 4, 4);
        GameState state(GameMode::OneVsOne,
                        { { DominoTile(4, 6), DominoTile(4, 1) },
                          { DominoTile(6, 6) } },
                        { DominoTile(0, 0), DominoTile(5, 5) }, chain,
                        { PlayRecord{1, DominoTile(4, 4)} }, 0);
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);

        SearchEngine::Config config;
        config.maxDepthPlies = 4;
        config.determinizationCount = 8;
        std::mt19937_64 firstRng(1234);
        std::mt19937_64 secondRng(1234);
        const auto first =
            SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, firstRng);
        const auto second =
            SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, secondRng);

        check(second.move.tile == first.move.tile && second.move.side == first.move.side,
              "a repeated search on the same thread chooses the same move");
        check(second.depthReached == first.depthReached,
              "a repeated search reaches the same depth");
        check(second.nodesVisited == first.nodesVisited &&
              second.transpositionHits == first.transpositionHits,
              "stale transposition entries do not change the second search's work");
        check(second.expectedValuePerPlayer == first.expectedValuePerPlayer,
              "stale transposition entries do not change the reported values");
    }

    if (failureCount() == 0) {
        std::cout << "\nSearchEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nSearchEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
