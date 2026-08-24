#pragma once
#include <array>
#include <cassert>
#include <map>
#include <vector>
#include "DominoTile.hpp"

namespace isolyn {

// Tracks, for every tile NOT currently known to the belief-holder, a
// probability distribution over which location it occupies: another
// player's hand, or the boneyard. Deliberately independent of GameState
// -- constructed from primitive counts, not a live reference -- so
// hidden-information reasoning stays separable from deterministic rule
// enforcement (Concept Spec's Separation of Systems), and so this is
// testable without a real game in progress. ProbabilityEngine is the
// bridge that constructs and updates instances of this from a real
// GameState; this class itself never touches one.
//
// Rigor status, stated plainly rather than implied: the initial
// distribution (constructor) and applyOpponentDraw() are exact --
// derived and verified in BeliefState.cpp to preserve both per-tile
// normalization and per-location count-consistency simultaneously, not
// approximations. markTileKnown()'s rebalancing is a documented,
// defensible single-pass approximation, not the mathematically exact
// joint solution (which would need iterative proportional fitting
// across every tracked tile and location at once, solved to
// convergence rather than in one pass). probability() always returns a
// per-tile-normalized value on query, regardless of any such drift in
// the underlying stored weights -- callers never see an inconsistent
// distribution for a single tile, even though the AGGREGATE per-location
// sum may drift slightly after markTileKnown calls specifically. The
// eventual Determinizer samples complete, count-consistent worlds
// directly, which is what carries search-critical precision; these
// marginals exist primarily for explainability (puzzle/analysis text,
// live eval display), where an honestly-approximate, clearly-documented
// number is worth far more than a claim of exactness nobody can cheaply
// verify.
class BeliefState {
public:
    static constexpr int kBoneyardLocation = -1;

    // `myKnownTiles`: tiles certain to be in the belief-holder's own
    // hand -- excluded from tracking entirely. `otherKnownTiles`: tiles
    // certain to be elsewhere and already identified (played on the
    // chain, or a revealed locked-boneyard pair) -- also excluded.
    // `locationCounts` maps each OTHER player's index to their current
    // hand size, plus kBoneyardLocation to the boneyard's current total
    // remaining size (including any not-yet-revealed locked tiles --
    // once revealed, they belong in otherKnownTiles instead of this
    // count; see ProbabilityEngine::constructFromGameState for exactly
    // where that split happens). `excludedTiles` (rare, defaults to
    // empty): tiles that are not merely hidden but are not part of THIS
    // round's play at all -- e.g. OneVsOneVsOne's removed 0-0 (see
    // Dealer::excludedTilesForMode). Different from otherKnownTiles on
    // purpose: those are tiles whose LOCATION is known (the chain, a
    // revealed pair); these have no location because they were never
    // dealt to anyone or placed anywhere. Both end up equally
    // "untracked" below, but conflating the two here would misdescribe
    // what actually happened to the tile to any future reader of a
    // constructed BeliefState.
    //
    // Every tile that is neither known nor already identified starts
    // tracked, with its initial distribution set exactly proportional to
    // each location's share of the total unseen pool -- the direct
    // combinatorial consequence of a uniformly random deal (see
    // EntropySource), not an assumption layered on top of it.
    //
    // Precondition, asserted: the number of tiles that end up tracked
    // (28 minus known minus already-identified minus excluded) must
    // exactly equal the sum of locationCounts -- every unseen tile
    // accounted for by exactly one location's count, none missing or
    // double counted.
    BeliefState(const std::vector<DominoTile>& myKnownTiles,
                const std::vector<DominoTile>& otherKnownTiles,
                const std::map<int, int>& locationCounts,
                const std::vector<DominoTile>& excludedTiles = {});

    // Whether `tile` is still tracked (uncertain) at all.
    bool isTracked(DominoTile tile) const;

    // Probability that `tile` is in `location`, always normalized
    // against this tile's own current total across every location it
    // could occupy -- 0 if `tile` isn't tracked (known tiles have no
    // meaningful probability, not an undefined one).
    double probability(DominoTile tile, int location) const;

    // Sum of probability(t, location) across every currently-tracked
    // tile. Exact and equal to that location's true known count
    // immediately after construction or after applyOpponentDraw; only
    // approximately equal after markTileKnown (see class-level note).
    // Exposed directly so tests -- and later, diagnostics -- can verify
    // this rather than trusting it silently.
    double totalProbabilityMass(int location) const;

    // `tile` has become fully known to be in `location` (played, drawn
    // by the belief-holder, or a locked-boneyard pair just revealed).
    // Removes it from tracking and rescales the remaining tracked tiles'
    // shares of `location` so their aggregate matches `newLocationCount`
    // (that location's count AFTER this tile left it) -- see the
    // class-level note on why this is a documented approximation rather
    // than the exact joint solution.
    //
    // Precondition, asserted: tile is currently tracked.
    void markTileKnown(DominoTile tile, int location, int newLocationCount);

    // `drawingPlayer` has drawn one boneyard tile whose specific
    // identity is unknown to the belief-holder. Exact update, derived
    // from first principles and verified (see BeliefState.cpp) to
    // preserve both per-tile normalization and per-location
    // count-consistency exactly -- no approximation, unlike
    // markTileKnown.
    //
    // FIX-17 (audit F-11): a TOTAL function. Drawing with zero (or
    // FP-drift negative) boneyard mass is a defined no-op in every
    // build configuration -- the old debug assert vanished under NDEBUG
    // and left the division undefined. Callers should still never draw
    // from an empty yard; the no-op is safety netting, not license.
    void applyOpponentDraw(int drawingPlayer);

private:
    std::array<std::map<int, double>, DominoTile::kTileCount> m_distributions;
    std::array<bool, DominoTile::kTileCount> m_tracked{};
};

} // namespace isolyn
