#include "DominoTile.hpp"
#include "TestHarness.hpp"
#include <array>

using isolyn::DominoTile;
using namespace isolyn::test;

int main() {
    section("DominoTile: identity and orientation independence");
    check(DominoTile(5, 0) == DominoTile(0, 5), "5-0 and 0-5 are the same tile");
    check(DominoTile(5, 0).low() == 0 && DominoTile(5, 0).high() == 5,
          "canonical form stores the lower pip value first");

    section("DominoTile: value calculation");
    check(DominoTile(6, 6).value() == 12, "6-6 sums to 12");
    check(DominoTile(5, 0).value() == 5, "5-0 sums to 5");
    check(DominoTile(3, 2).value() == 5, "3-2 sums to 5");

    section("DominoTile: doubles");
    check(DominoTile(4, 4).isDouble(), "4-4 is a double");
    check(!DominoTile(4, 3).isDouble(), "4-3 is not a double");

    section("DominoTile: face matching");
    check(DominoTile(5, 2).hasFace(5), "5-2 has a 5 face");
    check(DominoTile(5, 2).hasFace(2), "5-2 has a 2 face");
    check(!DominoTile(5, 2).hasFace(3), "5-2 has no 3 face");

    section("DominoTile: canonical index round-trip (all 28 tiles)");
    bool allRoundTrip = true;
    for (int index = 0; index < DominoTile::kTileCount; ++index) {
        DominoTile tile = DominoTile::fromIndex(index);
        if (tile.index() != index) allRoundTrip = false;
    }
    check(allRoundTrip, "every index in [0,27] round-trips through fromIndex/index");

    section("DominoTile: index uniqueness across all 28 tiles");
    std::array<bool, DominoTile::kTileCount> seen{};
    bool allUnique = true;
    for (int high = 0; high <= DominoTile::kMaxPips; ++high) {
        for (int low = 0; low <= high; ++low) {
            int idx = DominoTile(low, high).index();
            if (idx < 0 || idx >= DominoTile::kTileCount || seen[static_cast<std::size_t>(idx)]) {
                allUnique = false;
            } else {
                seen[static_cast<std::size_t>(idx)] = true;
            }
        }
    }
    check(allUnique, "all 28 tiles map to distinct indices in [0,27]");

    if (isolyn::test::failureCount() == 0) {
        std::cout << "\nDominoTile: all checks passed\n";
        return 0;
    }
    std::cout << "\nDominoTile: " << isolyn::test::failureCount() << " check(s) failed\n";
    return 1;
}
