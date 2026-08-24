#pragma once
#include <cstddef>
#include <cstdint>
#include <utility>
#include <vector>

namespace isolyn {

// Produces genuinely non-deterministic randomness for actual gameplay
// events (shuffling the domino set, and anything else the rules leave to
// chance). Every random draw comes directly from the operating system's
// own cryptographic randomness source -- BCryptGenRandom on Windows,
// getrandom() on Linux, SecRandomCopyBytes on macOS -- rather than using
// that source once to seed a general-purpose PRNG (std::mt19937_64, used
// by the previous implementation) and drawing many values from it. There
// is deliberately no fallback of any kind: if the platform's CSPRNG is
// ever unavailable, this throws rather than silently degrading to
// something weaker (rand(), a time-seeded engine, etc.).
//
// This is deliberately separate from any seeded/reproducible RNG used
// later by SimulationEngine for determinization sampling (a
// std::mt19937_64 there, explicitly seeded for reproducibility). Genuine
// unpredictability and reproducibility are opposite properties;
// conflating them here would quietly compromise whichever one lost the
// argument.
class EntropySource {
public:
    EntropySource() = default;

    // Unbiased Fisher-Yates (Durstenfeld) shuffle: every permutation of
    // the input is equally likely. Each swap partner is drawn via
    // rejection sampling (see uniformIndexBelow below), never a raw
    // modulo reduction, so no index is ever favored by however evenly
    // the sequence's length happens to divide the RNG's output range.
    template <typename T>
    void shuffle(std::vector<T>& sequence) const {
        if (sequence.empty()) {
            return;
        }
        for (std::size_t i = sequence.size() - 1; i > 0; --i) {
            const std::size_t j = static_cast<std::size_t>(
                uniformIndexBelow(static_cast<std::uint64_t>(i) + 1U));
            std::swap(sequence[i], sequence[j]);
        }
    }

private:
    // Fills the buffer with cryptographically secure random bytes from
    // the operating system. Every platform branch loops until the full
    // buffer is filled (a single OS call is not guaranteed to satisfy an
    // arbitrarily large request) and throws std::runtime_error on any
    // platform-reported failure -- never substitutes a weaker source.
    static void fillSecureRandomBytes(std::uint8_t* buffer, std::size_t size);

    // A uniformly random 64-bit value, drawn directly from the OS CSPRNG.
    static std::uint64_t nextUint64();

    // Uniformly distributed integer in [0, bound). Rejection sampling
    // discards the incomplete top slice of the uint64_t range (whose
    // size is `2^64 mod bound`, computed as `-bound % bound` via
    // unsigned wraparound, avoiding the need for a 128-bit type) so the
    // portion actually used divides evenly by `bound` -- eliminating
    // modulo bias entirely, rather than accepting the skew a plain
    // `nextUint64() % bound` would introduce. Precondition: bound > 0,
    // guaranteed by shuffle()'s own loop bounds (i+1 where i >= 1) --
    // never called with an empty range.
    static std::uint64_t uniformIndexBelow(std::uint64_t bound);
};

} // namespace isolyn
