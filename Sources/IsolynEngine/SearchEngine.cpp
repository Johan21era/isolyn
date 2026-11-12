#include "SearchEngine.hpp"
#include "EvaluationEngine.hpp"
#include "MoveExecutor.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "RulesEngine.hpp"
#include "SimulationEngine.hpp"

#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <limits>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

namespace isolyn {

namespace {

constexpr double kInfinity = std::numeric_limits<double>::infinity();
constexpr std::size_t kMaxTTEntries = 250000;
constexpr int kMaxHistoryPlayers = 4;
constexpr int kMoveCodeCount = DominoTile::kTileCount * 2;
constexpr int kKillerSlots = 64;

// EvaluationEngine treats an empty hand as a zero-valued completed round
// for reporting purposes. Search needs a stronger terminal signal: a real
// Domino win must outrank the +1000 "one playable tile" heuristic threat,
// or a bounded search can prefer preserving that threat over winning now.
// The opponent's pips are still present in the raw evaluation, so a larger
// losing hand remains more valuable among winning lines.
constexpr double kTerminalWinScore = 2000.0;

int sideCode(GameState::ChainSide side) {
    return side == GameState::ChainSide::Left ? 0 : 1;
}

int moveCode(const Move& move) {
    return move.tile.index() * 2 + sideCode(move.side);
}

struct RawEvaluation {
    std::array<double, 4> values{};
    std::uint8_t count = 0;

    bool empty() const { return count == 0; }
    std::size_t size() const { return count; }
    double& operator[](std::size_t index) { return values[index]; }
    double operator[](std::size_t index) const { return values[index]; }
};

RawEvaluation evaluateAll(GameMode mode, const GameState& state) {
    const EvaluationTotals totals = EvaluationEngine::evaluateAll(mode, state);
    RawEvaluation raw;
    raw.values = totals.totals;
    raw.count = static_cast<std::uint8_t>(totals.playerCount);
    return raw;
}

double relativeScore(const RawEvaluation& raw, int playerIndex, GameMode mode) {
    if (mode == GameMode::TwoVsTwo) {
        const int team = RulesEngine::teamIndexForPlayer(playerIndex);
        const auto mine = RulesEngine::playersOnTeam(team);
        const auto theirs = RulesEngine::playersOnTeam(1 - team);
        return (raw[static_cast<std::size_t>(mine.first)] + raw[static_cast<std::size_t>(mine.second)])
             - (raw[static_cast<std::size_t>(theirs.first)] + raw[static_cast<std::size_t>(theirs.second)]);
    }
    if (mode == GameMode::OneVsOne) {
        return raw[static_cast<std::size_t>(playerIndex)] -
               raw[static_cast<std::size_t>(1 - playerIndex)];
    }
    return raw[static_cast<std::size_t>(playerIndex)];
}

double rootCriterion(const RawEvaluation& raw, int playerIndex, GameMode mode) {
    if (mode == GameMode::OneVsOneVsOne) {
        return raw[static_cast<std::size_t>(playerIndex)];
    }
    return relativeScore(raw, playerIndex, mode);
}

// Root accumulation still uses vectors because it is once per candidate and
// determinization; this adapter keeps the hot search path allocation-free.
double rootCriterion(const std::vector<double>& raw, int playerIndex, GameMode mode) {
    RawEvaluation converted;
    converted.count = static_cast<std::uint8_t>(raw.size());
    std::copy(raw.begin(), raw.end(), converted.values.begin());
    return rootCriterion(converted, playerIndex, mode);
}

int totalHandTiles(const GameState& state) {
    int total = 0;
    for (int p = 0; p < state.playerCount(); ++p) {
        total += static_cast<int>(state.hand(p).size());
    }
    return total;
}

enum class TTFlag { Exact, LowerBound, UpperBound };

struct TTEntry {
    int depth = -1;
    double score = 0.0;
    RawEvaluation raw;
    int bestCode = -1;
    TTFlag flag = TTFlag::Exact;
};

struct SearchContext {
    GameMode mode = GameMode::OneVsOne;
    int endgameTileLimit = 0;
    bool useAlphaBeta = true;
    bool hasDeadline = false;
    std::chrono::steady_clock::time_point deadline{};
    const std::atomic<bool>* cancelRequested = nullptr;

    std::uint64_t nodes = 0;
    std::uint64_t ttHits = 0;
    bool aborted = false;
    bool exactEndgameUsed = false;

    std::unordered_map<std::uint64_t, TTEntry> tt;
    std::array<std::array<int, 2>, kKillerSlots> killers{};
    std::array<std::array<int, kMoveCodeCount>, kMaxHistoryPlayers> history{};
};

struct SearchValue {
    double score = 0.0;
    RawEvaluation raw;
};

struct DepthResult {
    Move move;
    std::vector<double> values;
    int depth = 0;
    int samples = 0;
};

bool shouldStop(SearchContext& context) {
    if (context.aborted) return true;
    if (context.cancelRequested != nullptr &&
        context.cancelRequested->load(std::memory_order_relaxed)) {
        context.aborted = true;
        return true;
    }
    if (context.hasDeadline && std::chrono::steady_clock::now() >= context.deadline) {
        context.aborted = true;
        return true;
    }
    return false;
}

bool tick(SearchContext& context) {
    ++context.nodes;
    // Checking the clock on every recursive call would cost more than the
    // search itself; 256-node granularity keeps cancellation responsive
    // without turning time management into the dominant cost.
    if ((context.nodes & 0xFFULL) == 0) return shouldStop(context);
    return context.aborted;
}

bool isExactEndgame(SearchContext& context, const GameState& state) {
    if (context.mode == GameMode::OneVsOneVsOne) return false;
    if (context.endgameTileLimit <= 0) return false;
    if (state.boneyard().drawableCount() != 0) return false;
    if (totalHandTiles(state) > context.endgameTileLimit) return false;
    context.exactEndgameUsed = true;
    return true;
}

void recordCutoff(SearchContext& context, int ply, int playerIndex, const Move& move) {
    const int code = moveCode(move);
    auto& killers = context.killers[static_cast<std::size_t>(ply) % kKillerSlots];
    if (killers[0] != code) {
        killers[1] = killers[0];
        killers[0] = code;
    }
    if (playerIndex >= 0 && playerIndex < kMaxHistoryPlayers &&
        code >= 0 && code < kMoveCodeCount) {
        ++context.history[static_cast<std::size_t>(playerIndex)][static_cast<std::size_t>(code)];
    }
}

void orderMoves(Move* moves,
                std::size_t count,
                const SearchContext& context,
                int playerIndex,
                int ply,
                int ttBestCode) {
    const auto& killers = context.killers[static_cast<std::size_t>(ply) % kKillerSlots];
    auto moveScore = [&](const Move& move) -> long long {
        const int code = moveCode(move);
        if (code == ttBestCode) return 1'000'000'000LL;
        if (code == killers[0]) return 900'000'000LL;
        if (code == killers[1]) return 800'000'000LL;

        long long history = 0;
        if (playerIndex >= 0 && playerIndex < kMaxHistoryPlayers &&
            code >= 0 && code < kMoveCodeCount) {
            history = context.history[static_cast<std::size_t>(playerIndex)]
                                      [static_cast<std::size_t>(code)];
        }
        // Shedding high-value tiles is a useful tie-breaker, not a rule:
        // it mainly improves alpha-beta cutoffs before the first exact
        // transposition entries exist.
        return history * 1000LL + static_cast<long long>(move.tile.value()) * 10LL +
               (move.side == GameState::ChainSide::Left ? 1LL : 0LL);
    };

    std::sort(moves, moves + count, [&](const Move& a, const Move& b) {
        return moveScore(a) > moveScore(b);
    });
}

std::vector<DominoTile> resolveForcedDraws(GameState& state, int playerIndex) {
    std::vector<DominoTile> drawn;
    while (!MoveGenerator::hasAnyLegalMove(state, playerIndex) &&
           state.boneyard().drawableCount() > 0) {
        drawn.push_back(state.drawTile(playerIndex));
    }
    return drawn;
}

void undoDraws(GameState& state, int playerIndex, const std::vector<DominoTile>& drawn) {
    for (auto it = drawn.rbegin(); it != drawn.rend(); ++it) {
        state.undoDrawTile(playerIndex, *it);
    }
}

SearchValue searchZeroSum(GameState& state,
                          int depthRemaining,
                          double alpha,
                          double beta,
                          SearchContext& context,
                          int ply) {
    if (tick(context)) return {};

    const int player = state.currentPlayerIndex();

    const bool closed = MoveGenerator::isPositionClosed(state);
    const bool exactEndgame = isExactEndgame(context, state);
    if (closed || (depthRemaining <= 0 && !exactEndgame)) {
        RawEvaluation raw = evaluateAll(context.mode, state);
        return SearchValue{relativeScore(raw, player, context.mode), raw};
    }

    std::vector<DominoTile> drawn = resolveForcedDraws(state, player);
    if (!MoveGenerator::hasAnyLegalMove(state, player)) {
        const int next = (player + 1) % state.playerCount();
        state.setCurrentPlayerIndex(next);
        // A pass/draw sequence still flips the side to move, so the
        // alpha-beta window must flip with it. Passing (alpha, beta)
        // unchanged here would make deeper cutoffs compare scores from
        // opposite perspectives.
        const double childAlpha = context.useAlphaBeta ? -beta : -kInfinity;
        const double childBeta = context.useAlphaBeta ? -alpha : kInfinity;
        SearchValue child = searchZeroSum(state, depthRemaining - 1, childAlpha, childBeta, context, ply);
        state.setCurrentPlayerIndex(player);
        undoDraws(state, player, drawn);
        if (context.aborted || child.raw.empty()) return {};
        return SearchValue{-child.score, child.raw};
    }

    const std::uint64_t key = state.hash();
    auto ttIt = context.tt.find(key);
    if (ttIt != context.tt.end() &&
        ttIt->second.depth >= depthRemaining &&
        ttIt->second.raw.size() == static_cast<std::size_t>(state.playerCount())) {
        const TTEntry& entry = ttIt->second;
        const bool usable = entry.flag == TTFlag::Exact ||
                            (entry.flag == TTFlag::LowerBound && entry.score >= beta) ||
                            (entry.flag == TTFlag::UpperBound && entry.score <= alpha);
        if (usable) {
            ++context.ttHits;
            SearchValue hit{entry.score, entry.raw};
            undoDraws(state, player, drawn);
            return hit;
        }
    }

    std::array<Move, MoveGenerator::kMaxMoves> candidates;
    const std::size_t candidateCount =
        MoveGenerator::generateInto(state, player, candidates);
    assert(candidateCount > 0);
    const int ttBest = ttIt != context.tt.end() ? ttIt->second.bestCode : -1;
    orderMoves(candidates.data(), candidateCount, context, player, ply, ttBest);

    double bestScore = -kInfinity;
    RawEvaluation bestRaw;
    int bestCode = -1;
    bool cutoff = false;
    const double originalAlpha = alpha;

    for (std::size_t candidateIndex = 0; candidateIndex < candidateCount; ++candidateIndex) {
        const Move& move = candidates[candidateIndex];
        if (tick(context)) break;
        assert(MoveValidator::isLegal(state, player, move));
        auto applied = MoveExecutor::apply(state, player, move);
        const bool emptied = state.hand(player).empty();

        SearchValue child;
        if (emptied) {
            child.raw = evaluateAll(context.mode, state);
            child.score = kTerminalWinScore + relativeScore(child.raw, player, context.mode);
        } else {
            const int next = (player + 1) % state.playerCount();
            state.setCurrentPlayerIndex(next);
            const double childAlpha = context.useAlphaBeta ? -beta : -kInfinity;
            const double childBeta = context.useAlphaBeta ? -alpha : kInfinity;
            child = searchZeroSum(state, depthRemaining - 1, childAlpha, childBeta, context, ply + 1);
            state.setCurrentPlayerIndex(player);
        }
        MoveExecutor::undo(state, applied);

        if (context.aborted || child.raw.empty()) break;

        const double score = emptied ? child.score : -child.score;
        if (score > bestScore) {
            bestScore = score;
            bestRaw = child.raw;
            bestCode = moveCode(move);
        }
        if (score > alpha) alpha = score;
        if (context.useAlphaBeta && alpha >= beta) {
            recordCutoff(context, ply, player, move);
            cutoff = true;
            break;
        }
    }

    undoDraws(state, player, drawn);
    if (context.aborted || bestCode < 0) return {};

    if (!bestRaw.empty()) {
        TTFlag flag = TTFlag::Exact;
        if (cutoff) flag = TTFlag::LowerBound;
        else if (bestScore <= originalAlpha) flag = TTFlag::UpperBound;
        if (context.tt.size() >= kMaxTTEntries) context.tt.clear();
        context.tt[key] = TTEntry{depthRemaining, bestScore, bestRaw, bestCode, flag};
    }
    return SearchValue{bestScore, bestRaw};
}

RawEvaluation searchMulti(GameState& state,
                          int depthRemaining,
                          SearchContext& context,
                          int ply) {
    if (tick(context)) return {};

    const int player = state.currentPlayerIndex();
    const bool closed = MoveGenerator::isPositionClosed(state);
    if (closed || depthRemaining <= 0) {
        return evaluateAll(context.mode, state);
    }

    std::vector<DominoTile> drawn = resolveForcedDraws(state, player);
    if (!MoveGenerator::hasAnyLegalMove(state, player)) {
        const int next = (player + 1) % state.playerCount();
        state.setCurrentPlayerIndex(next);
        RawEvaluation child = searchMulti(state, depthRemaining - 1, context, ply);
        state.setCurrentPlayerIndex(player);
        undoDraws(state, player, drawn);
        return child;
    }

    const std::uint64_t key = state.hash();
    auto ttIt = context.tt.find(key);
    if (ttIt != context.tt.end() &&
        ttIt->second.depth >= depthRemaining &&
        ttIt->second.raw.size() == static_cast<std::size_t>(state.playerCount())) {
        ++context.ttHits;
        RawEvaluation hit = ttIt->second.raw;
        undoDraws(state, player, drawn);
        return hit;
    }

    std::array<Move, MoveGenerator::kMaxMoves> candidates;
    const std::size_t candidateCount =
        MoveGenerator::generateInto(state, player, candidates);
    assert(candidateCount > 0);
    const int ttBest = ttIt != context.tt.end() ? ttIt->second.bestCode : -1;
    orderMoves(candidates.data(), candidateCount, context, player, ply, ttBest);

    double bestCriterion = -kInfinity;
    RawEvaluation bestRaw;
    int bestCode = -1;

    for (std::size_t candidateIndex = 0; candidateIndex < candidateCount; ++candidateIndex) {
        const Move& move = candidates[candidateIndex];
        if (tick(context)) break;
        assert(MoveValidator::isLegal(state, player, move));
        auto applied = MoveExecutor::apply(state, player, move);
        const bool emptied = state.hand(player).empty();

        RawEvaluation child;
        if (emptied) {
            child = evaluateAll(context.mode, state);
            child[static_cast<std::size_t>(player)] += kTerminalWinScore;
        } else {
            const int next = (player + 1) % state.playerCount();
            state.setCurrentPlayerIndex(next);
            child = searchMulti(state, depthRemaining - 1, context, ply + 1);
            state.setCurrentPlayerIndex(player);
        }
        MoveExecutor::undo(state, applied);

        if (context.aborted || child.empty()) break;

        const double criterion = child[static_cast<std::size_t>(player)];
        if (criterion > bestCriterion) {
            bestCriterion = criterion;
            bestRaw = child;
            bestCode = moveCode(move);
        }
    }

    undoDraws(state, player, drawn);
    if (context.aborted || bestCode < 0) return {};

    if (bestRaw.size() == static_cast<std::size_t>(state.playerCount())) {
        if (context.tt.size() >= kMaxTTEntries) context.tt.clear();
        context.tt[key] = TTEntry{depthRemaining, 0.0, bestRaw, bestCode, TTFlag::Exact};
    }
    return bestRaw;
}

} // namespace

SearchDecision SearchEngine::chooseBestMove(const GameState& state,
                                             const BeliefState& belief,
                                             GameMode mode,
                                             const Config& config,
                                             std::mt19937_64& rng,
                                             const std::atomic<bool>* cancelRequested) {
    const int player = state.currentPlayerIndex();
    std::vector<Move> candidates = MoveGenerator::generate(state, player);
    assert(!candidates.empty() && "chooseBestMove requires the current player to already have a legal move");

    const int playerCount = state.playerCount();
    SearchContext context;
    context.mode = mode;
    context.endgameTileLimit = config.endgameTileLimit;
    context.useAlphaBeta = config.useAlphaBeta;
    context.cancelRequested = cancelRequested;
    context.tt.reserve(1 << 14);

    const auto start = std::chrono::steady_clock::now();
    if (config.timeLimitMs > 0) {
        context.hasDeadline = true;
        context.deadline = start + std::chrono::milliseconds(config.timeLimitMs);
    }

    if (config.maxDepthPlies < 1 || config.determinizationCount < 1) {
        return SearchDecision{candidates[0],
                              std::vector<double>(static_cast<std::size_t>(playerCount), 0.0),
                              false,
                              0,
                              0,
                              0,
                              0,
                              false};
    }

    std::optional<DepthResult> bestResult;

    for (int depth = 1; depth <= config.maxDepthPlies; ++depth) {
        if (shouldStop(context)) break;

        std::vector<std::vector<double>> accumulated(
            candidates.size(),
            std::vector<double>(static_cast<std::size_t>(playerCount), 0.0));
        // Zero-sum modes must choose from the search score, not from a raw
        // vector that a transposition-table bound may have inherited from a
        // different line. The score is the value of the candidate in this
        // sampled world; averaging those values is the root expectation.
        std::vector<double> accumulatedScores(candidates.size(), 0.0);
        int samples = 0;
        bool abortedDepth = false;

        for (int sample = 0; sample < config.determinizationCount; ++sample) {
            if (shouldStop(context)) {
                abortedDepth = true;
                break;
            }

            GameState world = SimulationEngine::sampleDeterminizedState(state, belief, player, rng);

            for (std::size_t c = 0; c < candidates.size(); ++c) {
                if (shouldStop(context)) {
                    abortedDepth = true;
                    break;
                }

                GameState trial = world;
                auto applied = MoveExecutor::apply(trial, player, candidates[c]);
                const bool emptied = trial.hand(player).empty();

                RawEvaluation raw;
                double candidateScore = 0.0;
                if (emptied) {
                    raw = evaluateAll(mode, trial);
                    if (mode == GameMode::OneVsOneVsOne) {
                        raw[static_cast<std::size_t>(player)] += kTerminalWinScore;
                        candidateScore = raw[static_cast<std::size_t>(player)];
                    } else {
                        candidateScore = kTerminalWinScore + relativeScore(raw, player, mode);
                    }
                } else {
                    const int next = (player + 1) % playerCount;
                    trial.setCurrentPlayerIndex(next);
                    if (mode == GameMode::OneVsOneVsOne) {
                        raw = searchMulti(trial, depth - 1, context, 0);
                        if (!raw.empty()) {
                            candidateScore = raw[static_cast<std::size_t>(player)];
                        }
                    } else {
                        SearchValue child = searchZeroSum(trial, depth - 1, -kInfinity, kInfinity, context, 0);
                        raw = child.raw;
                        candidateScore = -child.score;
                    }
                    trial.setCurrentPlayerIndex(player);
                }
                MoveExecutor::undo(trial, applied);

                if (context.aborted || raw.size() != static_cast<std::size_t>(playerCount)) {
                    abortedDepth = true;
                    break;
                }

                for (int p = 0; p < playerCount; ++p) {
                    accumulated[c][static_cast<std::size_t>(p)] += raw[static_cast<std::size_t>(p)];
                }
                accumulatedScores[c] += candidateScore;
            }

            if (abortedDepth) break;
            ++samples;
        }

        // Only a complete depth is allowed to replace the previous result:
        // a partially sampled depth would make candidate averages
        // incomparable. A time stop therefore returns the last fully
        // completed depth, with depthReached making that explicit.
        if (!abortedDepth && samples == config.determinizationCount) {
            for (auto& values : accumulated) {
                for (double& value : values) value /= static_cast<double>(samples);
            }
            for (double& value : accumulatedScores) value /= static_cast<double>(samples);

            std::size_t bestIndex = 0;
            double bestCriterion = -kInfinity;
            for (std::size_t c = 0; c < accumulated.size(); ++c) {
                const double criterion = mode == GameMode::OneVsOneVsOne
                    ? rootCriterion(accumulated[c], player, mode)
                    : accumulatedScores[c];
                if (criterion > bestCriterion) {
                    bestCriterion = criterion;
                    bestIndex = c;
                }
            }

            bestResult = DepthResult{candidates[bestIndex], accumulated[bestIndex], depth, samples};
        }

        if (abortedDepth) break;
    }

    if (bestResult.has_value()) {
        return SearchDecision{bestResult->move,
                              bestResult->values,
                              bestResult->samples == config.determinizationCount,
                              bestResult->samples,
                              bestResult->depth,
                              context.nodes,
                              context.ttHits,
                              context.exactEndgameUsed};
    }

    return SearchDecision{candidates[0],
                          std::vector<double>(static_cast<std::size_t>(playerCount), 0.0),
                          false,
                          0,
                          0,
                          context.nodes,
                          context.ttHits,
                          context.exactEndgameUsed};
}

} // namespace isolyn
