#include "MobilityHeuristic.hpp"
#include "MoveGenerator.hpp"

namespace isolyn {

double MobilityHeuristic::score(const GameState& state, int playerIndex) {
    return static_cast<double>(MoveGenerator::generate(state, playerIndex).size());
}

} // namespace isolyn
