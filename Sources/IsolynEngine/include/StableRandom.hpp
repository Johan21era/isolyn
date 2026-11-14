#pragma once

#include <cassert>
#include <cstdint>
#include <random>
#include <utility>
#include <vector>

namespace isolyn {

// Seeded randomness used by the lab must not depend on a standard library's
// implementation-defined distributions. std::mt19937_64 itself is specified by
// the C++ standard, so these helpers take its raw output and apply arithmetic we
// own:
//
// - rejection sampling for an unbiased integer in [0, bound);
// - Fisher-Yates for an unbiased permutation;
// - 53 high bits for a double in [0, 1).
//
// A macOS build using libc++ and a Linux build using libstdc++ therefore produce
// the same sequence for the same seed. This is separate from EntropySource,
// which deliberately uses the operating system CSPRNG for real play.
namespace stable_random {

// Uniform integer in [0, bound). Precondition: bound > 0.
inline std::uint64_t uniformIndexBelow(std::mt19937_64& rng, std::uint64_t bound) {
    assert(bound > 0 && "uniformIndexBelow requires a positive bound");
    // Discard the incomplete top slice of the 64-bit range. This is the same
    // rejection rule EntropySource uses, but fed by the seeded PRNG.
    const std::uint64_t rejectionThreshold = static_cast<std::uint64_t>(-bound) % bound;
    for (;;) {
        const std::uint64_t value = rng();
        if (value >= rejectionThreshold) {
            return value % bound;
        }
    }
}

// Unbiased Fisher-Yates (Durstenfeld) shuffle.
template <typename T>
void shuffle(std::vector<T>& sequence, std::mt19937_64& rng) {
    for (std::size_t i = sequence.size(); i > 1; --i) {
        const std::uint64_t j = uniformIndexBelow(rng, static_cast<std::uint64_t>(i));
        std::swap(sequence[i - 1], sequence[static_cast<std::size_t>(j)]);
    }
}

// Uniform double in [0, 1). Taking the top 53 bits gives every representable
// step the same probability without relying on uniform_real_distribution.
inline double unitInterval(std::mt19937_64& rng) {
    return static_cast<double>(rng() >> 11) * (1.0 / 9007199254740992.0);
}

} // namespace stable_random
} // namespace isolyn
