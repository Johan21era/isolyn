// Reproducible 15-second depth probe for the two deep tiers. This measures
// completed iterative-deepening depth on opening positions; it is not a
// strength test and does not choose a move for the app.
#include "MatchController.hpp"
#include "ProbabilityEngine.hpp"
#include "RulesEngine.hpp"
#include "SearchEngine.hpp"
#include "Dealer.hpp"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <random>

using namespace isolyn;

int main(int argc, char** argv) {
    const int samples = argc > 1 ? std::atoi(argv[1]) : 80;
    const int positions = argc > 2 ? std::atoi(argv[2]) : 4;
    const int timeMs = argc > 3 ? std::atoi(argv[3]) : 15000;
    if (samples <= 0 || positions <= 0 || timeMs <= 0) {
        std::fprintf(stderr, "usage: %s [samples] [positions] [time-ms]\n", argv[0]);
        return 2;
    }

    for (int position = 1; position <= positions; ++position) {
        // Fixed deal per position, so repeating this command measures the
        // same openings rather than a fresh random deal each time.
        std::vector<std::vector<DominoTile>> hands;
        std::vector<DominoTile> deck;
        std::uint64_t dealSeed = 0xD00D + static_cast<std::uint64_t>(position);
        do {
            std::mt19937_64 dealRng(dealSeed++);
            deck.clear();
            deck.reserve(28);
            for (int i = 0; i < 28; ++i) deck.push_back(DominoTile::fromIndex(i));
            std::shuffle(deck.begin(), deck.end(), dealRng);
            hands = {
                {deck.begin(), deck.begin() + 7},
                {deck.begin() + 7, deck.begin() + 14},
            };
        } while (Dealer::isMisdeal(GameMode::OneVsOne, hands));
        std::vector<DominoTile> boneyard(deck.begin() + 14, deck.end());
        GameState startState(GameMode::OneVsOne, hands, boneyard);
        const auto opening = RulesEngine::determineOpeningPlay(hands);
        startState.playTile(opening.openingPlayerIndex, opening.openingTile,
                            GameState::ChainSide::Left);
        startState.setCurrentPlayerIndex((opening.openingPlayerIndex + 1) % 2);

        auto controller = MatchController(startState);
        if (!controller.currentPlayerHasLegalMove()) controller.resolveForcedDraw();
        const auto state = controller.state();
        const int player = controller.currentPlayerIndex();
        auto belief = ProbabilityEngine::constructFromGameState(state, player);

        SearchEngine::Config config;
        config.maxDepthPlies = samples == 80 ? 24 : 48;
        config.determinizationCount = samples;
        config.workerThreads = 8;
        config.timeLimitMs = timeMs;
        config.endgameTileLimit = 8;
        config.maxVoluntaryDraws = SearchEngine::kUnlimitedVoluntaryDraws;
        config.useSelectiveSearch = true;
        std::mt19937_64 rng(static_cast<std::uint64_t>(samples) * 100000 + static_cast<std::uint64_t>(position));

        const auto start = std::chrono::steady_clock::now();
        auto decision = SearchEngine::chooseBestMove(
            state, belief, GameMode::OneVsOne, config, rng);
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        std::printf("samples %d position %d, %d ms -> depth %d, move %d-%d, draw=%s, nodes %llu, elapsed %lld ms\n",
                    samples, position, timeMs, decision.depthReached,
                    decision.move.tile.low(), decision.move.tile.high(),
                    decision.isDraw ? "true" : "false",
                    static_cast<unsigned long long>(decision.nodesVisited),
                    static_cast<long long>(elapsed));
        std::fflush(stdout);
    }
    return 0;
}