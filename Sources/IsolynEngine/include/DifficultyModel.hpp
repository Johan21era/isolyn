#pragma once

#include <array>
#include <cstddef>

namespace isolyn {

// A difficulty tier is a search configuration, not a separate rules engine.
// The mapping lives in C++ so the app, the bridge and offline tools all use
// the same numbers; strength labels are presentation, never engine truth.
struct DifficultyProfile {
    int strength = 100;
    int maxDepthPlies = 2;
    int determinizationCount = 8;
};

class DifficultyModel {
public:
    static constexpr int kMinStrength = 100;
    static constexpr int kMaxStrength = 3000;

    // The tiers from the roadmap. A request is clamped to the supported
    // range and then assigned the nearest tier boundary at or above it.
    // Keeping this table monotonic matters more than exact interpolation:
    // the calibration harness is what decides whether the labels are earned.
    static constexpr std::array<DifficultyProfile, 6> kProfiles{{
        {100, 2, 8},
        {400, 2, 8},
        {900, 3, 16},
        {1600, 4, 24},
        {2300, 5, 40},
        {3000, 8, 64},
    }};

    static constexpr DifficultyProfile profileForStrength(int strength) noexcept {
        const int clamped = strength < kMinStrength
            ? kMinStrength
            : (strength > kMaxStrength ? kMaxStrength : strength);

        if (clamped <= 400) return {clamped, 2, 8};
        if (clamped <= 900) return {clamped, 3, 16};
        if (clamped <= 1600) return {clamped, 4, 24};
        if (clamped <= 2300) return {clamped, 5, 40};
        // Depth 8 measured 57.6% against depth 2/8 over 1,000 games
        // (-53.2 Elo, 95% CI [-75.0, -31.4]). It is the stronger elite
        // setting, at roughly 2.6x the median nodes of depth 6.
        return {clamped, 8, 64};
    }
};

} // namespace isolyn