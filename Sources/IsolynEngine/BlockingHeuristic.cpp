#include "BlockingHeuristic.hpp"
#include "MoveGenerator.hpp"

namespace isolyn {

double BlockingHeuristic::score(const GameState& state, int playerIndex) {
    int totalOpponentMobility = 0;
    for (int p = 0; p < state.playerCount(); ++p) {
        if (p == playerIndex) continue;
        totalOpponentMobility += MoveGenerator::countLegalMoves(state, p);
    }
    return -static_cast<double>(totalOpponentMobility);
}

} // namespace isolyn
