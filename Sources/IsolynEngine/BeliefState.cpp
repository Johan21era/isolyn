#include "BeliefState.hpp"

namespace isolyn {

BeliefState::BeliefState(const std::vector<DominoTile>& myKnownTiles,
                          const std::vector<DominoTile>& otherKnownTiles,
                          const std::map<int, int>& locationCounts,
                          const std::vector<DominoTile>& excludedTiles) {
    std::array<bool, DominoTile::kTileCount> known{};
    std::array<bool, DominoTile::kTileCount> excluded{};
    for (const auto& tile : myKnownTiles) known[static_cast<std::size_t>(tile.index())] = true;
    for (const auto& tile : otherKnownTiles) known[static_cast<std::size_t>(tile.index())] = true;
    for (const auto& tile : excludedTiles) {
        std::size_t idx = static_cast<std::size_t>(tile.index());
        assert(!known[idx] &&
               "a tile cannot be both known/already-identified and excluded from this round's play entirely");
        excluded[idx] = true;
    }

    int totalUnseen = 0;
    for (const auto& [location, count] : locationCounts) {
        totalUnseen += count;
    }

    int trackedCount = 0;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        std::size_t idx = static_cast<std::size_t>(i);
        if (known[idx] || excluded[idx]) {
            m_tracked[idx] = false;
            continue;
        }
        m_tracked[idx] = true;
        ++trackedCount;
        for (const auto& [location, count] : locationCounts) {
            if (totalUnseen > 0) {
                m_distributions[idx][location] = static_cast<double>(count) / static_cast<double>(totalUnseen);
            }
        }
    }

    assert(trackedCount == totalUnseen &&
           "locationCounts must sum to exactly the number of tiles that are neither known, already identified, "
           "nor excluded from this round's play entirely");
}

bool BeliefState::isTracked(DominoTile tile) const {
    return m_tracked[static_cast<std::size_t>(tile.index())];
}

double BeliefState::probability(DominoTile tile, int location) const {
    std::size_t idx = static_cast<std::size_t>(tile.index());
    if (!m_tracked[idx]) return 0.0;

    const auto& dist = m_distributions[idx];
    auto it = dist.find(location);
    if (it == dist.end()) return 0.0;

    double total = 0.0;
    for (const auto& [loc, p] : dist) total += p;
    if (total <= 0.0) return 0.0;

    return it->second / total;
}

double BeliefState::totalProbabilityMass(int location) const {
    double total = 0.0;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        if (!m_tracked[static_cast<std::size_t>(i)]) continue;
        total += probability(DominoTile::fromIndex(i), location);
    }
    return total;
}

void BeliefState::markTileKnown(DominoTile tile, int location, int newLocationCount) {
    std::size_t idx = static_cast<std::size_t>(tile.index());
    assert(m_tracked[idx] && "markTileKnown requires a currently-tracked (still uncertain) tile");

    m_tracked[idx] = false;
    m_distributions[idx].clear();

    double remainingRawSum = 0.0;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        if (!m_tracked[static_cast<std::size_t>(i)]) continue;
        auto it = m_distributions[static_cast<std::size_t>(i)].find(location);
        if (it != m_distributions[static_cast<std::size_t>(i)].end()) {
            remainingRawSum += it->second;
        }
    }
    if (remainingRawSum <= 0.0) return;

    double scale = static_cast<double>(newLocationCount) / remainingRawSum;
    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        if (!m_tracked[static_cast<std::size_t>(i)]) continue;
        auto it = m_distributions[static_cast<std::size_t>(i)].find(location);
        if (it != m_distributions[static_cast<std::size_t>(i)].end()) {
            it->second *= scale;
        }
    }
}

void BeliefState::applyOpponentDraw(int drawingPlayer) {
    // Exact derivation. Let B = totalProbabilityMass(boneyard) before
    // this call, which by the class invariant equals the boneyard's true
    // known tile count. The tile actually drawn is, by exchangeability
    // (the boneyard's fixed draw order came from a uniformly random
    // shuffle nobody has observed -- see EntropySource -- so "the next
    // tile" is statistically indistinguishable from a uniform pick over
    // whatever remains), equally likely to be any one of the B
    // boneyard-probability-units. So for any given tracked tile t, the
    // probability it was the one drawn is exactly its boneyard share
    // divided by B.
    //
    // For each tracked tile t: move = p(t, boneyard) / B is added to
    // p(t, drawingPlayer) and subtracted from p(t, boneyard). Both
    // invariants hold exactly afterward:
    //   - per-tile total is unchanged: mass only moves within a single
    //     tile's own distribution, nothing added or removed overall.
    //   - aggregate totals shift by exactly +1 for drawingPlayer and -1
    //     for the boneyard: summing `move` over every tracked tile gives
    //     sum(p(t,boneyard))/B = B/B = 1, exactly the one tile that
    //     moved.
    double boneyardMassBefore = totalProbabilityMass(kBoneyardLocation);
    assert(boneyardMassBefore > 0.0 &&
           "applyOpponentDraw requires the boneyard to have had at least one unit of probability mass before the draw");

    for (int i = 0; i < DominoTile::kTileCount; ++i) {
        if (!m_tracked[static_cast<std::size_t>(i)]) continue;
        auto& dist = m_distributions[static_cast<std::size_t>(i)];
        auto boneyardIt = dist.find(kBoneyardLocation);
        double boneyardShare = (boneyardIt != dist.end()) ? boneyardIt->second : 0.0;
        if (boneyardShare == 0.0) continue;

        double moved = boneyardShare / boneyardMassBefore;
        dist[drawingPlayer] += moved;
        dist[kBoneyardLocation] = boneyardShare - moved;
    }
}

} // namespace isolyn
