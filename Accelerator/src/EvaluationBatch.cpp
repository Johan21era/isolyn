#include "IsolynEvaluationBatch.hpp"
#include "EvaluationEngine.hpp"

#include <array>
#include <cstddef>
#include <utility>

namespace isolyn::accelerator {

EvaluationBatch encodeEvaluationBatch(GameMode mode,
                                      const std::vector<GameState>& positions) {
    EvaluationBatch batch;
    if (positions.empty()) return batch;

    const std::size_t playerCount = static_cast<std::size_t>(positions.front().playerCount());
    if (playerCount == 0) return batch;
    for (const GameState& position : positions) {
        if (static_cast<std::size_t>(position.playerCount()) != playerCount) return {};
    }

    const EvaluationWeights weights{};
    const std::array<double, kEvaluationComponentCount> componentWeights{{
        weights.mobility,
        weights.blocking,
        weights.expectedValue,
        weights.closingOpportunity,
        weights.winThreat,
        weights.pipControl,
        weights.tempo,
        weights.teamSupport,
    }};

    batch.positionCount = positions.size();
    batch.playerCount = playerCount;
    batch.componentCount = kEvaluationComponentCount;
    batch.features.resize(batch.positionCount * batch.playerCount * batch.componentCount);

    for (std::size_t positionIndex = 0; positionIndex < positions.size(); ++positionIndex) {
        for (std::size_t player = 0; player < playerCount; ++player) {
            const EvaluationBreakdown breakdown =
                EvaluationEngine::evaluate(mode, positions[positionIndex],
                                           static_cast<int>(player), weights);
            const std::array<double, kEvaluationComponentCount> components{{
                breakdown.mobility,
                breakdown.blocking,
                breakdown.expectedValue,
                breakdown.closingOpportunity,
                breakdown.winThreat,
                breakdown.pipControl,
                breakdown.tempo,
                breakdown.teamSupport,
            }};
            const std::size_t base =
                (positionIndex * batch.playerCount + player) * batch.componentCount;
            for (std::size_t component = 0; component < batch.componentCount; ++component) {
                batch.features[base + component] =
                    static_cast<float>(components[component] * componentWeights[component]);
            }
        }
    }

    return batch;
}

} // namespace isolyn::accelerator
