#include "SimulationEngine.hpp"
#include "ProbabilityEngine.hpp"
#include "TestHarness.hpp"
#include <algorithm>
#include <random>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("SimulationEngine: the determinized world exactly preserves everything the believer actually knows");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 14),
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 14, allTiles.end());
        GameState real(GameMode::OneVsOne, hands, boneyard);
        real.playTile(0, allTiles[0], GameState::ChainSide::Left);
        real.setCurrentPlayerIndex(1);

        BeliefState belief = ProbabilityEngine::constructFromGameState(real, 0);
        std::mt19937_64 rng(123);
        GameState world = SimulationEngine::sampleDeterminizedState(real, belief, 0, rng);

        check(world.mode() == real.mode(), "mode is preserved exactly");
        check(world.currentPlayerIndex() == real.currentPlayerIndex(), "whose turn it is is preserved exactly");
        check(world.hand(0).size() == real.hand(0).size(), "the believer's own hand size is preserved exactly");

        auto byIndex = [](DominoTile a, DominoTile b) { return a.index() < b.index(); };
        std::vector<DominoTile> realHand0Sorted(real.hand(0).begin(), real.hand(0).end());
        std::vector<DominoTile> worldHand0Sorted(world.hand(0).begin(), world.hand(0).end());
        std::sort(realHand0Sorted.begin(), realHand0Sorted.end(), byIndex);
        std::sort(worldHand0Sorted.begin(), worldHand0Sorted.end(), byIndex);
        check(realHand0Sorted == worldHand0Sorted, "the believer's own hand contents are exactly preserved");

        check(world.chain().orderedTiles() == real.chain().orderedTiles(), "the chain is exactly preserved");
        check(world.chain().leftEnd() == real.chain().leftEnd() && world.chain().rightEnd() == real.chain().rightEnd(),
              "the chain's exposed ends are exactly preserved");
        check(world.playHistory().size() == real.playHistory().size(), "play history is exactly preserved");
        check(world.hand(1).size() == real.hand(1).size(), "the opponent's hand SIZE is preserved, even though its contents are hypothetical");
    }

    section("SimulationEngine: the locked pair stays uncertain to the belief holder (RULEBOOK R-17)");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 26),
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 26, allTiles.end());
        GameState real(GameMode::OneVsOne, hands, boneyard);

        BeliefState belief = ProbabilityEngine::constructFromGameState(real, 0);
        std::mt19937_64 rng(456);
        GameState world = SimulationEngine::sampleDeterminizedState(real, belief, 0, rng);

        auto realLocked = real.boneyard().lockedTiles();
        check(realLocked.size() == 2, "the real boneyard has a locked pair to hide");
        check(belief.isTracked(realLocked[0]) && belief.isTracked(realLocked[1]),
              "R-17: neither locked tile is treated as known or pre-revealed");
        check(world.boneyard().size() == 2,
              "the sampled world still has exactly the right boneyard size");
        check(world.hand(1).size() == real.hand(1).size(),
              "the sampled opponent hand keeps its real size");
    }

    section("SimulationEngine: an empty chain is handled correctly, without touching leftEnd/rightEnd on it");
    {
        std::vector<DominoTile> allTiles;
        for (int i = 0; i < DominoTile::kTileCount; ++i) allTiles.push_back(DominoTile::fromIndex(i));

        std::vector<std::vector<DominoTile>> hands = {
            std::vector<DominoTile>(allTiles.begin(), allTiles.begin() + 7),
            std::vector<DominoTile>(allTiles.begin() + 7, allTiles.begin() + 14),
        };
        std::vector<DominoTile> boneyard(allTiles.begin() + 14, allTiles.end());
        GameState real(GameMode::OneVsOne, hands, boneyard); // no plays yet -- chain is empty

        BeliefState belief = ProbabilityEngine::constructFromGameState(real, 0);
        std::mt19937_64 rng(789);
        GameState world = SimulationEngine::sampleDeterminizedState(real, belief, 0, rng);

        check(world.chain().isEmpty(), "an empty real chain correctly produces an empty determinized chain, not a crash");
    }

    if (failureCount() == 0) {
        std::cout << "\nSimulationEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nSimulationEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
