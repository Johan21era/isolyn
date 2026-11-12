#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

namespace isolyn::accelerator {

// A flat batch of already-weighted feature rows.
//
// Layout is row-major:
//   features[(position * playerCount + player) * componentCount + component]
// where componentCount == featureCount / playerCount.
//
// This is the generic linear contract. The compact position contract below is
// the path that computes evaluation features on the GPU instead of on the host.
struct BatchView {
    const float* features = nullptr;
    std::size_t positionCount = 0;
    std::size_t featureCount = 0;
    float* values = nullptr;
    std::size_t playerCount = 0;
};

// Compact, rule-neutral description of one concrete, already-determinized
// position. The host sets only facts; the GPU computes the same eight
// EvaluationEngine components as the C++ reference.
struct PositionRow {
    std::uint32_t handMasks[4] = {};
    std::int32_t leftEnd = -1;
    std::int32_t rightEnd = -1;
    std::uint32_t currentPlayer = 0;
    std::uint32_t playerCount = 0;
    std::uint32_t mode = 0;          // GameMode's underlying value
    std::uint32_t closed = 0;        // MoveGenerator::isPositionClosed
    std::uint32_t closerPlayer = 0;  // RulesEngine::determineCloser
    std::uint32_t roundScores[4] = {};
};

struct PositionBatchView {
    const PositionRow* positions = nullptr;
    std::size_t positionCount = 0;
    float* values = nullptr;
    std::size_t playerCount = 0;
};

struct Capabilities {
    bool available = false;
    bool unifiedMemory = false;
    std::size_t maxBatchSize = 0;
    std::string_view name{};
};

class Backend {
public:
    virtual ~Backend() = default;

    virtual Capabilities capabilities() const noexcept = 0;

    // Returns true only when every position in the batch was evaluated.
    // Implementations must fail closed on malformed batches or device errors;
    // the caller then falls back to the CPU reference path.
    virtual bool evaluate(const BatchView& batch) noexcept = 0;

    // Computes EvaluationEngine totals for compact positions. Default false is
    // the deliberate fail-closed fallback for backends that only support the
    // generic linear contract.
    virtual bool evaluatePositions(const PositionBatchView&) noexcept { return false; }
};

// Deterministic CPU reference for the generic linear feature contract.
bool evaluateCpuReference(const BatchView& batch) noexcept;

// Returns nullptr when Metal is not compiled in, no compatible device exists,
// or the runtime shader/pipeline could not be created.
Backend* metalBackend() noexcept;

} // namespace isolyn::accelerator
