#pragma once

#include <cstddef>
#include <vector>

#include "GameMode.hpp"
#include "GameState.hpp"

namespace isolyn::accelerator {

// The eight EvaluationEngine components, already multiplied by the default
// EvaluationWeights, in one row per position/player. The GPU contract only
// needs to sum each component row.
inline constexpr std::size_t kEvaluationComponentCount = 8;

struct EvaluationBatch {
    std::vector<float> features;
    std::size_t positionCount = 0;
    std::size_t playerCount = 0;
    std::size_t componentCount = 0;
};

// Encodes concrete, already-determinized positions. The caller is responsible
// for hidden-information sampling; this adapter only exposes the evaluator's
// weighted components and never sees opponent information beyond `state`.
//
// Returns an empty batch if `positions` is empty or if the states do not agree
// on player count.
EvaluationBatch encodeEvaluationBatch(GameMode mode,
                                      const std::vector<GameState>& positions);

} // namespace isolyn::accelerator
