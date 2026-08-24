#pragma once
#include <iostream>
#include <string>

// Deliberately minimal for this pass -- real pass/fail output with named
// checks, no vendored framework. Whether to adopt Catch2/GoogleTest/doctest
// (and how the C++ test layer eventually plugs into `swift test`) is a
// real decision for the testing-infrastructure pass in Phase 4, not
// something to quietly commit to here.
namespace isolyn::test {

inline int& failureCount() {
    static int count = 0;
    return count;
}

inline void check(bool condition, const std::string& description) {
    if (condition) {
        std::cout << "  [pass] " << description << "\n";
    } else {
        std::cout << "  [FAIL] " << description << "\n";
        ++failureCount();
    }
}

inline void section(const std::string& name) {
    std::cout << name << "\n";
}

} // namespace isolyn::test
