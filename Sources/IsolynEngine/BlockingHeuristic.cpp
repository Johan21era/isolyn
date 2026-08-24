#include "BlockingHeuristic.hpp"
#include "MoveGenerator.hpp"

namespace isolyn {

double BlockingHeuristic::score(const GameState& state, int playerIndex) {
    int totalOpponentMobility = 0;
    for (int p = 0; p < state.playerCount(); ++p) {
        if (p == playerIndex) continue;
        totalOpponentMobility += static_cast<int>(MoveGenerator::generate(state, p).size());
    }
    return -static_cast<double>(totalOpponentMobility);
}

} // namespace isolyn
