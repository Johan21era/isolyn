#pragma once
#include <map>
#include <random>
#include <utility>
#include <vector>
#include "BeliefState.hpp"
#include "DominoTile.hpp"

namespace isolyn {

// Samples one concrete, complete assignment of every tile BeliefState
// still tracks as uncertain to exactly one location, respecting the
// EXACT capacity given for each location -- never approximately, always
// exactly, since the resulting assignment must be usable to build a
// genuinely valid GameState.
//
// Algorithm: processes locations in a randomly shuffled order (reduces
// systematic bias from a fixed order); for each location but the last,
// samples WITHOUT REPLACEMENT, weighted by each remaining tile's current
// belief-state probability for that location, exactly that location's
// capacity; whatever's left after every location but the last goes
// entirely to the last one (guaranteed correct count, by BeliefState's
// own invariant that capacities sum to the total tracked-tile count).
//
// Honest limitation: this is a valid, capacity-exact,
// marginal-probability-weighted sample, NOT a mathematically exact draw
// from the true joint posterior (which would need iterative proportional
// fitting). For search -- averaging outcomes across many independent
// samples -- this is the standard, defensible approach.
//
// Uses a caller-supplied, explicitly-seedable std::mt19937_64 -- never
// EntropySource, which is deliberately non-reproducible for real-game
// fairness. Determinization is a controlled simulation and needs the
// opposite property: reproducibility for testing and debugging.
class Determinizer {
public:
    static std::vector<std::pair<DominoTile, int>> sample(const BeliefState& belief,
                                                            const std::map<int, int>& locationCounts,
                                                            std::mt19937_64& rng);
};

} // namespace isolyn
