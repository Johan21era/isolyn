#include "SimulationEngine.hpp"
#include "Determinizer.hpp"
#include <algorithm>

namespace isolyn {

GameState SimulationEngine::sampleDeterminizedState(const GameState& realState, const BeliefState& belief,
                                                     int believerIndex, std::mt19937_64& rng) {
    std::map<int, int> locationCounts;
    for (int p = 0; p < realState.playerCount(); ++p) {
        if (p == believerIndex) continue;
        locationCounts[p] = static_cast<int>(realState.hand(p).size());
    }
    auto realLocked = realState.boneyard().lockedTiles();
    locationCounts[BeliefState::kBoneyardLocation] = realLocked.empty()
        ? static_cast<int>(realState.boneyard().size())
        : 0;

    auto assignment = Determinizer::sample(belief, locationCounts, rng);

    std::vector<std::vector<DominoTile>> hands(static_cast<std::size_t>(realState.playerCount()));
    hands[static_cast<std::size_t>(believerIndex)] =
        std::vector<DominoTile>(realState.hand(believerIndex).begin(), realState.hand(believerIndex).end());

    std::vector<DominoTile> sampledBoneyardTiles;
    for (const auto& [tile, location] : assignment) {
        if (location == BeliefState::kBoneyardLocation) {
            sampledBoneyardTiles.push_back(tile);
        } else {
            hands[static_cast<std::size_t>(location)].push_back(tile);
        }
    }
    std::shuffle(sampledBoneyardTiles.begin(), sampledBoneyardTiles.end(), rng);

    std::vector<DominoTile> boneyardTiles = sampledBoneyardTiles;
    for (const auto& tile : realLocked) boneyardTiles.push_back(tile);

    // IMPORTANT: realState.chain().leftEnd()/rightEnd() assert-fail if
    // the chain is empty -- must guard this, cannot call
    // Chain::fromKnownState unconditionally.
    Chain chainCopy = realState.chain().isEmpty()
        ? Chain()
        : Chain::fromKnownState(realState.chain().orderedTiles(), realState.chain().leftEnd(), realState.chain().rightEnd());

    return GameState(realState.mode(), hands, boneyardTiles, chainCopy, realState.playHistory(), realState.currentPlayerIndex());
}

} // namespace isolyn
