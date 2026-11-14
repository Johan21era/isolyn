#include "Determinizer.hpp"
#include "StableRandom.hpp"
#include <algorithm>
#include <cassert>

namespace isolyn {

std::vector<std::pair<DominoTile, int>> Determinizer::sample(const BeliefState& belief,
                                                               const std::map<int, int>& locationCounts,
                                                               std::mt19937_64& rng) {
    std::vector<DominoTile> remaining;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        DominoTile tile = DominoTile::fromIndex(i);
        if (belief.isTracked(tile)) remaining.push_back(tile);
    }

    std::vector<int> locations;
    for (const auto& [location, count] : locationCounts) locations.push_back(location);
    stable_random::shuffle(locations, rng);

    std::vector<std::pair<DominoTile, int>> assignment;

    for (std::size_t li = 0; li + 1 < locations.size(); ++li) {
        int location = locations[li];
        int capacity = locationCounts.at(location);

        for (int k = 0; k < capacity; ++k) {
            assert(!remaining.empty() &&
                   "ran out of tiles before every location's capacity was filled -- locationCounts inconsistent with belief's tracked tiles");

            double totalWeight = 0.0;
            for (const auto& tile : remaining) totalWeight += belief.probability(tile, location);

            std::size_t chosenIndex = 0;
            if (totalWeight <= 0.0) {
                chosenIndex = static_cast<std::size_t>(
                    stable_random::uniformIndexBelow(rng, remaining.size()));
            } else {
                const double r = stable_random::unitInterval(rng) * totalWeight;
                double cumulative = 0.0;
                for (std::size_t i = 0; i < remaining.size(); ++i) {
                    cumulative += belief.probability(remaining[i], location);
                    if (r <= cumulative) {
                        chosenIndex = i;
                        break;
                    }
                }
            }

            assignment.push_back({remaining[chosenIndex], location});
            remaining.erase(remaining.begin() + static_cast<long>(chosenIndex));
        }
    }

    if (!locations.empty()) {
        int lastLocation = locations.back();
        for (const auto& tile : remaining) {
            assignment.push_back({tile, lastLocation});
        }
    }

    return assignment;
}

} // namespace isolyn
