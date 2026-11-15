#pragma once
#include <atomic>
#include <cstdint>
#include <random>
#include <vector>
#include "BeliefState.hpp"
#include "EvaluationEngine.hpp"
#include "GameMode.hpp"
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

struct SearchDecision {
    Move move;

    // One entry per player, EvaluationEngine score, averaged across every
    // sampled determinization completed for the chosen move. This is the
    // evaluator's raw vector; search may add a terminal utility internally
    // (a completed win must outrank the one-tile win-threat heuristic), but
    // that utility is deliberately not reported as an evaluation component.
    std::vector<double> expectedValuePerPlayer;

    // True iff every configured determinization sample was evaluated at
    // the depth that produced this result. A time/cancel stop may leave
    // depthReached below maxDepthPlies; callers that care about depth
    // should inspect it rather than treating this as a full-strength run.
    bool completed = true;

    // How many determinization samples ran for the reported result.
    int samplesCompleted = 0;

    // Deepest fully completed iterative-deepening depth.
    int depthReached = 0;

    // Instrumentation for strength/performance work. These are diagnostic
    // only and never affect move selection.
    std::uint64_t nodesVisited = 0;
    std::uint64_t transpositionHits = 0;
    bool exactEndgame = false;

    // True when the chosen action is a voluntary draw rather than a placement.
    // `move` is then a legal placeholder and must NOT be played: callers must
    // apply the draw and leave the same player to move, because a draw does not
    // consume the turn (MatchController::voluntaryDraw).
    bool isDraw = false;
};

// How per-candidate results from different sampled worlds are combined into one
// decision.
//
// Determinization search is only expected-value-optimal when the belief state
// and the evaluation are both exact. Neither is true here, so the aggregation
// rule is itself a strategic choice: averaging can prefer a move that is
// mediocre in every world in which it is actually played, which is the classic
// strategy-fusion failure of perfect-information Monte-Carlo search. The
// alternatives below are cheap -- every candidate is already evaluated in every
// sampled world -- and are measured rather than assumed.
enum class RootAggregation {
    Mean,        // expected value under the sampled belief (the original rule)
    Maximin,     // worst sampled world: robust to a single bad world
    TrimmedMean, // drop the worst quartile of worlds, then average
    WinCount,    // how many worlds this candidate wins outright
};

class SearchEngine {
public:
    // The rulebook allows unlimited voluntary draws in a turn. A standard
    // double-six set can never supply more than 28 tiles; this is a validated
    // bound for callers that widen the root decision, not a cap on the live
    // session (which has no numeric limit). The clock remains the real limiter.
    static constexpr int kUnlimitedVoluntaryDraws = 64;

    struct Config {
        // Iterative deepening stops at this depth. The old engine used a
        // single fixed depth; retaining a default of 4 preserves the
        // existing bridge/UI contract while allowing callers to go deeper.
        int maxDepthPlies = 4;
        int determinizationCount = 20;

        // 0 means no wall-clock cap. Positive values are a cooperative
        // budget checked inside the search; the best fully completed
        // depth is returned when the budget expires.
        int timeLimitMs = 0;

        // Late endgame: once the boneyard is empty and at most this many
        // tiles remain in all hands, keep searching to the terminal
        // instead of stopping at a heuristic horizon. This is an exact
        // solver for the sampled perfect-information world, not a
        // heuristic extension. 0 disables it.
        int endgameTileLimit = 8;

        // Kept as an explicit switch so callers can compare the new
        // alpha-beta path against a full-width baseline.
        bool useAlphaBeta = true;

        // PVS/LMR for deep tiers. Off by default: this is an experiment whose
        // effect is measured, and the bridge enables it only for the two
        // deep-search profiles (maxDepthPlies >= 24).
        bool useSelectiveSearch = false;

        // Worker threads used to evaluate determinization samples in
        // parallel. 0 = automatic (hardware concurrency, capped by
        // determinizationCount), 1 = the original single-threaded path.
        //
        // Samples are assigned to workers by a fixed stride, and worlds are
        // still sampled sequentially from the caller's RNG, so a given seed
        // and worker count reproduce the same decision. Each worker owns its
        // own transposition table, killers and history -- none of that state
        // is shared across threads, so there is no lock on the hot path.
        int workerThreads = 0;

        // Root move selection across sampled worlds. See RootAggregation.
        RootAggregation rootAggregation = RootAggregation::Mean;

        // Evaluation weights used at every leaf. Defaults are the hand-tuned
        // ones; exposing them here is what makes component ablation and
        // calibration measurable instead of theoretical.
        EvaluationWeights weights{};

        // Voluntary draws a player may consider AT THIS DECISION. 0 disables the
        // option; kUnlimitedVoluntaryDraws is the rulebook-compliant analysis
        // setting. A draw does not consume the turn, so its continuation keeps
        // the same player to move and must not be negated. Live play is not
        // capped: after a draw the same player can choose again, and the
        // engine re-searches that new decision.
        int maxVoluntaryDraws = 0;
    };

    // Precondition: it is currently a player's turn to choose a move
    // (any forced-draw sequence at the root has already been resolved --
    // exactly as real play does via MatchController -- before this is
    // called).
    //
    // cancelRequested is an optional, caller-owned cooperative
    // cancellation flag, checked at the root and periodically inside the
    // recursive search. A cancelled call still returns a genuinely legal
    // move, never fabricated state; samplesCompleted == 0 means no real
    // analysis happened.
    static SearchDecision chooseBestMove(const GameState& state,
                                         const BeliefState& belief,
                                         GameMode mode,
                                         const Config& config,
                                         std::mt19937_64& rng,
                                         const std::atomic<bool>* cancelRequested = nullptr);
};

} // namespace isolyn
