#include "DifficultyModel.hpp"
#include "TestHarness.hpp"

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("DifficultyModel: monotonic, clamped search tiers");
    {
        const auto low = DifficultyModel::profileForStrength(-50);
        check(low.strength == 100 && low.maxDepthPlies == 2 && low.determinizationCount == 8,
              "strength below the range clamps to the casual tier");

        const auto club = DifficultyModel::profileForStrength(900);
        check(club.strength == 900 && club.maxDepthPlies == 3 && club.determinizationCount == 16,
              "900 maps to the solid-basics tier");

        const auto elite = DifficultyModel::profileForStrength(3000);
        check(elite.strength == 3000 && elite.maxDepthPlies == 8 && elite.determinizationCount == 64,
              "3000 maps to the elite tier");

        const auto high = DifficultyModel::profileForStrength(99999);
        check(high.strength == 3000 && high.maxDepthPlies == 8 && high.determinizationCount == 64,
              "strength above the range clamps to elite");

        check(DifficultyModel::profileForStrength(400).maxDepthPlies == 2 &&
              DifficultyModel::profileForStrength(401).maxDepthPlies == 3 &&
              DifficultyModel::profileForStrength(900).maxDepthPlies == 3 &&
              DifficultyModel::profileForStrength(901).maxDepthPlies == 4,
              "adjacent strength tiers never decrease depth");
    }

    return failureCount() == 0 ? 0 : 1;
}