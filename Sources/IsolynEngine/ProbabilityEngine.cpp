#include "ProbabilityEngine.hpp"
#include "Dealer.hpp"

namespace isolyn {

BeliefState ProbabilityEngine::constructFromGameState(const GameState& state, int believerIndex) {
    std::vector<DominoTile> myKnown(state.hand(believerIndex).begin(), state.hand(believerIndex).end());

    std::vector<DominoTile> otherKnown;
    for (const auto& tile : state.chain().orderedTiles()) {
        otherKnown.push_back(tile);
    }

    // R-17: the locked pair is never revealed. Keep it in the boneyard's
    // uncertain count; the sampler may place any unseen identities in the
    // two locked slots, which is the correct information set. Treating the
    // pair as known here (the old behavior) told the AI exactly which tiles
    // could never be drawn.
    std::map<int, int> locationCounts;
    for (int p = 0; p < state.playerCount(); ++p) {
        if (p == believerIndex) continue;
        locationCounts[p] = static_cast<int>(state.hand(p).size());
    }
    locationCounts[BeliefState::kBoneyardLocation] = static_cast<int>(state.boneyard().size());

    // Modes that remove tiles from play entirely (currently only
    // OneVsOneVsOne's 0-0) must tell BeliefState so its "every one of
    // the 28 canonical tiles is known, identified, or trackable
    // somewhere" accounting doesn't try to track a tile that was never
    // dealt to anyone in the first place. Same source Dealer::deal
    // itself uses, so the two can never disagree about which tiles that
    // is.
    //
    // There is no survivor phase (R-22), so the mode alone decides which
    // tiles were never dealt to anyone.
    const std::vector<DominoTile> excluded = Dealer::excludedTilesForMode(state.mode());
    return BeliefState(myKnown, otherKnown, locationCounts, excluded);
}

void ProbabilityEngine::observePlay(BeliefState& belief, const GameState& stateAfter, int playerIndex, DominoTile tile) {
    if (!belief.isTracked(tile)) return; // already known to the believer some other way (e.g. it's their own tile)
    belief.markTileKnown(tile, playerIndex, static_cast<int>(stateAfter.hand(playerIndex).size()));
}

void ProbabilityEngine::observeDraw(BeliefState& belief, const GameState& /*stateAfter*/, int drawingPlayer) {
    belief.applyOpponentDraw(drawingPlayer);
}

double ProbabilityEngine::probabilityHoldsTile(const BeliefState& belief, int playerIndex, DominoTile tile) {
    return belief.probability(tile, playerIndex);
}

double ProbabilityEngine::expectedRemainingValue(const BeliefState& belief, int playerIndex) {
    double total = 0.0;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        DominoTile tile = DominoTile::fromIndex(i);
        if (!belief.isTracked(tile)) continue;
        total += belief.probability(tile, playerIndex) * tile.value();
    }
    return total;
}

double ProbabilityEngine::probabilityHoldsAtLeast(const BeliefState& belief, int playerIndex, int pipValue, int minimumCount) {
    std::vector<double> perTileProbabilities;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        DominoTile tile = DominoTile::fromIndex(i);
        if (!tile.hasFace(pipValue)) continue;
        if (!belief.isTracked(tile)) continue;
        perTileProbabilities.push_back(belief.probability(tile, playerIndex));
    }

    int k = static_cast<int>(perTileProbabilities.size());
    std::vector<double> dp(static_cast<std::size_t>(k) + 1, 0.0);
    dp[0] = 1.0;
    for (double p : perTileProbabilities) {
        for (int j = k; j >= 1; --j) {
            dp[static_cast<std::size_t>(j)] = dp[static_cast<std::size_t>(j)] * (1.0 - p) + dp[static_cast<std::size_t>(j - 1)] * p;
        }
        dp[0] *= (1.0 - p);
    }

    double total = 0.0;
    for (int j = minimumCount; j <= k; ++j) {
        if (j < 0) continue;
        total += dp[static_cast<std::size_t>(j)];
    }
    return total;
}

} // namespace isolyn
