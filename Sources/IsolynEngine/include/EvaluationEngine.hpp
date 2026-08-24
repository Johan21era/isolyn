#pragma once
#include "GameState.hpp"
#include "GameMode.hpp"

namespace isolyn {

// A breakdown of an evaluation, one entry per component, so a decision
// can be explained rather than just producing an opaque final number
// (Concept Spec's Evaluation Philosophy: every move's evaluation must be
// explainable, never "felt right").
struct EvaluationBreakdown {
    double mobility;
    double blocking;
    double expectedValue;
    // Only meaningful when the evaluated position is actually Closed;
    // zero otherwise.
    double closingOpportunity;
    double total;
};

// Combines the independently-testable heuristic components into one
// evaluation, for a specific player, of a specific (already concrete,
// already determinized) GameState.
//
// Deliberately does NOT know about hidden information, belief states, or
// multiple determinizations, and needs no BeliefState/ProbabilityEngine
// dependency to work correctly: when SearchEngine eventually calls this,
// it will do so once per sampled hidden-tile guess (a determinization),
// and within any one such guess every hand value genuinely is known --
// to that simulated world, not to the real, still-uncertain game.
// Averaging this engine's output across many different determinizations
// is what turns per-sample "known" values into a genuine
// expected-value-under-uncertainty estimate -- that averaging is
// SearchEngine's responsibility, one level up, not this class's. This is
// what makes EvaluationEngine safe to build before BeliefState exists at
// all.
//
// Weights below are placeholders, not calibrated constants -- Phase 7
// (profile, measure, tune against real search outcomes) is what
// eventually justifies real numbers here, not values picked in advance
// of any evidence.
class EvaluationEngine {
public:
    static constexpr double kMobilityWeight = 1.0;
    static constexpr double kBlockingWeight = 1.0;
    static constexpr double kExpectedValueWeight = 1.0;
    static constexpr double kClosingOpportunityWeight = 1.0;

    // Closing-opportunity scoring activates only when `state` is itself
    // a Closed position (MoveGenerator::isPositionClosed), and correctly
    // combines partners' hand values for 2v2 via RulesEngine's
    // team-index helpers before scoring -- team scoring, not individual
    // scoring, is what actually applies in that mode.
    static EvaluationBreakdown evaluate(GameMode mode, const GameState& state, int playerIndex);
};

} // namespace isolyn
