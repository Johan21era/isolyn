#pragma once
#include <atomic>
#include <random>
#include <vector>
#include "BeliefState.hpp"
#include "GameMode.hpp"
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

struct SearchDecision {
    Move move;
    // One entry per player, EvaluationEngine score, averaged across
    // every sampled determinization actually completed for the CHOSEN
    // move (see samplesCompleted -- NOT always config.determinizationCount,
    // see cancelRequested below).
    std::vector<double> expectedValuePerPlayer;

    // True iff every configured determinization sample was evaluated.
    // False means cancelRequested fired partway through (see
    // chooseBestMove below) -- move/expectedValuePerPlayer still reflect
    // a genuine, honestly-computed evaluation over whatever samples DID
    // complete (never fabricated, never garbage), just lower-confidence
    // than a full run. Callers that care about that distinction should
    // surface it rather than silently presenting a cancelled analysis
    // with the same confidence as a completed one.
    bool completed = true;

    // How many of config.determinizationCount samples actually ran.
    // Always determinizationCount when completed is true. Can be 0 if
    // cancellation fired before the first sample finished -- in that
    // case `move` falls back to the first legal candidate (a valid,
    // legal move, but NOT a meaningful choice) and every
    // expectedValuePerPlayer entry is 0.0. Callers must treat
    // samplesCompleted == 0 as "no real analysis happened" and discard
    // the result rather than displaying it.
    int samplesCompleted = 0;
};

class SearchEngine {
public:
    struct Config {
        int maxDepthPlies = 4;
        int determinizationCount = 20;
    };

    // Precondition: it is currently a player's turn to choose a move
    // (any forced-draw sequence at the root has already been resolved --
    // exactly as real play does via MatchController -- before this is
    // called).
    //
    // cancelRequested is an optional, caller-owned cooperative
    // cancellation flag, checked once before EACH determinization sample
    // begins -- including before the very first one, so an
    // already-cancelled call returns immediately with samplesCompleted
    // == 0 rather than always paying for at least one full sample first
    // (NOT checked inside the deeper recursive searchNode() calls a
    // sample makes -- that would add a check to the hottest,
    // most-recursive path for a responsiveness gain finer than "one
    // sample" is ever likely to matter in practice). Passing nullptr
    // (the default) disables this entirely and reproduces the exact
    // prior behavior/signature for every existing call site -- this
    // parameter is purely additive. A sample already in progress when
    // cancellation fires always runs to completion and is fully
    // reflected in the result before the next check happens -- state
    // mutated by MoveExecutor within a sample is always fully unwound
    // before that sample's contribution is counted, so a cancelled call
    // can never return with `state` left mutated, and never discards a
    // sample's work partway through. This does not stop the C++
    // computation any faster than "finish whichever sample is already
    // running" -- it does not reach into searchNode to abort a
    // half-finished recursive evaluation. Ownership: the flag itself is
    // allocated and destroyed by the caller; this function only ever
    // reads it (relaxed loads), never writes it, and never retains the
    // pointer past this call returning.
    static SearchDecision chooseBestMove(const GameState& state, const BeliefState& belief, GameMode mode,
                                          const Config& config, std::mt19937_64& rng,
                                          const std::atomic<bool>* cancelRequested = nullptr);

private:
    // Mutates `state` via MoveExecutor and GameState's own draw/undo
    // machinery, always restoring it exactly before returning.
    static std::vector<double> searchNode(GameState& state, GameMode mode, int depthRemaining);

    // The value a player is actually maximizing at an internal node:
    // their own EvaluationEngine score for 1v1/1v1v1, or their own score
    // PLUS their partner's for 2v2.
    static double decisionCriterion(const std::vector<double>& valuePerPlayer, int playerIndex, GameMode mode);
};

} // namespace isolyn
