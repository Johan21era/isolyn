#pragma once
#include <random>
#include "BeliefState.hpp"
#include "GameState.hpp"

namespace isolyn {

// Produces one complete, hypothetical GameState consistent with
// everything `believerIndex` actually knows in `realState`: their own
// hand, the visible chain (and its exposed ends), the turn/history state,
// are all copied exactly. Every other player's hand and the boneyard's
// still-uncertain portion are filled in from one sample drawn via
// Determinizer, weighted by `belief`. The boneyard's already-revealed
// locked tiles (if any) are appended after the sampled portion, in their
// real identities -- nothing about them is re-sampled, since they were
// never uncertain to begin with.
class SimulationEngine {
public:
    static GameState sampleDeterminizedState(const GameState& realState, const BeliefState& belief,
                                              int believerIndex, std::mt19937_64& rng);
};

} // namespace isolyn
