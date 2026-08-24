#include "Determinizer.hpp"
#include "TestHarness.hpp"
#include <map>
#include <random>
#include <string>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("Determinizer: every sample respects exact location capacities");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 21; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 3}, {2, 2}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(known, {}, locationCounts);

        std::mt19937_64 rng(42);
        auto assignment = Determinizer::sample(belief, locationCounts, rng);

        check(assignment.size() == 7, "every tracked tile appears exactly once in the assignment");

        std::map<int, int> observedCounts;
        for (const auto& [tile, location] : assignment) observedCounts[location]++;
        check(observedCounts[1] == 3, "opponent1 receives exactly its capacity (3), not approximately");
        check(observedCounts[2] == 2, "opponent2 receives exactly its capacity (2)");
        check(observedCounts[BeliefState::kBoneyardLocation] == 2, "boneyard receives exactly its capacity (2)");
    }

    section("Determinizer: repeated samples vary -- genuine randomness");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 24; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 2}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(known, {}, locationCounts);

        std::mt19937_64 rng(7);
        auto first = Determinizer::sample(belief, locationCounts, rng);
        auto second = Determinizer::sample(belief, locationCounts, rng);
        check(!(first == second), "two independent samples from the same belief produce different assignments");
    }

    section("Determinizer: over many trials, every equally-likely tile is actually selectable");
    {
        std::vector<DominoTile> known;
        for (int i = 0; i < 25; ++i) known.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 1}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(known, {}, locationCounts);

        std::mt19937_64 rng(99);
        std::map<int, int> hitCounts;
        constexpr int kTrials = 300;
        for (int t = 0; t < kTrials; ++t) {
            auto sample = Determinizer::sample(belief, locationCounts, rng);
            for (const auto& [tile, location] : sample) {
                if (location == 1) hitCounts[tile.index()]++;
            }
        }
        check(hitCounts.size() == 3, "over 300 trials, all three equally-likely tiles were selected at least once");
        for (int idx = 25; idx <= 27; ++idx) {
            check(hitCounts[idx] > 0, "index " + std::to_string(idx) + " was selected for opponent1 at least once");
        }
    }

    if (failureCount() == 0) {
        std::cout << "\nDeterminizer: all checks passed\n";
        return 0;
    }
    std::cout << "\nDeterminizer: " << failureCount() << " check(s) failed\n";
    return 1;
}
