#include "EntropySource.hpp"
#include <algorithm>
#include <cassert>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>

#ifdef _WIN32
    #define NOMINMAX
    #include <windows.h>
    #include <bcrypt.h>
    #pragma comment(lib, "bcrypt.lib")
#elif defined(__linux__)
    #include <cerrno>
    #include <sys/random.h>
#elif defined(__APPLE__)
    #include <Security/Security.h>
#else
    #error "Unsupported operating system. EntropySource supports Windows, Linux, and macOS."
#endif

namespace isolyn {

void EntropySource::fillSecureRandomBytes(std::uint8_t* buffer, std::size_t size) {
#ifdef _WIN32

    // Windows CNG's system-preferred cryptographic RNG.
    while (size > 0) {
        const ULONG chunk = static_cast<ULONG>(
            std::min(size, static_cast<std::size_t>(std::numeric_limits<ULONG>::max())));

        const NTSTATUS status =
            BCryptGenRandom(nullptr, buffer, chunk, BCRYPT_USE_SYSTEM_PREFERRED_RNG);

        if (status != 0) {
            throw std::runtime_error(
                "BCryptGenRandom failed with NTSTATUS " + std::to_string(static_cast<long>(status)));
        }

        buffer += chunk;
        size -= chunk;
    }

#elif defined(__linux__)

    while (size > 0) {
        const ssize_t result = ::getrandom(buffer, size, 0);

        if (result < 0) {
            if (errno == EINTR) {
                continue;
            }
            throw std::runtime_error(std::string("getrandom() failed: ") + std::strerror(errno));
        }

        if (result == 0) {
            throw std::runtime_error("getrandom() returned zero bytes unexpectedly");
        }

        buffer += result;
        size -= static_cast<std::size_t>(result);
    }

#elif defined(__APPLE__)

    const OSStatus status = SecRandomCopyBytes(kSecRandomDefault, size, buffer);

    if (status != errSecSuccess) {
        throw std::runtime_error(
            "SecRandomCopyBytes failed with OSStatus " + std::to_string(static_cast<long>(status)));
    }

#endif
}

std::uint64_t EntropySource::nextUint64() {
    std::uint64_t value = 0;
    fillSecureRandomBytes(reinterpret_cast<std::uint8_t*>(&value), sizeof(value));
    return value;
}

std::uint64_t EntropySource::uniformIndexBelow(std::uint64_t bound) {
    assert(bound > 0 && "uniformIndexBelow requires a positive bound");

    const std::uint64_t rejectionThreshold = static_cast<std::uint64_t>(-bound) % bound;

    for (;;) {
        const std::uint64_t value = nextUint64();
        if (value >= rejectionThreshold) {
            return value % bound;
        }
    }
}

} // namespace isolyn
