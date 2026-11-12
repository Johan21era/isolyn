#pragma once
#include <atomic>
#include <cstdint>
#include <random>
#include <vector>
#include "BeliefState.hpp"
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
};

class SearchEngine {
public:
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
