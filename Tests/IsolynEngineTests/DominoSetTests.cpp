#include "DominoSet.hpp"
#include "EntropySource.hpp"
#include "TestHarness.hpp"
#include <algorithm>
#include <set>

using isolyn::DominoSet;
using isolyn::DominoTile;
using isolyn::EntropySource;
using namespace isolyn::test;

int main() {
    section("DominoSet: full set composition");
    const auto& all = DominoSet::allTiles();
    check(all.size() == 28, "the set contains exactly 28 tiles");

    std::set<int> indices;
    for (const auto& tile : all) indices.insert(tile.index());
    check(indices.size() == 28, "all 28 tiles have distinct canonical indices");

    int doubleCount = 0;
    for (const auto& tile : all) if (tile.isDouble()) ++doubleCount;
    check(doubleCount == 7, "the set contains exactly 7 doubles (0-0 through 6-6)");

    section("DominoSet: shuffling preserves the set");
    EntropySource entropy;
    auto shuffled = DominoSet::shuffledTiles(entropy);
    check(shuffled.size() == 28, "a shuffle still contains 28 tiles");

    std::set<int> shuffledIndices;
    for (const auto& tile : shuffled) shuffledIndices.insert(tile.index());
    check(shuffledIndices == indices, "a shuffle is a permutation of the same 28 tiles, nothing added or lost");

    section("DominoSet: independent shuffles differ");
    auto shuffledAgain = DominoSet::shuffledTiles(entropy);
    bool identicalOrder = std::equal(shuffled.begin(), shuffled.end(), shuffledAgain.begin(),
                                      [](const DominoTile& a, const DominoTile& b) { return a == b; });
    check(!identicalOrder, "two independent shuffles produce different orderings");

    if (failureCount() == 0) {
        std::cout << "\nDominoSet: all checks passed\n";
        return 0;
    }
    std::cout << "\nDominoSet: " << failureCount() << " check(s) failed\n";
    return 1;
}
