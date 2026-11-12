#pragma once

#include <cstddef>
#include <vector>

#include "GameMode.hpp"
#include "GameState.hpp"
#include "IsolynAccelerator.hpp"

namespace isolyn::accelerator {

struct PositionBatch {
    std::vector<PositionRow> rows;
    std::size_t playerCount = 0;
};

// Encodes concrete, already-determinized states into the compact GPU layout.
// The caller owns hidden-information sampling; this adapter only turns visible
// state facts into masks and chain/round metadata.
//
// Returns an empty batch if `positions` is empty or the states disagree on
// player count.
PositionBatch encodePositionBatch(GameMode mode,
                                  const std::vector<GameState>& positions);

} // namespace isolyn::accelerator
