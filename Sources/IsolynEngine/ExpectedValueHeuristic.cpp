#include "ExpectedValueHeuristic.hpp"

namespace isolyn {

double ExpectedValueHeuristic::score(const GameState& state, int playerIndex) {
    int total = 0;
    for (const auto& tile : state.hand(playerIndex)) {
        total += tile.value();
    }
    return -static_cast<double>(total);
}

} // namespace isolyn
