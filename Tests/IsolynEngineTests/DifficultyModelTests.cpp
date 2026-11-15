#include "DifficultyModel.hpp"
#include "TestHarness.hpp"

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("DifficultyModel: monotonic, clamped search tiers");
    {
        check(DifficultyModel::kMaxTileConsumingActions == 28,
              "a double-six game cannot have more than 28 tile-consuming actions");
        check(DifficultyModel::profileForStrength(10000).maxDepthPlies >
                  DifficultyModel::kMaxTileConsumingActions,
              "Mythical's 48 is a search ceiling, not a tile-action depth");

        const auto low = DifficultyModel::profileForStrength(-50);
        check(low.strength == 100 && low.maxDepthPlies == 2 && low.determinizationCount == 8,
              "strength below the range clamps to the casual tier");

        const auto club = DifficultyModel::profileForStrength(900);
        check(club.strength == 900 && club.maxDepthPlies == 3 && club.determinizationCount == 16,
              "900 maps to the solid-basics tier");

        const auto master = DifficultyModel::profileForStrength(3000);
        check(master.strength == 3000 && master.maxDepthPlies == 8 && master.determinizationCount == 64,
              "3000 maps to the master tier");

        const auto legendary = DifficultyModel::profileForStrength(5000);
        check(legendary.strength == 5000 && legendary.maxDepthPlies == 24 &&
                  legendary.determinizationCount == 80,
              "5000 maps to the legendary tier");

        const auto mythical = DifficultyModel::profileForStrength(10000);
        check(mythical.strength == 10000 && mythical.maxDepthPlies == 48 &&
                  mythical.determinizationCount == 160,
              "10000 maps to the mythical tier");

        const auto high = DifficultyModel::profileForStrength(99999);
        check(high.strength == 10000 && high.maxDepthPlies == 48 &&
                  high.determinizationCount == 160,
              "strength above the range clamps to mythical");

        check(DifficultyModel::profileForStrength(400).maxDepthPlies == 2 &&
              DifficultyModel::profileForStrength(401).maxDepthPlies == 3 &&
              DifficultyModel::profileForStrength(900).maxDepthPlies == 3 &&
              DifficultyModel::profileForStrength(901).maxDepthPlies == 4 &&
              DifficultyModel::profileForStrength(3000).maxDepthPlies == 8 &&
              DifficultyModel::profileForStrength(3001).maxDepthPlies == 24 &&
              DifficultyModel::profileForStrength(5000).maxDepthPlies == 24 &&
              DifficultyModel::profileForStrength(5001).maxDepthPlies == 48,
              "adjacent strength tiers never decrease depth");
    }

    return failureCount() == 0 ? 0 : 1;
}