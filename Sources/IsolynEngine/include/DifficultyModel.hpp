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
    static constexpr int kMaxStrength = 10000;

    // A double-six hand cannot contain more than 28 tiles, and every legal
    // placement or voluntary/forced draw consumes one. This is the
    // tile-consuming action ceiling (27 in 1v1v1, where 0-0 is excluded); a
    // pass adds a ply but does not consume a tile. A tier's maxDepthPlies may
    // exceed this as a search guard; it must never be reported as a reached
    // game depth as though 48 plies were a normal hand.
    static constexpr int kMaxTileConsumingActions = 28;

    // The tiers from the roadmap. A request is clamped to the supported
    // range and then assigned the nearest tier boundary at or above it.
    // Keeping this table monotonic matters more than exact interpolation:
    // the calibration harness is what decides whether the labels are earned.
    static constexpr std::array<DifficultyProfile, 8> kProfiles{{
        {100, 2, 8},
        {400, 2, 8},
        {900, 3, 16},
        {1600, 4, 24},
        {2300, 5, 40},
        {3000, 8, 64},
        {5000, 24, 80},
        {10000, 48, 160},
    }};

    static constexpr DifficultyProfile profileForStrength(int strength) noexcept {
        const int clamped = strength < kMinStrength
            ? kMinStrength
            : (strength > kMaxStrength ? kMaxStrength : strength);

        if (clamped <= 400) return {clamped, 2, 8};
        if (clamped <= 900) return {clamped, 3, 16};
        if (clamped <= 1600) return {clamped, 4, 24};
        if (clamped <= 2300) return {clamped, 5, 40};
        // Master keeps the measured full-width setting. Legendary and Mythical
        // are deep-search tiers: the bridge enables PVS/LMR for them. Legendary
        // completes 24 plies on the measured 15-second openings; Mythical's 48
        // is a search ceiling, not a normal game depth (a hand has at most 28
        // tile-consuming actions). Neither label is a strength claim.
        if (clamped <= 3000) return {clamped, 8, 64};
        if (clamped <= 5000) return {clamped, 24, 80};
        return {clamped, 48, 160};
    }
};

} // namespace isolyn