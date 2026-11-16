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
#include <condition_variable>
#include <functional>
#include <mutex>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <thread>
#include <utility>
#include <vector>

namespace isolyn {

namespace {

constexpr double kInfinity = std::numeric_limits<double>::infinity();
// A search needs a small cache, not a 250k-node hash map. The master tier
// records only a few thousand hits across millions of nodes, so a fixed,
// four-way table keeps the useful entries while bounding memory per lane.
constexpr std::size_t kTTWays = 4;
constexpr int kMaxHistoryPlayers = 4;
constexpr int kMaxWorkers = 16;
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

// R-22: in a 1v1v1 survivor round the eliminated seat holds no tiles and
// must be skipped by search exactly as MatchController skips it in play.
// Every other mode has no empty mid-round hand, so this is the ordinary
// +1 rotation there.
int nextActivePlayer(const GameState& state, int player) {
    const int playerCount = state.playerCount();
    for (int step = 1; step <= playerCount; ++step) {
        const int candidate = (player + step) % playerCount;
        if (!state.hand(candidate).empty()) return candidate;
    }
    return player;
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

RawEvaluation evaluateAll(GameMode mode,
                          const GameState& state,
                          const EvaluationWeights& weights,
                          std::optional<bool> positionClosed = std::nullopt,
                          const EvaluationWeights* positionalWeights = nullptr) {
    const EvaluationTotals totals = positionClosed.has_value()
        ? EvaluationEngine::evaluateAllWithClosed(mode, state, *positionClosed, weights, positionalWeights)
        : EvaluationEngine::evaluateAll(mode, state, weights, positionalWeights);
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

enum class TTFlag : std::uint8_t { Exact, LowerBound, UpperBound };

// Compact entry with one generation stamp instead of an explicit empty key.
// A generation bump invalidates every entry without walking the storage, which
// matters because the table is reused across moves rather than allocated and
// zero-filled for every decision.
struct TTEntry {
    std::uint64_t key = 0;
    double score = 0.0;
    std::array<double, 4> values{};
    std::uint16_t generation = 0;
    std::int16_t depth = -1;
    std::int16_t bestCode = -1;
    TTFlag flag = TTFlag::Exact;
};

std::uint64_t mixTTKey(std::uint64_t key) noexcept {
    key ^= key >> 33;
    key *= 0xff51afd7ed558ccdULL;
    key ^= key >> 33;
    return key;
}

class TranspositionTable {
public:
    explicit TranspositionTable(std::size_t bucketCount)
        : m_bucketCount(bucketCount),
          m_bucketMask(bucketCount - 1),
          m_entries(bucketCount * kTTWays) {}

    std::size_t bucketCount() const noexcept { return m_bucketCount; }

    void beginSearch() noexcept {
        ++m_generation;
        if (m_generation == 0) {
            for (TTEntry& entry : m_entries) entry.generation = 0;
            m_generation = 1;
        }
    }

    TTEntry* find(std::uint64_t key) noexcept {
        const std::size_t first = bucketFor(key);
        for (std::size_t way = 0; way < kTTWays; ++way) {
            TTEntry& entry = m_entries[first + way];
            if (entry.generation != m_generation) return nullptr;
            if (entry.key == key) return &entry;
        }
        return nullptr;
    }

    void store(std::uint64_t key,
               int depth,
               double score,
               const RawEvaluation& raw,
               int bestCode,
               TTFlag flag) noexcept {
        const std::size_t first = bucketFor(key);
        TTEntry* victim = nullptr;
        for (std::size_t way = 0; way < kTTWays; ++way) {
            TTEntry& entry = m_entries[first + way];
            if (entry.generation != m_generation || entry.key == key) {
                victim = &entry;
                break;
            }
            if (victim == nullptr || entry.depth < victim->depth) victim = &entry;
        }
        victim->key = key;
        victim->depth = static_cast<std::int16_t>(depth);
        victim->score = score;
        victim->values = raw.values;
        victim->bestCode = static_cast<std::int16_t>(bestCode);
        victim->flag = flag;
        victim->generation = m_generation;
    }

private:
    std::size_t bucketFor(std::uint64_t key) const noexcept {
        return static_cast<std::size_t>(mixTTKey(key) & m_bucketMask) * kTTWays;
    }

    std::size_t m_bucketCount;
    std::size_t m_bucketMask;
    std::vector<TTEntry> m_entries;
    std::uint16_t m_generation = 0;
};

// Shallow tiers visit far fewer positions, so a full-size table would be
// mostly unused cache pollution. Grow the table with the configured depth and
// cap it at the master tier's proven size.
std::size_t ttBucketsForDepth(int maxDepthPlies) noexcept {
    const int depth = std::clamp(maxDepthPlies, 2, 5);
    return static_cast<std::size_t>(1) << (depth + 9);
}

struct SearchContext {
    GameMode mode = GameMode::OneVsOne;
    int endgameTileLimit = 0;
    bool useAlphaBeta = true;
    bool useSelectiveSearch = false;
    GameState::TranspositionKeyMode transpositionKeyMode =
        GameState::TranspositionKeyMode::FullHistory;
    bool hasDeadline = false;
    std::chrono::steady_clock::time_point deadline{};
    const std::atomic<bool>* cancelRequested = nullptr;
    // Set by any worker when it stops, so the remaining workers wind down
    // instead of finishing work whose result cannot be used.
    std::atomic<bool>* sharedAbort = nullptr;

    std::uint64_t nodes = 0;
    std::uint64_t ttHits = 0;
    bool aborted = false;
    bool exactEndgameUsed = false;

    EvaluationWeights weights{};
    const EvaluationWeights* positionalWeights = nullptr;
    int maxVoluntaryDraws = 0;
    TranspositionTable* tt = nullptr;
    bool tableStarted = false;
    std::array<std::array<int, 2>, kKillerSlots> killers{};
    std::array<std::array<int, kMoveCodeCount>, kMaxHistoryPlayers> history{};
};

void startTableIfNeeded(SearchContext& context, TranspositionTable& table) {
    if (context.tableStarted) return;
    context.tt = &table;
    context.tt->beginSearch();
    context.tableStarted = true;
}

RawEvaluation rawFromEntry(const TTEntry& entry, int playerCount) {
    RawEvaluation raw;
    raw.values = entry.values;
    raw.count = static_cast<std::uint8_t>(playerCount);
    return raw;
}

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
    if (context.sharedAbort != nullptr &&
        context.sharedAbort->load(std::memory_order_relaxed)) {
        context.aborted = true;
        return true;
    }
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

// A small persistent pool for root-sample parallelism.
//
// Spawning threads per depth made the parallel path only ~2x faster than the
// sequential one: eight spawns per depth, eight depths per move, hundreds of
// moves per game. This pool is created once per searching thread and reused
// for every depth, which removes that cost entirely.
class SamplePool {
public:
    explicit SamplePool(int size) : m_size(std::max(1, size)) {
        m_threads.reserve(static_cast<std::size_t>(m_size));
        for (int i = 0; i < m_size; ++i) {
            m_threads.emplace_back([this, i]() { workerLoop(i); });
        }
    }

    ~SamplePool() {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_stop = true;
        }
        m_start.notify_all();
        for (std::thread& thread : m_threads) thread.join();
    }

    SamplePool(const SamplePool&) = delete;
    SamplePool& operator=(const SamplePool&) = delete;

    int size() const { return m_size; }

    // Tables are owned by the pool and allocated only for lanes a search
    // actually uses. A thread_local table would reserve its full storage in
    // every pool thread even when the process runs one search lane.
    TranspositionTable& tableFor(int lane, std::size_t buckets) {
        auto& table = m_tables[static_cast<std::size_t>(lane)];
        if (!table || table->bucketCount() < buckets) {
            table = std::make_unique<TranspositionTable>(buckets);
        }
        return *table;
    }

    // Runs `task` on every worker and returns once all have finished.
    void run(const std::function<void(int)>& task) {
        if (m_size == 1) {
            task(0);
            return;
        }
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_task = &task;
            m_remaining = m_size;
            ++m_generation;
        }
        m_start.notify_all();
        std::unique_lock<std::mutex> lock(m_mutex);
        m_done.wait(lock, [this]() { return m_remaining == 0; });
    }

private:
    void workerLoop(int index) {
        int seen = 0;
        for (;;) {
            const std::function<void(int)>* task = nullptr;
            {
                std::unique_lock<std::mutex> lock(m_mutex);
                m_start.wait(lock, [this, &seen]() { return m_stop || m_generation != seen; });
                if (m_stop) return;
                seen = m_generation;
                task = m_task;
            }
            if (task != nullptr) (*task)(index);
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (--m_remaining == 0) m_done.notify_one();
            }
        }
    }

    int m_size = 1;
    std::vector<std::thread> m_threads;
    std::array<std::unique_ptr<TranspositionTable>, kMaxWorkers> m_tables{};
    std::mutex m_mutex;
    std::condition_variable m_start;
    std::condition_variable m_done;
    const std::function<void(int)>* m_task = nullptr;
    int m_remaining = 0;
    int m_generation = 0;
    bool m_stop = false;
};

// One pool per searching thread. A process-wide pool would be a data race the
// moment two searches overlap; a per-thread pool keeps every search
// self-contained and needs no lock outside the barrier itself.
SamplePool& searchPool() {
    thread_local SamplePool pool(static_cast<int>(std::max(1u, std::thread::hardware_concurrency())));
    return pool;
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

// R-18 for search nodes. The live match applies the mandatory draw when the
// turn passes; the search reaches the same position by setting the next
// player directly, so it must apply the identical rule at node entry and
// unwind it on every exit path (including leaf/closed/abort returns). The
// root itself is not touched: production roots have already passed through
// MatchController's turn transition, and drawing there could make a
// candidate tile that the caller does not actually hold.
struct OneDominoDrawGuard {
    GameState& state;
    int player;
    std::optional<DominoTile> tile;
    ~OneDominoDrawGuard() {
        if (tile) state.undoDrawTile(player, *tile);
    }
};

SearchValue searchZeroSum(GameState& state,
                          int depthRemaining,
                          double alpha,
                          double beta,
                          SearchContext& context,
                          int ply,
                          int drawsLeft) {
    if (tick(context)) return {};

    const int player = state.currentPlayerIndex();

    OneDominoDrawGuard oneDomino{state, player, std::nullopt};
    if (ply > 0) oneDomino.tile = state.enforceOneDominoRule();

    const bool exactEndgame = isExactEndgame(context, state);
    if (depthRemaining <= 0 && !exactEndgame) {
        // evaluateAll derives Closed from the mobility it already computes,
        // so a horizon leaf needs no separate all-player legality scan.
        RawEvaluation raw = evaluateAll(context.mode, state, context.weights, std::nullopt, context.positionalWeights);
        return SearchValue{relativeScore(raw, player, context.mode), raw};
    }

    const bool closed = MoveGenerator::isPositionClosed(state);
    if (closed) {
        RawEvaluation raw = evaluateAll(context.mode, state, context.weights, true, context.positionalWeights);
        return SearchValue{relativeScore(raw, player, context.mode), raw};
    }

    std::vector<DominoTile> drawn = resolveForcedDraws(state, player);
    if (!MoveGenerator::hasAnyLegalMove(state, player)) {
        const int next = nextActivePlayer(state, player);
        state.setCurrentPlayerIndex(next);
        // A pass/draw sequence still flips the side to move, so the
        // alpha-beta window must flip with it. Passing (alpha, beta)
        // unchanged here would make deeper cutoffs compare scores from
        // opposite perspectives.
        const double childAlpha = context.useAlphaBeta ? -beta : -kInfinity;
        const double childBeta = context.useAlphaBeta ? -alpha : kInfinity;
        SearchValue child = searchZeroSum(state, depthRemaining - 1, childAlpha, childBeta, context, ply, 0);
        state.setCurrentPlayerIndex(player);
        undoDraws(state, player, drawn);
        if (context.aborted || child.raw.empty()) return {};
        return SearchValue{-child.score, child.raw};
    }

    // Voluntary draw. Inside a determinized world the drawn tile is known
    // exactly, so the continuation is exact rather than an approximation. A
    // draw does not consume the turn: the same player is to move, so the score
    // is taken WITHOUT the negamax sign flip a placement gets.
    double drawScore = -kInfinity;
    RawEvaluation drawRaw;
    bool hasDrawOption = false;
    if (context.maxVoluntaryDraws > 0 && drawsLeft > 0 &&
        state.boneyard().drawableCount() > 0 && !state.chain().isEmpty()) {
        // A draw costs one ply of horizon here. Keeping depth constant instead
        // is the true cost model, but it re-enables draws after every placement
        // and the tree grows as 2^depth -- measured, and rejected as
        // unaffordable. The conservative model is kept and stated.
        const DominoTile drawnTile = state.drawTile(player);
        // One draw for this decision. A second draw is a new live decision
        // (the same player remains to move), so planning a chain of draws in
        // one tree only multiplies nodes and burns horizon without changing the
        // legal action space. The session itself is still unlimited.
        const SearchValue afterDraw =
            searchZeroSum(state, depthRemaining - 1, alpha, beta, context, ply, 0);
        state.undoDrawTile(player, drawnTile);
        if (!context.aborted && !afterDraw.raw.empty()) {
            drawScore = afterDraw.score;
            drawRaw = afterDraw.raw;
            hasDrawOption = true;
        }
    }

    const std::uint64_t key = state.transpositionKey(context.transpositionKeyMode);
    const TTEntry* ttEntry = context.tt->find(key);
    if (ttEntry != nullptr && ttEntry->depth >= depthRemaining) {
        const bool usable = ttEntry->flag == TTFlag::Exact ||
                            (ttEntry->flag == TTFlag::LowerBound && ttEntry->score >= beta) ||
                            (ttEntry->flag == TTFlag::UpperBound && ttEntry->score <= alpha);
        if (usable) {
            ++context.ttHits;
            SearchValue hit{ttEntry->score, rawFromEntry(*ttEntry, state.playerCount())};
            undoDraws(state, player, drawn);
            return hit;
        }
    }

    std::array<Move, MoveGenerator::kMaxMoves> candidates;
    const std::size_t candidateCount =
        MoveGenerator::generateInto(state, player, candidates);
    assert(candidateCount > 0);
    const int ttBest = ttEntry != nullptr ? ttEntry->bestCode : -1;
    orderMoves(candidates.data(), candidateCount, context, player, ply, ttBest);

    double bestScore = -kInfinity;
    RawEvaluation bestRaw;
    int bestCode = -1;
    bool cutoff = false;
    const double originalAlpha = alpha;
    const bool narrowWindow = context.useSelectiveSearch && (beta - alpha <= 1.0);

    // A voluntary draw competes with every placement as a real action.
    if (hasDrawOption) {
        bestScore = drawScore;
        bestRaw = drawRaw;
    }

    bool firstPlacement = true;
    for (std::size_t candidateIndex = 0; candidateIndex < candidateCount; ++candidateIndex) {
        const Move& move = candidates[candidateIndex];
        if (tick(context)) break;
        assert(MoveValidator::isLegal(state, player, move));
        auto applied = MoveExecutor::apply(state, player, move);
        const bool emptied = state.hand(player).empty();

        // PVS/LMR are opt-in for the deep tiers. The first placement gets a
        // full window; later quiet placements get a null-window probe, and a
        // move that beats alpha is re-searched at full depth. A reduced probe
        // is only a scout -- it never becomes the returned score unless a full
        // search confirms it. The default path remains the old full-width loop.
        const bool selective = context.useSelectiveSearch && context.useAlphaBeta && !emptied;
        const bool laterPlacement = !firstPlacement;
        const bool canReduce = selective && laterPlacement &&
                               depthRemaining >= 5 && candidateIndex >= 1;
        const bool nullWindow = selective && laterPlacement &&
                                alpha > -kInfinity / 2.0;
        const int childDepth = depthRemaining - 1 - (canReduce ? 4 : 0);
        const double windowAlpha = nullWindow ? -alpha - 1.0 : -beta;
        const double windowBeta = -alpha;

        auto searchChild = [&](int depth, double childAlpha, double childBeta) -> SearchValue {
            if (emptied) {
                SearchValue value;
                value.raw = evaluateAll(context.mode, state, context.weights, std::nullopt, context.positionalWeights);
                value.score = kTerminalWinScore + relativeScore(value.raw, player, context.mode);
                return value;
            }
            const int next = nextActivePlayer(state, player);
            state.setCurrentPlayerIndex(next);
            const double a = context.useAlphaBeta ? childAlpha : -kInfinity;
            const double b = context.useAlphaBeta ? childBeta : kInfinity;
            SearchValue value = searchZeroSum(state, depth, a, b, context, ply + 1, 0);
            state.setCurrentPlayerIndex(player);
            return value;
        };

        SearchValue child = searchChild(childDepth, windowAlpha, windowBeta);
        MoveExecutor::undo(state, applied);

        if (context.aborted || child.raw.empty()) break;

        double score = emptied ? child.score : -child.score;
        if ((canReduce || nullWindow) && !emptied && score > alpha) {
            auto fullApplied = MoveExecutor::apply(state, player, move);
            child = searchChild(depthRemaining - 1, -beta, -alpha);
            MoveExecutor::undo(state, fullApplied);
            if (context.aborted || child.raw.empty()) break;
            score = -child.score;
        }

        firstPlacement = false;
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
    if (context.aborted || bestRaw.empty()) return {};

    // A PVS null-window probe only proves a bound; storing it as Exact would
    // let a later full-window search reuse a score that was never searched at
    // that width. Keep narrow probes out of the shared table.
    if (!bestRaw.empty() && !narrowWindow) {
        TTFlag flag = TTFlag::Exact;
        if (cutoff) flag = TTFlag::LowerBound;
        else if (bestScore <= originalAlpha) flag = TTFlag::UpperBound;
        context.tt->store(key, depthRemaining, bestScore, bestRaw, bestCode, flag);
    }
    return SearchValue{bestScore, bestRaw};
}

RawEvaluation searchMulti(GameState& state,
                          int depthRemaining,
                          SearchContext& context,
                          int ply) {
    if (tick(context)) return {};

    const int player = state.currentPlayerIndex();
    if (depthRemaining <= 0) {
        // evaluateAll derives Closed from mobility without a second scan.
        return evaluateAll(context.mode, state, context.weights, std::nullopt, context.positionalWeights);
    }

    const bool closed = MoveGenerator::isPositionClosed(state);
    if (closed) {
        return evaluateAll(context.mode, state, context.weights, true, context.positionalWeights);
    }

    std::vector<DominoTile> drawn = resolveForcedDraws(state, player);
    if (!MoveGenerator::hasAnyLegalMove(state, player)) {
        const int next = nextActivePlayer(state, player);
        state.setCurrentPlayerIndex(next);
        RawEvaluation child = searchMulti(state, depthRemaining - 1, context, ply);
        state.setCurrentPlayerIndex(player);
        undoDraws(state, player, drawn);
        return child;
    }

    const std::uint64_t key = state.transpositionKey(context.transpositionKeyMode);
    const TTEntry* ttEntry = context.tt->find(key);
    if (ttEntry != nullptr && ttEntry->depth >= depthRemaining) {
        ++context.ttHits;
        RawEvaluation hit = rawFromEntry(*ttEntry, state.playerCount());
        undoDraws(state, player, drawn);
        return hit;
    }

    std::array<Move, MoveGenerator::kMaxMoves> candidates;
    const std::size_t candidateCount =
        MoveGenerator::generateInto(state, player, candidates);
    assert(candidateCount > 0);
    const int ttBest = ttEntry != nullptr ? ttEntry->bestCode : -1;
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
                    child = evaluateAll(context.mode, state, context.weights, std::nullopt, context.positionalWeights);
            child[static_cast<std::size_t>(player)] += kTerminalWinScore;
        } else {
            const int next = nextActivePlayer(state, player);
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
    if (context.aborted || bestRaw.empty()) return {};

    if (bestRaw.size() == static_cast<std::size_t>(state.playerCount())) {
        context.tt->store(key, depthRemaining, 0.0, bestRaw, bestCode, TTFlag::Exact);
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

    // A voluntary draw is a first-class candidate when enabled. It is appended
    // after the placements so candidate indices keep their existing meaning.
    // The opener of a round faces an empty chain, where every tile is a legal
    // lead; the rules require a play there, so a draw must not be a candidate.
    const bool drawAllowed = config.maxVoluntaryDraws > 0 &&
                             state.boneyard().drawableCount() > 0 &&
                             !state.chain().isEmpty();
    const std::size_t drawIndex = candidates.size();
    const std::size_t actionCount = candidates.size() + (drawAllowed ? 1u : 0u);

    const int playerCount = state.playerCount();

    SamplePool& pool = searchPool();
    int workers = config.workerThreads;
    if (workers <= 0) {
        workers = pool.size();
    }
    workers = std::max(1, std::min({workers, config.determinizationCount, kMaxWorkers}));

    const bool parallel = workers > 1 && pool.size() > 1;
    const int laneCount = parallel ? std::min(workers, pool.size()) : 1;

    std::atomic<bool> stopFlag{false};
    std::vector<SearchContext> contexts(static_cast<std::size_t>(laneCount));
    for (SearchContext& ctx : contexts) {
        ctx.mode = mode;
        ctx.endgameTileLimit = config.endgameTileLimit;
        ctx.useAlphaBeta = config.useAlphaBeta;
        ctx.useSelectiveSearch = config.useSelectiveSearch;
        ctx.transpositionKeyMode = config.transpositionKeyMode;
        ctx.cancelRequested = cancelRequested;
        ctx.sharedAbort = &stopFlag;
        ctx.weights = config.weights;
        ctx.positionalWeights = config.useConditionalWeights ? &config.positionalWeights : nullptr;
        ctx.maxVoluntaryDraws = config.maxVoluntaryDraws;
    }

    const auto start = std::chrono::steady_clock::now();
    if (config.timeLimitMs > 0) {
        const auto deadline = start + std::chrono::milliseconds(config.timeLimitMs);
        for (SearchContext& ctx : contexts) {
            ctx.hasDeadline = true;
            ctx.deadline = deadline;
        }
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
    bool bestIsDraw = false;

    for (int depth = 1; depth <= config.maxDepthPlies; ++depth) {
        if (shouldStop(contexts.front()) || stopFlag.load(std::memory_order_relaxed)) break;

        // Worlds are sampled sequentially from the caller's RNG, so the set of
        // sampled worlds -- and therefore the decision -- is identical to the
        // single-threaded path for the same seed.
        std::vector<GameState> worlds;
        worlds.reserve(static_cast<std::size_t>(config.determinizationCount));
        for (int sample = 0; sample < config.determinizationCount; ++sample) {
            worlds.push_back(SimulationEngine::sampleDeterminizedState(state, belief, player, rng));
        }

        struct SampleResult {
            std::vector<double> scores;
            std::vector<std::vector<double>> values;
            bool aborted = true;
        };
        std::vector<SampleResult> sampleResults(static_cast<std::size_t>(config.determinizationCount));

        auto evaluateSample = [&](int sampleIndex, SearchContext& ctx,
                                  TranspositionTable& table) {
            startTableIfNeeded(ctx, table);
            SampleResult& result = sampleResults[static_cast<std::size_t>(sampleIndex)];
            result.scores.assign(actionCount, 0.0);
            result.values.assign(actionCount,
                                 std::vector<double>(static_cast<std::size_t>(playerCount), 0.0));
            result.aborted = false;

            const GameState& world = worlds[static_cast<std::size_t>(sampleIndex)];

            for (std::size_t c = 0; c < actionCount; ++c) {
                if (shouldStop(ctx)) {
                    result.aborted = true;
                    stopFlag.store(true, std::memory_order_relaxed);
                    return;
                }

                GameState trial = world;

                if (drawAllowed && c == drawIndex) {
                    // Same player to move after a draw, so no sign flip.
                    const DominoTile drawnTile = trial.drawTile(player);
                    const SearchValue afterDraw = searchZeroSum(
                        trial, depth - 1, -kInfinity, kInfinity, ctx, 0, 0);
                    trial.undoDrawTile(player, drawnTile);
                    const RawEvaluation drawRaw = afterDraw.raw;
                    if (ctx.aborted || drawRaw.size() != static_cast<std::size_t>(playerCount)) {
                        result.aborted = true;
                        stopFlag.store(true, std::memory_order_relaxed);
                        return;
                    }
                    for (int p = 0; p < playerCount; ++p) {
                        result.values[c][static_cast<std::size_t>(p)] =
                            drawRaw[static_cast<std::size_t>(p)];
                    }
                    result.scores[c] = afterDraw.score;
                    continue;
                }
                auto applied = MoveExecutor::apply(trial, player, candidates[c]);
                const bool emptied = trial.hand(player).empty();

                RawEvaluation raw;
                double candidateScore = 0.0;
                if (emptied) {
                    raw = evaluateAll(mode, trial, config.weights, std::nullopt,
                                 config.useConditionalWeights ? &config.positionalWeights : nullptr);
                    if (mode == GameMode::OneVsOneVsOne) {
                        raw[static_cast<std::size_t>(player)] += kTerminalWinScore;
                        candidateScore = raw[static_cast<std::size_t>(player)];
                    } else {
                        candidateScore = kTerminalWinScore + relativeScore(raw, player, mode);
                    }
                } else {
                    const int next = nextActivePlayer(trial, player);
                    trial.setCurrentPlayerIndex(next);
                    if (mode == GameMode::OneVsOneVsOne) {
                        raw = searchMulti(trial, depth - 1, ctx, 0);
                        if (!raw.empty()) {
                            candidateScore = raw[static_cast<std::size_t>(player)];
                        }
                    } else {
                        // The draw action is evaluated once, above, as its own
                        // root candidate. Once a placement has been made, the
                        // next turn starts from the live snapshot and gets its
                        // own decision; planning another draw inside this tree
                        // only spends horizon. Draws remain unlimited live.
                        SearchValue child = searchZeroSum(trial, depth - 1, -kInfinity, kInfinity, ctx, 0, 0);
                        raw = child.raw;
                        candidateScore = -child.score;
                    }
                    trial.setCurrentPlayerIndex(player);
                }
                MoveExecutor::undo(trial, applied);

                if (ctx.aborted || raw.size() != static_cast<std::size_t>(playerCount)) {
                    result.aborted = true;
                    stopFlag.store(true, std::memory_order_relaxed);
                    return;
                }

                for (int p = 0; p < playerCount; ++p) {
                    result.values[c][static_cast<std::size_t>(p)] = raw[static_cast<std::size_t>(p)];
                }
                result.scores[c] = candidateScore;
            }
        };

        const std::size_t tableBuckets = ttBucketsForDepth(config.maxDepthPlies);
        if (!parallel) {
            TranspositionTable& table = pool.tableFor(0, tableBuckets);
            for (int sample = 0; sample < config.determinizationCount; ++sample) {
                if (stopFlag.load(std::memory_order_relaxed)) break;
                evaluateSample(sample, contexts.front(), table);
            }
        } else {
            pool.run([&](int lane) {
                if (lane >= laneCount) return;
                SearchContext& ctx = contexts[static_cast<std::size_t>(lane)];
                TranspositionTable& table = pool.tableFor(lane, tableBuckets);
                for (int sample = lane; sample < config.determinizationCount; sample += laneCount) {
                    if (stopFlag.load(std::memory_order_relaxed)) return;
                    evaluateSample(sample, ctx, table);
                }
            });
        }

        std::vector<std::vector<double>> accumulated(
            actionCount,
            std::vector<double>(static_cast<std::size_t>(playerCount), 0.0));
        // Per-candidate score in every sampled world. Keeping them separate --
        // rather than only accumulating a running mean -- is what makes any
        // aggregation rule other than the mean possible at the root.
        std::vector<std::vector<double>> scoresByCandidate(actionCount);
        for (std::vector<double>& perCandidate : scoresByCandidate) {
            perCandidate.reserve(static_cast<std::size_t>(config.determinizationCount));
        }
        int samples = 0;
        bool abortedDepth = stopFlag.load(std::memory_order_relaxed);

        // Reduced in sample order, so the floating-point sums -- and, for the
        // mean rule, the chosen move -- are identical to the single-threaded
        // path.
        for (int sample = 0; sample < config.determinizationCount && !abortedDepth; ++sample) {
            const SampleResult& result = sampleResults[static_cast<std::size_t>(sample)];
            if (result.aborted) {
                abortedDepth = true;
                break;
            }
            for (std::size_t c = 0; c < actionCount; ++c) {
                scoresByCandidate[c].push_back(result.scores[c]);
                for (int p = 0; p < playerCount; ++p) {
                    accumulated[c][static_cast<std::size_t>(p)] +=
                        result.values[c][static_cast<std::size_t>(p)];
                }
            }
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

            auto aggregate = [&](std::size_t candidateIndex) -> double {
                const std::vector<double>& scores = scoresByCandidate[candidateIndex];
                if (scores.empty()) return -kInfinity;
                switch (config.rootAggregation) {
                case RootAggregation::Maximin: {
                    double worst = kInfinity;
                    for (double score : scores) worst = std::min(worst, score);
                    return worst;
                }
                case RootAggregation::TrimmedMean: {
                    std::vector<double> sorted = scores;
                    std::sort(sorted.begin(), sorted.end());
                    const std::size_t drop = sorted.size() / 4;
                    double total = 0.0;
                    for (std::size_t i = drop; i < sorted.size(); ++i) total += sorted[i];
                    return total / static_cast<double>(sorted.size() - drop);
                }
                case RootAggregation::WinCount: {
                    double wins = 0.0;
                    for (std::size_t i = 0; i < scores.size(); ++i) {
                        double best = -kInfinity;
                        for (const std::vector<double>& other : scoresByCandidate) {
                            if (i < other.size()) best = std::max(best, other[i]);
                        }
                        if (scores[i] >= best) wins += 1.0;
                    }
                    return wins;
                }
                case RootAggregation::Mean:
                default: {
                    double total = 0.0;
                    for (double score : scores) total += score;
                    return total / static_cast<double>(scores.size());
                }
                }
            };

            std::size_t bestIndex = 0;
            double bestCriterion = -kInfinity;
            for (std::size_t c = 0; c < accumulated.size(); ++c) {
                // The mean rule keeps the original per-mode criterion (raw value
                // in 1v1v1, team-relative otherwise). The robust rules compare
                // like-for-like per-candidate distributions, so their mode
                // handling is already encoded in what was scored.
                const double criterion =
                    (config.rootAggregation == RootAggregation::Mean &&
                     mode == GameMode::OneVsOneVsOne)
                        ? rootCriterion(accumulated[c], player, mode)
                        : aggregate(c);
                if (criterion > bestCriterion) {
                    bestCriterion = criterion;
                    bestIndex = c;
                }
            }

            // The draw is a candidate INDEX but not a Move: drawIndex sits one
            // past the end of `candidates`. Indexing it here read out of bounds
            // and produced a garbage "placeholder" move. A draw must report a
            // genuinely legal placement instead (the DTO contract requires it),
            // so use the first legal candidate and let isDraw carry the meaning.
            bestIsDraw = drawAllowed && bestIndex == drawIndex;
            const Move chosenMove = bestIsDraw ? candidates[0] : candidates[bestIndex];
            bestResult = DepthResult{chosenMove, accumulated[bestIndex], depth, samples};
        }

        if (abortedDepth) break;
    }

    std::uint64_t totalNodes = 0;
    std::uint64_t totalTtHits = 0;
    bool anyExactEndgame = false;
    for (const SearchContext& ctx : contexts) {
        totalNodes += ctx.nodes;
        totalTtHits += ctx.ttHits;
        anyExactEndgame = anyExactEndgame || ctx.exactEndgameUsed;
    }

    if (bestResult.has_value()) {
        return SearchDecision{bestResult->move,
                              bestResult->values,
                              bestResult->samples == config.determinizationCount,
                              bestResult->samples,
                              bestResult->depth,
                              totalNodes,
                              totalTtHits,
                              anyExactEndgame,
                              bestIsDraw};
    }

    return SearchDecision{candidates[0],
                          std::vector<double>(static_cast<std::size_t>(playerCount), 0.0),
                          false,
                          0,
                          0,
                          totalNodes,
                          totalTtHits,
                          anyExactEndgame};
}

} // namespace isolyn
