#include "IsolynAccelerator.hpp"
#include "BatchValidation.hpp"

#include <cstddef>
#include <limits>

namespace isolyn::accelerator {

bool evaluateCpuReference(const BatchView& batch) noexcept {
    if (!detail::isValidBatch(batch, std::numeric_limits<std::size_t>::max())) {
        return false;
    }

    const std::size_t componentCount = batch.featureCount / batch.playerCount;
    for (std::size_t position = 0; position < batch.positionCount; ++position) {
        for (std::size_t player = 0; player < batch.playerCount; ++player) {
            const std::size_t base =
                (position * batch.playerCount + player) * componentCount;
            float sum = 0.0f;
            for (std::size_t component = 0; component < componentCount; ++component) {
                sum += batch.features[base + component];
            }
            batch.values[position * batch.playerCount + player] = sum;
        }
    }
    return true;
}

} // namespace isolyn::accelerator
