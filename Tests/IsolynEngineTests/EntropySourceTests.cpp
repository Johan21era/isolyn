#include "EntropySource.hpp"
#include "DominoSet.hpp"
#include "TestHarness.hpp"
#include <array>
#include <set>
#include <string>
#include <vector>

using isolyn::DominoSet;
using isolyn::DominoTile;
using isolyn::EntropySource;
using namespace isolyn::test;

int main() {
    section("EntropySource: distribution sanity check");
    // Coarse smoke test, not a formal randomness test suite -- this exists
    // to catch gross bugs (a fixed seed, a shuffle that never moves
    // certain tiles), not to certify cryptographic quality. The OS CSPRNG
    // call underneath is the actual guarantee of genuine entropy; this
    // test guards the shuffle code that consumes it.
    EntropySource entropy;
    constexpr int kTrials = 2000;
    std::array<int, DominoTile::kTileCount> firstPositionCounts{};

    for (int trial = 0; trial < kTrials; ++trial) {
        auto shuffled = DominoSet::shuffledTiles(entropy);
        int idx = shuffled.front().index();
        ++firstPositionCounts[static_cast<std::size_t>(idx)];
    }

    double expected = static_cast<double>(kTrials) / DominoTile::kTileCount;
    bool roughlyUniform = true;
    for (int count : firstPositionCounts) {
        if (count < expected * 0.3 || count > expected * 2.0) roughlyUniform = false;
    }
    check(roughlyUniform,
          "each of the 28 tiles lands in the first position roughly 1/28 of the time over "
          + std::to_string(kTrials) + " trials");

    section("EntropySource: independent instances do not collide");
    EntropySource entropyB;
    auto shuffledA = DominoSet::shuffledTiles(entropy);
    auto shuffledB = DominoSet::shuffledTiles(entropyB);
    bool identical = true;
    for (std::size_t i = 0; i < shuffledA.size(); ++i) {
        if (!(shuffledA[i] == shuffledB[i])) { identical = false; break; }
    }
    check(!identical, "two independent EntropySource instances do not produce the same shuffle");

    section("EntropySource: empty and single-element input are handled without corrupting memory");
    // A hand-rolled Fisher-Yates walks the sequence via `size() - 1`,
    // which underflows on an empty std::vector (size_type is unsigned)
    // unless explicitly guarded -- this regression-tests that guard
    // directly, rather than relying on it never being noticed missing.
    {
        std::vector<DominoTile> emptySequence;
        entropy.shuffle(emptySequence);
        check(emptySequence.empty(), "shuffling an empty sequence leaves it empty, doesn't crash");

        std::vector<DominoTile> singleTile{ DominoTile(3, 5) };
        entropy.shuffle(singleTile);
        check(singleTile.size() == 1 && singleTile[0] == DominoTile(3, 5),
              "shuffling a single-element sequence leaves it unchanged");
    }

    section("EntropySource: every shuffle, across many trials, is a genuine permutation of the original set");
    // Structural integrity, not statistical quality (the distribution
    // sanity check above already covers that): across many independent
    // shuffles, the result must always be exactly the same 28 tiles --
    // nothing duplicated, nothing missing, nothing invented.
    {
        constexpr int kPermutationTrials = 5000;
        const auto& all = DominoSet::allTiles();
        std::set<int> expectedIndices;
        for (const auto& tile : all) expectedIndices.insert(tile.index());

        bool everyTrialValid = true;
        for (int trial = 0; trial < kPermutationTrials; ++trial) {
            std::vector<DominoTile> deck(all.begin(), all.end());
            entropy.shuffle(deck);

            if (deck.size() != 28) {
                everyTrialValid = false;
                break;
            }

            std::set<int> seenIndices;
            bool hasDuplicate = false;
            for (const auto& tile : deck) {
                if (!seenIndices.insert(tile.index()).second) {
                    hasDuplicate = true;
                    break;
                }
            }
            if (hasDuplicate || seenIndices != expectedIndices) {
                everyTrialValid = false;
                break;
            }
        }
        check(everyTrialValid,
              "across " + std::to_string(kPermutationTrials) + " shuffles, every result is exactly "
              "the original 28 tiles -- no duplicates, none missing, none invented");
    }

    if (failureCount() == 0) {
        std::cout << "\nEntropySource: all checks passed\n";
        return 0;
    }
    std::cout << "\nEntropySource: " << failureCount() << " check(s) failed\n";
    return 1;
}
