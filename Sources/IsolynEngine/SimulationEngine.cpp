#include "SimulationEngine.hpp"
#include "Determinizer.hpp"
#include "StableRandom.hpp"
#include <algorithm>

namespace isolyn {

GameState SimulationEngine::sampleDeterminizedState(const GameState& realState, const BeliefState& belief,
                                                     int believerIndex, std::mt19937_64& rng) {
    std::map<int, int> locationCounts;
    for (int p = 0; p < realState.playerCount(); ++p) {
        if (p == believerIndex) continue;
        locationCounts[p] = static_cast<int>(realState.hand(p).size());
    }
    // The full boneyard size includes the two locked tiles. Their identity
    // is hidden (R-17), so the sampled world may place any unseen
    // identities in those two slots -- the correct information set.
    locationCounts[BeliefState::kBoneyardLocation] = static_cast<int>(realState.boneyard().size());

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
    stable_random::shuffle(sampledBoneyardTiles, rng);

    // Do not append the real locked pair: that would reveal its identity to
    // the search. The sampled boneyard already has the full boneyard size;
    // its final two tiles become this world's (equally valid) locked pair.
    std::vector<DominoTile> boneyardTiles = sampledBoneyardTiles;

    // IMPORTANT: realState.chain().leftEnd()/rightEnd() assert-fail if
    // the chain is empty -- must guard this, cannot call
    // Chain::fromKnownState unconditionally.
    Chain chainCopy = realState.chain().isEmpty()
        ? Chain()
        : Chain::fromKnownState(realState.chain().orderedTiles(), realState.chain().leftEnd(), realState.chain().rightEnd());

    return GameState(realState.mode(), hands, boneyardTiles, chainCopy, realState.playHistory(), realState.currentPlayerIndex());
}

} // namespace isolyn
