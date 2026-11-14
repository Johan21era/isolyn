#pragma once
#include "BeliefState.hpp"
#include "GameState.hpp"

namespace isolyn {

// The bridge between GameState (deterministic, fully-known-to-the-engine
// state) and BeliefState (one player's uncertain view of it), plus the
// aggregate queries built on top of a BeliefState that go beyond
// single-tile lookups. This is deliberately where GameState dependency
// lives -- BeliefState itself stays fully decoupled and testable
// standalone; this class is the necessary seam between the two worlds.
//
// Extension point, stated explicitly rather than left implicit: Concept
// Spec's Behavioral Analysis calls for observing DECISIONS (hesitation,
// declining to draw, ignored closing opportunities), not just tile
// movements. None of that is implemented here -- doing so rigorously
// needs a calibrated likelihood model (how much should hesitation
// actually shift a belief, and why that number rather than another),
// which doesn't exist yet and would otherwise be exactly the "arbitrary
// probability" the Concept Spec explicitly forbids. The observe*()
// methods below are structured so a future observeHesitation()/
// observeDeclinedDraw()/etc. could be added as another sibling method
// without restructuring anything else here -- the extension point is
// real, the calibrated math behind it isn't, and this class does not
// pretend otherwise.
class ProbabilityEngine {
public:
    // Builds a fresh BeliefState for `believerIndex`'s perspective of
    // `state`: their own hand and every tile visible on the chain are
    // fully known and excluded from tracking; each other player's hand
    // size and the boneyard's full remaining size become locationCounts.
    // The locked pair is deliberately NOT treated as known (R-17): it is
    // part of the boneyard's uncertainty, so the sampler may place any
    // unseen identities in those two unreachable slots.
    static BeliefState constructFromGameState(const GameState& state, int believerIndex);

    // `tile` was just played by `playerIndex`, confirming (to anyone who
    // didn't already know for certain) that it had been in their hand.
    // Reads playerIndex's new hand size directly from `stateAfter`.
    static void observePlay(BeliefState& belief, const GameState& stateAfter, int playerIndex, DominoTile tile);

    // `drawingPlayer` drew one boneyard tile of unknown identity.
    static void observeDraw(BeliefState& belief, const GameState& stateAfter, int drawingPlayer);

    // Direct per-tile lookup, exposed here too so callers can use
    // ProbabilityEngine as the single entry point rather than needing
    // BeliefState's own lower-level API as well.
    static double probabilityHoldsTile(const BeliefState& belief, int playerIndex, DominoTile tile);

    // Sum, over every tile BeliefState still tracks as uncertain, of
    // (probability it's in playerIndex's hand) x (its point value). Does
    // not include any tiles known by some other means to be in that hand
    // -- BeliefState discards a tile's history once it becomes known, so
    // it has nothing to attribute a specific known location to; a caller
    // with that information must add it separately.
    static double expectedRemainingValue(const BeliefState& belief, int playerIndex);

    // Probability that playerIndex holds AT LEAST minimumCount of the
    // (at most 7) tiles containing pipValue -- a direct, computable form
    // of the "missing a set" concept from docs/design/STRATEGY_NOTES.md's 2v2
    // section (5+ including the double = not missing). Computed via the
    // Poisson binomial distribution: treats each relevant tile's
    // membership as an independent Bernoulli trial at its own marginal
    // probability, which is an approximation (true membership is
    // correlated through the hand-size count constraints discussed in
    // BeliefState's own documentation) but a standard, well-defined one,
    // not an arbitrary heuristic -- and, at 7 or fewer trials, cheap to
    // compute exactly via dynamic programming rather than needing
    // sampling.
    static double probabilityHoldsAtLeast(const BeliefState& belief, int playerIndex, int pipValue, int minimumCount);
};

} // namespace isolyn
