#pragma once

#include "IsolynAccelerator.hpp"

#include <cstddef>
#include <limits>

namespace isolyn::accelerator::detail {

inline bool isValidBatch(const BatchView& batch, std::size_t maxBatchSize) noexcept {
    if (batch.features == nullptr || batch.values == nullptr) return false;
    if (batch.positionCount == 0 || batch.featureCount == 0 || batch.playerCount == 0) return false;
    if (batch.positionCount > maxBatchSize) return false;
    if (batch.featureCount % batch.playerCount != 0) return false;

    const std::size_t componentCount = batch.featureCount / batch.playerCount;
    if (componentCount == 0 || componentCount > 64) return false;

    const std::size_t max = std::numeric_limits<std::size_t>::max();
    if (batch.featureCount > max / batch.positionCount) return false;
    if (batch.playerCount > max / batch.positionCount) return false;
    return true;
}

} // namespace isolyn::accelerator::detail
