// Standalone fuzz driver -- used ONLY when Apple's toolchain lacks the
// libFuzzer runtime (several Xcode releases ship libclang_rt.fuzzer for
// simulator/device triples but not macOS). Drives the exact same
// LLVMFuzzerTestOneInput harness as the real libFuzzer build
// (FuzzBridge.cpp), with pseudo-random inputs plus single-line mutations of
// the previous input so interesting byte patterns get local exploration --
// a deliberately small slice of what libFuzzer's coverage guidance does,
// never claimed to be equivalent. Value here is sanitizer-backed execution
// of adversarial bridge arguments on macOS where -fsanitize=fuzzer cannot
// link at all. Build with ASan+UBSan (see run_bridge_fuzz.sh fallback).
//
// Usage: standalone_fuzz_driver [iterations] [seed]
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size);

int main(int argc, char** argv) {
    const unsigned long iters = argc > 1 ? std::strtoul(argv[1], nullptr, 10) : 50000UL;
    const unsigned long seed  = argc > 2 ? std::strtoul(argv[2], nullptr, 10) : 0xC0FFEEUL;

    std::mt19937_64 rng(seed);
    std::vector<uint8_t> current;
    std::vector<uint8_t> previous;

    unsigned long executed = 0;
    for (unsigned long i = 0; i < iters; ++i) {
        size_t size = 0;
        if (!previous.empty() && (rng() % 100) < 35) {
            // Mutate the previous input: keeps successful byte patterns alive
            // and explores their neighborhood, mimicking corpus behavior.
            current = previous;
            const int flips = 1 + static_cast<int>(rng() % 4);
            for (int f = 0; f < flips && !current.empty(); ++f) {
                const size_t idx = rng() % current.size();
                current[idx] ^= static_cast<uint8_t>(1u << (rng() % 8));
            }
            if ((rng() % 100) < 25 && current.size() > 1) {
                current.resize(rng() % current.size());
            }
        } else {
            size = static_cast<size_t>(rng() % 256);
            current.assign(size, 0);
            for (size_t j = 0; j < size; ++j) current[j] = static_cast<uint8_t>(rng());
        }

        LLVMFuzzerTestOneInput(current.data(), current.size());
        ++executed;
        previous = current;
    }

    std::printf("standalone fuzz: %lu executions, zero crashes / hangs / sanitizer findings\n", executed);
    return 0;
}
