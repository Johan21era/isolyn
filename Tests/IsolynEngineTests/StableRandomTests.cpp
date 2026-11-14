#include "StableRandom.hpp"
#include "TestHarness.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <random>
#include <vector>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("StableRandom: a fixed seed pins a fixed cross-platform integer stream");
    {
        std::mt19937_64 rng(0x1501C0DEULL);
        const std::vector<std::uint64_t> expected = {
            25, 5, 6, 6, 27, 9, 4, 0, 10, 26, 14, 3,
        };
        bool matches = true;
        for (std::uint64_t value : expected) {
            matches = matches && stable_random::uniformIndexBelow(rng, 28) == value;
        }
        check(matches, "the first 12 indices for seed 0x1501C0DE are pinned");

        std::mt19937_64 replay(0x1501C0DEULL);
        bool replayMatches = true;
        for (std::uint64_t value : expected) {
            replayMatches = replayMatches && stable_random::uniformIndexBelow(replay, 28) == value;
        }
        check(replayMatches, "the same seed reproduces the same indices");
    }

    section("StableRandom: a shuffle is a permutation, not a lossy resample");
    {
        std::vector<int> values = {0, 1, 2, 3, 4, 5, 6, 7};
        std::mt19937_64 rng(42);
        stable_random::shuffle(values, rng);

        std::vector<int> sorted = values;
        std::sort(sorted.begin(), sorted.end());
        check(sorted == std::vector<int>({0, 1, 2, 3, 4, 5, 6, 7}),
              "shuffle preserves every value exactly once");
        check(values == std::vector<int>({7, 0, 5, 1, 2, 4, 3, 6}),
              "seed 42 produces the pinned permutation");
    }

    section("StableRandom: integer bounds are respected, including bound 1");
    {
        std::mt19937_64 rng(7);
        bool inBounds = true;
        for (std::uint64_t bound : {1ULL, 2ULL, 3ULL, 28ULL, 1009ULL}) {
            for (int i = 0; i < 500; ++i) {
                inBounds = inBounds && stable_random::uniformIndexBelow(rng, bound) < bound;
            }
        }
        check(inBounds, "500 draws per bound stay inside [0, bound)");
    }

    section("StableRandom: the unit interval is [0, 1) and pinned");
    {
        std::mt19937_64 rng(9);
        const double value = stable_random::unitInterval(rng);
        check(value >= 0.0 && value < 1.0, "unitInterval returns [0, 1)");
        check(std::abs(value - 0.51851910188764505) < 1e-15,
              "seed 9 produces the pinned unit-interval value");
    }

    if (failureCount() == 0) {
        std::cout << "\nStableRandom: all checks passed\n";
        return 0;
    }
    std::cout << "\nStableRandom: " << failureCount() << " check(s) failed\n";
    return 1;
}
