#include "IsolynBridge.hpp"

#include "Dealer.hpp"
#include "EntropySource.hpp"
#include "MatchController.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "ProbabilityEngine.hpp"
#include "SearchEngine.hpp"

#include <atomic>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <random>
#include <unordered_map>
#include <utility>
#include <optional>

namespace isolyn::bridge {

// ============================================================================
// Internal conversion / validation helpers
// ============================================================================
namespace {

DominoTile toEngine(TileDTO t) {
    return DominoTile(t.low, t.high);
}

TileDTO fromEngine(DominoTile t) {
    return TileDTO{
        static_cast<int8_t>(t.low()),
        static_cast<int8_t>(t.high())
    };
}

constexpr TileDTO kNoTileDTO{-1, -1};

bool isValidTileDTO(TileDTO t) {
    return t.low >= DominoTile::kMinPips &&
           t.low <= DominoTile::kMaxPips &&
           t.high >= DominoTile::kMinPips &&
           t.high <= DominoTile::kMaxPips;
}

bool isValidMode(GameModeDTO m) {
    return m == GameModeDTO::OneVsOne ||
           m == GameModeDTO::OneVsOneVsOne ||
           m == GameModeDTO::TwoVsTwo;
}

bool isValidSide(ChainSideDTO s) {
    return s == ChainSideDTO::Left ||
           s == ChainSideDTO::Right;
}

GameMode toEngine(GameModeDTO m) {
    switch (m) {
        case GameModeDTO::OneVsOne: return GameMode::OneVsOne;
        case GameModeDTO::OneVsOneVsOne: return GameMode::OneVsOneVsOne;
        case GameModeDTO::TwoVsTwo: return GameMode::TwoVsTwo;
    }
    return GameMode::OneVsOne;
}

GameModeDTO fromEngine(GameMode m) {
    switch (m) {
        case GameMode::OneVsOne: return GameModeDTO::OneVsOne;
        case GameMode::OneVsOneVsOne: return GameModeDTO::OneVsOneVsOne;
        case GameMode::TwoVsTwo: return GameModeDTO::TwoVsTwo;
    }
    return GameModeDTO::OneVsOne;
}

GameState::ChainSide toEngine(ChainSideDTO s) {
    return s == ChainSideDTO::Left ? GameState::ChainSide::Left : GameState::ChainSide::Right;
}

Move toEngineMove(MoveDTO m) {
    return Move{ toEngine(m.tile), toEngine(m.side) };
}

MoveDTO fromEngineMove(const Move& move) {
    return MoveDTO{ fromEngine(move.tile),
        move.side == GameState::ChainSide::Left ? ChainSideDTO::Left : ChainSideDTO::Right };
}

RoundOutcomeDTO fromEngine(RoundOutcomeKind k) {
    switch (k) {
        case RoundOutcomeKind::InProgress: return RoundOutcomeDTO::InProgress;
        case RoundOutcomeKind::DominoVictory: return RoundOutcomeDTO::DominoVictory;
        case RoundOutcomeKind::Closed: return RoundOutcomeDTO::Closed;
    }
    return RoundOutcomeDTO::InProgress;
}

void setDiagnostic(char (&buf)[128], const char* msg) noexcept {
    if (msg == nullptr) { buf[0] = '\0'; return; }
    // FIX: snprintf guarantees null-termination, strncpy does not.
    std::snprintf(buf, sizeof(buf), "%s", msg);
}

void clearDiagnostic(char (&buf)[128]) noexcept { buf[0] = '\0'; }

CommandResultDTO failedCommand(BridgeStatus status, const char* diagnostic) noexcept {
    CommandResultDTO r{};
    r.status = status; r.newStateVersion = 0; r.roundOutcome = RoundOutcomeDTO::InProgress; r.decidingPlayerIndex = -1;
    setDiagnostic(r.diagnosticMessage, diagnostic); return r;
}

SnapshotDTO failedSnapshot(BridgeStatus status) noexcept {
    SnapshotDTO s{}; s.status = status; return s;
}

AnalysisResultDTO failedAnalysis(BridgeStatus status) noexcept {
    AnalysisResultDTO r{};
    r.status = status; r.completed = false; r.samplesCompleted = 0; r.samplesConfigured = 0;
    r.playerCount = 0; r.stateVersionAnalyzed = 0;
    for (double& v : r.expectedValuePerPlayer) v = 0.0;
    r.recommendedMove = MoveDTO{ kNoTileDTO, ChainSideDTO::Left };
    return r;
}

bool canAdvanceStateVersion(uint64_t version) noexcept { return version < std::numeric_limits<uint64_t>::max(); }
void advanceStateVersion(uint64_t& version) noexcept { ++version; }

} // namespace

// ============================================================================
// Internal session / analysis state
// ============================================================================
namespace {

struct EngineSessionImpl {
    MatchController controller;
    GameMode mode;
    uint64_t stateVersion = 1;
    // FIX: Cache authoritative round outcome so snapshots don't guess.
    RoundOutcomeDTO cachedRoundOutcome = RoundOutcomeDTO::InProgress;
    int             cachedDecidingPlayer = -1;
    std::mutex mutex;
    EngineSessionImpl(MatchController c, GameMode m) : controller(std::move(c)), mode(m) {}
};

struct AnalysisSnapshotImpl {
    GameState world;
    BeliefState belief;
    GameMode mode;
    int believerPlayerIndex;
    uint64_t stateVersionAnalyzed;
    std::atomic<bool> cancelRequested{false};
    AnalysisSnapshotImpl(GameState w, BeliefState b, GameMode m, int believer, uint64_t v)
        : world(std::move(w)), belief(std::move(b)), mode(m), believerPlayerIndex(believer), stateVersionAnalyzed(v) {}
};

// ============================================================================
// Handle Tables
// ============================================================================
template <typename Impl>
class HandleTable {
public:
    uint64_t insert(std::unique_ptr<Impl> value) {
        if (!value) return 0;
        std::lock_guard<std::mutex> lock(m_mutex);
        // FIX: Exhaustion logic. If m_nextId == 0, space is permanently exhausted.
        // No wrap-around, no "one last ID" edge case.
        if (m_nextId == 0) return 0;
        uint64_t id = m_nextId++;
        if (m_nextId == 0) m_nextId = 0; // Clamp on wrap.
        m_entries.emplace(id, std::shared_ptr<Impl>(std::move(value)));
        return id;
    }
    std::shared_ptr<Impl> find(uint64_t id) {
        if (id == 0) return nullptr;
        std::lock_guard<std::mutex> lock(m_mutex);
        auto it = m_entries.find(id);
        return (it == m_entries.end()) ? nullptr : it->second;
    }
    void erase(uint64_t id) {
        if (id == 0) return;
        std::lock_guard<std::mutex> lock(m_mutex); m_entries.erase(id);
    }
    std::size_t size() { std::lock_guard<std::mutex> lock(m_mutex); return m_entries.size(); }
private:
    std::mutex m_mutex; uint64_t m_nextId = 1;
    std::unordered_map<uint64_t, std::shared_ptr<Impl>> m_entries;
};

HandleTable<EngineSessionImpl>& sessionTable() { static HandleTable<EngineSessionImpl> t; return t; }
HandleTable<AnalysisSnapshotImpl>& analysisTable() { static HandleTable<AnalysisSnapshotImpl> t; return t; }

} // namespace -- was missing in the original; see review notes

// ============================================================================
// Snapshot Construction
// ============================================================================
namespace {

SnapshotDTO buildSnapshot(EngineSessionImpl& impl, int requestingPlayerIndex) {
    const GameState& state = impl.controller.state();
    const int playerCount = state.playerCount();
    if (requestingPlayerIndex < 0 || requestingPlayerIndex >= playerCount) return failedSnapshot(BridgeStatus::InvalidRequest);

    SnapshotDTO out{};
    out.status = BridgeStatus::Ok;
    out.stateVersion = impl.stateVersion;
    out.mode = fromEngine(impl.mode);
    out.playerCount = playerCount;
    out.requestingPlayerIndex = requestingPlayerIndex;
    out.currentPlayerIndex = state.currentPlayerIndex();

    // Own Hand
    const auto& ownHand = state.hand(requestingPlayerIndex);
    const std::size_t ownCap = static_cast<std::size_t>(kTotalTileCount);
    const std::size_t ownCopied = ownHand.size() < ownCap ? ownHand.size() : ownCap;
    out.ownHandCount = static_cast<int32_t>(ownCopied);
    for (std::size_t i = 0; i < ownCopied; ++i) out.ownHand[i] = fromEngine(ownHand[i]);

    // Other Hand Sizes
    for (int p = 0; p < kMaxPlayers; ++p) out.otherHandSizes[p] = 0;
    const int bounded = playerCount < kMaxPlayers ? playerCount : kMaxPlayers;
    for (int p = 0; p < bounded; ++p) {
        if (p == requestingPlayerIndex) continue;
        out.otherHandSizes[p] = static_cast<int32_t>(state.hand(p).size());
    }

    // Chain
    const auto& orderedChain = state.chain().orderedTiles();
    const std::size_t chainCap = static_cast<std::size_t>(kTotalTileCount);
    const std::size_t chainCopied = orderedChain.size() < chainCap ? orderedChain.size() : chainCap;
    out.chain.count = static_cast<int32_t>(chainCopied);
    for (std::size_t i = 0; i < chainCopied; ++i) out.chain.tiles[i] = fromEngine(orderedChain[i]);
    out.chain.leftEnd = state.chain().isEmpty() ? -1 : state.chain().leftEnd();
    out.chain.rightEnd = state.chain().isEmpty() ? -1 : state.chain().rightEnd();

    // Boneyard
    out.boneyardDrawableCount = static_cast<int32_t>(state.boneyard().drawableCount());
    auto locked = state.boneyard().lockedTiles();
    out.boneyardLockedTiles[0] = kNoTileDTO; out.boneyardLockedTiles[1] = kNoTileDTO;
    const std::size_t lockedCopied = locked.size() < 2 ? locked.size() : 2;
    out.boneyardLockedCount = static_cast<int32_t>(lockedCopied);
    for (std::size_t i = 0; i < lockedCopied; ++i) out.boneyardLockedTiles[i] = fromEngine(locked[i]);

    // FIX: Authoritative Round Outcome from Cache (set by commands), not local heuristic.
    out.roundOutcome = impl.cachedRoundOutcome;
    out.decidingPlayerIndex = impl.cachedDecidingPlayer;

    // Legal Moves
    out.legalMovesForRequestingPlayer.count = 0;
    if (out.currentPlayerIndex == requestingPlayerIndex) {
        auto legal = MoveGenerator::generate(state, requestingPlayerIndex);
        const std::size_t legalCap = static_cast<std::size_t>(kMaxLegalMoves);
        const std::size_t legalCopied = legal.size() < legalCap ? legal.size() : legalCap;
        out.legalMovesForRequestingPlayer.count = static_cast<int32_t>(legalCopied);
        for (std::size_t i = 0; i < legalCopied; ++i) out.legalMovesForRequestingPlayer.moves[i] = fromEngineMove(legal[i]);
    }
    return out;
}

} // namespace

// ============================================================================
// Lifecycle
// ============================================================================
SessionHandle bridge_session_create_first_round(GameModeDTO mode) {
    if (!isValidMode(mode)) return kInvalidSessionHandle;
    // FIX: Construct EntropySource outside try block so system entropy failures
    // aren't silently swallowed as "Invalid Handle".
    EntropySource entropy;
    try {
        const GameMode engineMode = toEngine(mode);
        MatchController controller = MatchController::dealFirstRound(engineMode, entropy);
        auto impl = std::make_unique<EngineSessionImpl>(std::move(controller), engineMode);
        return sessionTable().insert(std::move(impl));
    } catch (...) { return kInvalidSessionHandle; }
}

SessionHandle bridge_session_create_subsequent_round(GameModeDTO mode, int32_t startingPlayerIndex) {
    if (!isValidMode(mode)) return kInvalidSessionHandle;
    EntropySource entropy;
    try {
        const GameMode engineMode = toEngine(mode);
        const int playerCount = Dealer::playerCountForMode(engineMode);
        if (startingPlayerIndex < 0 || startingPlayerIndex >= playerCount) return kInvalidSessionHandle;
        MatchController controller = MatchController::dealSubsequentRound(engineMode, entropy, startingPlayerIndex);
        auto impl = std::make_unique<EngineSessionImpl>(std::move(controller), engineMode);
        return sessionTable().insert(std::move(impl));
    } catch (...) { return kInvalidSessionHandle; }
}

void bridge_session_close(SessionHandle session) { sessionTable().erase(session); }

// ============================================================================
// Queries
// ============================================================================
SnapshotDTO bridge_get_snapshot(SessionHandle session, int32_t requestingPlayerIndex) {
    try {
        auto impl = sessionTable().find(session);
        if (!impl) return failedSnapshot(BridgeStatus::SessionClosed);
        std::lock_guard<std::mutex> lock(impl->mutex);
        return buildSnapshot(*impl, requestingPlayerIndex);
    } catch (...) { return failedSnapshot(BridgeStatus::BridgeFailure); }
}

// ============================================================================
// Commands
// ============================================================================
namespace {
// Internal helper to reduce boilerplate in command functions.
void commitSuccess(EngineSessionImpl& impl, RoundOutcomeKind kind, int decidingPlayer) {
    advanceStateVersion(impl.stateVersion);
    impl.cachedRoundOutcome = fromEngine(kind);
    impl.cachedDecidingPlayer = decidingPlayer;
}
CommandResultDTO okResult(const EngineSessionImpl& impl, RoundOutcomeDTO outcome, int decidingPlayer) {
    CommandResultDTO r{}; r.status = BridgeStatus::Ok; r.newStateVersion = impl.stateVersion;
    r.roundOutcome = outcome; r.decidingPlayerIndex = decidingPlayer;
    clearDiagnostic(r.diagnosticMessage); return r;
}
} // namespace

CommandResultDTO bridge_submit_move(SessionHandle session, uint64_t expectedStateVersion, MoveDTO move) {
    try {
        auto impl = sessionTable().find(session);
        if (!impl) return failedCommand(BridgeStatus::SessionClosed, "session is closed or unknown");
        std::lock_guard<std::mutex> lock(impl->mutex);
        if (expectedStateVersion != impl->stateVersion) return failedCommand(BridgeStatus::StaleRequest, "expectedStateVersion mismatch");
        if (!isValidTileDTO(move.tile) || !isValidSide(move.side)) return failedCommand(BridgeStatus::InvalidRequest, "invalid tile or side");
        if (!canAdvanceStateVersion(impl->stateVersion)) return failedCommand(BridgeStatus::BridgeFailure, "state version exhausted");

        const GameState& state = impl->controller.state();
        const int player = impl->controller.currentPlayerIndex();
        const Move engineMove = toEngineMove(move);
        if (!MoveValidator::isLegal(state, player, engineMove)) return failedCommand(BridgeStatus::InvalidMove, "illegal move");

        RoundOutcome outcome = impl->controller.playTurn(engineMove);
        commitSuccess(*impl, outcome.kind, outcome.decidingPlayerIndex);
        return okResult(*impl, fromEngine(outcome.kind), outcome.decidingPlayerIndex);
    } catch (...) { return failedCommand(BridgeStatus::EngineFailure, "engine exception"); }
}

CommandResultDTO bridge_voluntary_draw(SessionHandle session, uint64_t expectedStateVersion) {
    try {
        auto impl = sessionTable().find(session);
        if (!impl) return failedCommand(BridgeStatus::SessionClosed, "session closed");
        std::lock_guard<std::mutex> lock(impl->mutex);
        if (expectedStateVersion != impl->stateVersion) return failedCommand(BridgeStatus::StaleRequest, "stale version");
        if (!canAdvanceStateVersion(impl->stateVersion)) return failedCommand(BridgeStatus::BridgeFailure, "version exhausted");
        if (impl->controller.state().boneyard().drawableCount() == 0) return failedCommand(BridgeStatus::BoneyardEmpty, "boneyard empty");

        impl->controller.voluntaryDraw();
        commitSuccess(*impl, RoundOutcomeKind::InProgress, -1);
        return okResult(*impl, RoundOutcomeDTO::InProgress, -1);
    } catch (...) { return failedCommand(BridgeStatus::EngineFailure, "engine exception"); }
}

CommandResultDTO bridge_resolve_forced_draw(SessionHandle session, uint64_t expectedStateVersion) {
    try {
        auto impl = sessionTable().find(session);
        if (!impl) return failedCommand(BridgeStatus::SessionClosed, "session closed");
        std::lock_guard<std::mutex> lock(impl->mutex);
        if (expectedStateVersion != impl->stateVersion) return failedCommand(BridgeStatus::StaleRequest, "stale version");
        if (!canAdvanceStateVersion(impl->stateVersion)) return failedCommand(BridgeStatus::BridgeFailure, "version exhausted");
        if (impl->controller.currentPlayerHasLegalMove()) return failedCommand(BridgeStatus::NoLegalMove, "legal move exists");

        impl->controller.resolveForcedDraw();
        commitSuccess(*impl, RoundOutcomeKind::InProgress, -1);
        return okResult(*impl, RoundOutcomeDTO::InProgress, -1);
    } catch (...) { return failedCommand(BridgeStatus::EngineFailure, "engine exception"); }
}

CommandResultDTO bridge_end_turn_with_no_play(SessionHandle session, uint64_t expectedStateVersion) {
    try {
        auto impl = sessionTable().find(session);
        if (!impl) return failedCommand(BridgeStatus::SessionClosed, "session closed");
        std::lock_guard<std::mutex> lock(impl->mutex);
        if (expectedStateVersion != impl->stateVersion) return failedCommand(BridgeStatus::StaleRequest, "stale version");
        if (!canAdvanceStateVersion(impl->stateVersion)) return failedCommand(BridgeStatus::BridgeFailure, "version exhausted");
        if (impl->controller.currentPlayerHasLegalMove()) return failedCommand(BridgeStatus::InvalidRequest, "legal move exists");

        RoundOutcome outcome = impl->controller.endTurnWithNoPlay();
        commitSuccess(*impl, outcome.kind, outcome.decidingPlayerIndex);
        return okResult(*impl, fromEngine(outcome.kind), outcome.decidingPlayerIndex);
    } catch (...) { return failedCommand(BridgeStatus::EngineFailure, "engine exception"); }
}

// ============================================================================
// Analysis
// ============================================================================
AnalysisHandle bridge_analysis_snapshot_create(SessionHandle session, int32_t believerPlayerIndex) {
    try {
        auto impl = sessionTable().find(session);
        if (!impl) return kInvalidAnalysisHandle;

        std::optional<GameState> worldCopyOpt; GameMode modeCopy; uint64_t versionCopy; int playerCount;
        {
            std::lock_guard<std::mutex> lock(impl->mutex);
            const GameState& state = impl->controller.state();
            playerCount = state.playerCount();
            if (believerPlayerIndex < 0 || believerPlayerIndex >= playerCount) return kInvalidAnalysisHandle;
            // NOTE (Claude, post-fuzzing): SearchEngine::chooseBestMove's
            // own documented precondition is that state.currentPlayerIndex()
            // already has a legal move -- it does not check this itself
            // (real play always resolves a forced draw first via
            // MatchController::resolveForcedDraw before a player is ever
            // asked to choose a move, and chooseBestMove trusts that).
            // Nothing here previously verified that before handing a
            // snapshot to chooseBestMove -- if the session's current
            // player happened to be blocked (needs bridge_resolve_forced_draw
            // first), this assert-fired every time under a debug build,
            // and would have been silent undefined behavior (candidates[0]
            // on an empty vector) under Release/NDEBUG. Found by
            // Tests/IsolynEngineBridgeTests/FuzzBridge.cpp within seconds
            // of the first real run -- reusing NoLegalMove here since it's
            // the exact same underlying condition bridge_resolve_forced_draw
            // already reports it as.
            if (!impl->controller.currentPlayerHasLegalMove()) return kInvalidAnalysisHandle;
            worldCopyOpt.emplace(state); modeCopy = impl->mode; versionCopy = impl->stateVersion;
        } // Lock released HERE. Belief construction happens unlocked.

        BeliefState belief = ProbabilityEngine::constructFromGameState(*worldCopyOpt, believerPlayerIndex);
        auto snap = std::make_unique<AnalysisSnapshotImpl>(std::move(*worldCopyOpt), std::move(belief), modeCopy, believerPlayerIndex, versionCopy);
        return analysisTable().insert(std::move(snap));
    } catch (...) { return kInvalidAnalysisHandle; }
}

AnalysisResultDTO bridge_analysis_run(AnalysisHandle snapshot, int32_t maxDepthPlies, int32_t determinizationCount, uint64_t rngSeed) {
    try {
        auto snap = analysisTable().find(snapshot);
        if (!snap) return failedAnalysis(BridgeStatus::SessionClosed);
        if (maxDepthPlies < 1 || determinizationCount < 1) return failedAnalysis(BridgeStatus::InvalidRequest);

        SearchEngine::Config config;
        config.maxDepthPlies = maxDepthPlies;
        config.determinizationCount = determinizationCount;
        std::mt19937_64 rng(rngSeed);

        // Pass atomic flag directly. No new abstraction layers.
        SearchDecision decision = SearchEngine::chooseBestMove(snap->world, snap->belief, snap->mode, config, rng, &snap->cancelRequested);

        AnalysisResultDTO r{};
        r.status = BridgeStatus::Ok; r.stateVersionAnalyzed = snap->stateVersionAnalyzed;
        r.completed = decision.completed; r.samplesCompleted = decision.samplesCompleted; r.samplesConfigured = determinizationCount;
        r.recommendedMove = fromEngineMove(decision.move);
        const std::size_t cnt = decision.expectedValuePerPlayer.size();
        const std::size_t copied = cnt < static_cast<std::size_t>(kMaxPlayers) ? cnt : static_cast<std::size_t>(kMaxPlayers);
        r.playerCount = static_cast<int32_t>(copied);
        for (int p = 0; p < kMaxPlayers; ++p) r.expectedValuePerPlayer[p] = 0.0;
        for (std::size_t p = 0; p < copied; ++p) r.expectedValuePerPlayer[p] = decision.expectedValuePerPlayer[p];
        return r;
    } catch (...) { return failedAnalysis(BridgeStatus::EngineFailure); }
}

void bridge_analysis_request_cancel(AnalysisHandle snapshot) {
    try { auto snap = analysisTable().find(snapshot); if (snap) snap->cancelRequested.store(true, std::memory_order_relaxed); } catch (...) {}
}

void bridge_analysis_snapshot_destroy(AnalysisHandle snapshot) { analysisTable().erase(snapshot); }

} // namespace isolyn::bridge