#pragma once
#include <array>
#include "GameState.hpp"
#include "GameMode.hpp"

namespace isolyn {

// A breakdown of an evaluation, one entry per component, so a decision
// can be explained rather than just producing an opaque final number
// (Concept Spec's Evaluation Philosophy: every move's evaluation must be
// explainable, never "felt right").
//
// The first four components are the original hand-written signals. The
// remaining four are the strength layer added in this pass:
//   winThreat   -- an immediate Domino win is available to a participant
//   pipControl  -- how many tiles in hand match either exposed chain end
//   tempo       -- whose turn/team is currently acting
//   teamSupport -- in 2v2, the partner's mobility (partnership awareness)
//
// All eight components are deliberately separate and independently
// tunable. EvaluationWeights below is the calibration seam: a future
// self-play trainer can replace the defaults without changing search or
// any caller.
struct EvaluationBreakdown {
    double mobility = 0.0;
    double blocking = 0.0;
    double expectedValue = 0.0;
    // Only meaningful when the evaluated position is actually Closed;
    // zero otherwise.
    double closingOpportunity = 0.0;

    double winThreat = 0.0;
    double pipControl = 0.0;
    double tempo = 0.0;
    double teamSupport = 0.0;

    double total = 0.0;
};

// Defaults are hand-tuned from the rules/strategy notes, not claimed to
// be statistically calibrated. They are deliberately kept in one place
// so self-play can replace them with measured values later.
struct EvaluationWeights {
    double mobility = 1.0;
    double blocking = 1.0;
    double expectedValue = 1.0;
    double closingOpportunity = 1.0;
    double winThreat = 1.0;
    double pipControl = 0.5;
    double tempo = 0.1;
    // Partnership awareness. Hand-set at 0.25 until 2026-11-14; raised to 24.0
    // after a measured 2v2 sweep (2 -> +12.7, 6 -> +15.3, 12 -> +17.9,
    // 24 -> +22.3, 48 -> +22.7, 96 -> +22.3 Elo against the old default, 3,000
    // rounds each, then replicated at a second seed: +16.2 [+3.8,+28.7]).
    //
    // The term is `0.25 * team mobility` and is zero outside 2v2, so this
    // weight cannot affect 1v1 or 1v1v1 -- confirmed by a 1v1 control that
    // scored -1.0 Elo [-16.3,+14.2]. See docs/research/EXPERIMENT_REGISTRY.md
    // (E-023). Do not change it without re-running the 2v2 sweep: the previous
    // default made the engine's only partnership signal worth ~6% of one
    // player's mobility, which is why 5x more search bought nothing in 2v2.
    double teamSupport = 24.0;
};

// A fixed-size result for the search leaf path. Keeping the values inline
// avoids one heap allocation per player; `playerCount` tells callers how many
// entries are meaningful.
struct EvaluationTotals {
    std::array<double, 4> totals{};
    int playerCount = 0;
};

// Combines the independently-testable heuristic components into one
// evaluation, for a specific player, of a specific (already concrete,
// already determinized) GameState.
//
// Deliberately does NOT know about hidden information, belief states, or
// multiple determinizations, and needs no BeliefState/ProbabilityEngine
// dependency to work correctly: when SearchEngine calls this, it does so
// once per sampled hidden-tile guess (a determinization), and within any
// one such guess every hand value genuinely is known -- to that simulated
// world, not to the real, still-uncertain game. Averaging this engine's
// output across many different determinizations is what turns per-sample
// "known" values into a genuine expected-value-under-uncertainty estimate
// -- that averaging is SearchEngine's responsibility, one level up.
class EvaluationEngine {
public:
    // Legacy named constants retained for callers/tests that referenced
    // the original four-component contract. New code should use
    // EvaluationWeights.
    static constexpr double kMobilityWeight = 1.0;
    static constexpr double kBlockingWeight = 1.0;
    static constexpr double kExpectedValueWeight = 1.0;
    static constexpr double kClosingOpportunityWeight = 1.0;

    // Closing-opportunity scoring activates only when `state` is itself
    // a Closed position (MoveGenerator::isPositionClosed), and correctly
    // combines partners' hand values for 2v2 via RulesEngine's
    // team-index helpers before scoring -- team scoring, not individual
    // scoring, is what actually applies in that mode.
    static EvaluationBreakdown evaluate(GameMode mode,
                                        const GameState& state,
                                        int playerIndex,
                                        const EvaluationWeights& weights = EvaluationWeights{});

    // Computes every player's total from one pass over the state. Search uses
    // this at leaves so mobility, blocking, threat, closed scoring, and 2v2
    // team support are not recomputed once per player. The totals are exactly
    // the `total` fields the per-player API would return.
    static EvaluationTotals evaluateAll(GameMode mode,
                                        const GameState& state,
                                        const EvaluationWeights& weights = EvaluationWeights{});

    // Same totals with the caller's already-computed closed-position fact.
    // Closed internal search nodes use this after their early-termination
    // check; horizon leaves use evaluateAll, which derives Closed from the
    // mobility it already computes.
    static EvaluationTotals evaluateAllWithClosed(
        GameMode mode,
        const GameState& state,
        bool positionClosed,
        const EvaluationWeights& weights = EvaluationWeights{});
};

} // namespace isolyn
