#include "SearchEngine.hpp"
#include "EvaluationEngine.hpp"
#include "MoveExecutor.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "RulesEngine.hpp"
#include "SimulationEngine.hpp"
#include <cassert>
#include <limits>

namespace isolyn {

double SearchEngine::decisionCriterion(const std::vector<double>& valuePerPlayer, int playerIndex, GameMode mode) {
    if (mode != GameMode::TwoVsTwo) {
        return valuePerPlayer[static_cast<std::size_t>(playerIndex)];
    }
    auto team = RulesEngine::playersOnTeam(RulesEngine::teamIndexForPlayer(playerIndex));
    return valuePerPlayer[static_cast<std::size_t>(team.first)] + valuePerPlayer[static_cast<std::size_t>(team.second)];
}

std::vector<double> SearchEngine::searchNode(GameState& state, GameMode mode, int depthRemaining) {
    if (MoveGenerator::isPositionClosed(state)) {
        std::vector<double> values;
        for (int p = 0; p < state.playerCount(); ++p) {
            values.push_back(EvaluationEngine::evaluate(mode, state, p).total);
        }
        return values;
    }

    if (depthRemaining <= 0) {
        std::vector<double> values;
        for (int p = 0; p < state.playerCount(); ++p) {
            values.push_back(EvaluationEngine::evaluate(mode, state, p).total);
        }
        return values;
    }

    int player = state.currentPlayerIndex();

    // Deterministic forced-draw within this single, fully-known world --
    // no chance node needed, since the whole boneyard's contents are
    // already fixed by this determinization.
    std::vector<DominoTile> drawnForUndo;
    while (!MoveGenerator::hasAnyLegalMove(state, player) && state.boneyard().drawableCount() > 0) {
        drawnForUndo.push_back(state.drawTile(player));
    }

    std::vector<double> result;

    if (!MoveGenerator::hasAnyLegalMove(state, player)) {
        int next = (player + 1) % state.playerCount();
        state.setCurrentPlayerIndex(next);
        result = searchNode(state, mode, depthRemaining - 1);
        state.setCurrentPlayerIndex(player);
    } else {
        auto candidates = MoveGenerator::generate(state, player);
        assert(!candidates.empty());

        double bestCriterion = -std::numeric_limits<double>::infinity();
        std::vector<double> bestValues;

        for (const auto& move : candidates) {
            assert(MoveValidator::isLegal(state, player, move));
            auto applied = MoveExecutor::apply(state, player, move);

            std::vector<double> childValues;
            if (state.hand(player).empty()) {
                for (int p = 0; p < state.playerCount(); ++p) {
                    childValues.push_back(EvaluationEngine::evaluate(mode, state, p).total);
                }
            } else {
                int next = (player + 1) % state.playerCount();
                state.setCurrentPlayerIndex(next);
                childValues = searchNode(state, mode, depthRemaining - 1);
                state.setCurrentPlayerIndex(player);
            }

            double criterion = decisionCriterion(childValues, player, mode);
            if (criterion > bestCriterion) {
                bestCriterion = criterion;
                bestValues = childValues;
            }

            MoveExecutor::undo(state, applied);
        }

        result = bestValues;
    }

    for (auto it = drawnForUndo.rbegin(); it != drawnForUndo.rend(); ++it) {
        state.undoDrawTile(player, *it);
    }

    return result;
}

SearchDecision SearchEngine::chooseBestMove(const GameState& state, const BeliefState& belief, GameMode mode,
                                             const Config& config, std::mt19937_64& rng,
                                             const std::atomic<bool>* cancelRequested) {
    int player = state.currentPlayerIndex();
    auto candidates = MoveGenerator::generate(state, player);
    assert(!candidates.empty() && "chooseBestMove requires the current player to already have a legal move");

    std::vector<std::vector<double>> accumulated(candidates.size(), std::vector<double>(static_cast<std::size_t>(state.playerCount()), 0.0));

    int samplesCompleted = 0;
    for (int sample = 0; sample < config.determinizationCount; ++sample) {
        // Checked BEFORE starting each sample, never mid-sample: `state`
        // itself is never touched in this function (only local copies
        // `world`/`trial` are), so declining to start another sample
        // never leaves anything half-applied. Checking here (rather than
        // only after a sample completes) is what lets an
        // already-cancelled call return with samplesCompleted == 0
        // instead of always paying for at least one full sample first.
        if (cancelRequested != nullptr && cancelRequested->load(std::memory_order_relaxed)) {
            break;
        }

        GameState world = SimulationEngine::sampleDeterminizedState(state, belief, player, rng);

        for (std::size_t c = 0; c < candidates.size(); ++c) {
            GameState trial = world; // GameState is cheap to clone by design
            auto applied = MoveExecutor::apply(trial, player, candidates[c]);

            std::vector<double> values;
            if (trial.hand(player).empty()) {
                for (int p = 0; p < trial.playerCount(); ++p) {
                    values.push_back(EvaluationEngine::evaluate(mode, trial, p).total);
                }
            } else {
                int next = (player + 1) % trial.playerCount();
                trial.setCurrentPlayerIndex(next);
                values = searchNode(trial, mode, config.maxDepthPlies - 1);
            }

            for (std::size_t p = 0; p < values.size(); ++p) {
                accumulated[c][p] += values[p];
            }

            MoveExecutor::undo(trial, applied);
        }

        ++samplesCompleted;
    }

    if (samplesCompleted == 0) {
        // Cancelled before even one full sample completed. accumulated
        // is still all-zero -- averaging it would divide by zero. There
        // is no meaningful "best" candidate yet, so fall back to the
        // first legal one (valid and legal, never a fabricated/garbage
        // move) and report honestly via completed/samplesCompleted
        // rather than presenting this as a real evaluation.
        return SearchDecision{candidates[0],
                               std::vector<double>(static_cast<std::size_t>(state.playerCount()), 0.0),
                               false, 0};
    }

    std::size_t bestIndex = 0;
    double bestCriterion = -std::numeric_limits<double>::infinity();
    for (std::size_t c = 0; c < candidates.size(); ++c) {
        for (double& v : accumulated[c]) v /= samplesCompleted;
        double criterion = decisionCriterion(accumulated[c], player, mode);
        if (criterion > bestCriterion) {
            bestCriterion = criterion;
            bestIndex = c;
        }
    }

    bool completed = (samplesCompleted == config.determinizationCount);
    return SearchDecision{candidates[bestIndex], accumulated[bestIndex], completed, samplesCompleted};
}

} // namespace isolyn
