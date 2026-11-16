#include "IsolynBridge.hpp"

#include "Dealer.hpp"
#include "DifficultyModel.hpp"
#include "EntropySource.hpp"
#include "MatchController.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "ProbabilityEngine.hpp"
#include "SearchEngine.hpp"

#include "ScoreSystem.hpp"

#include <atomic>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <random>
#include <unordered_map>
#include <unordered_set>
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
    r.isDraw = false;
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
        // FIX-19b (audit F-12): the old post-increment line read
        // `if (m_nextId == 0) m_nextId = 0;` -- a no-op dressed as a
        // clamp. The entry guard above IS the whole exhaustion story:
        // once the counter wraps to 0 it stays there and every future
        // insert returns 0. Say exactly that, nothing more.
        uint64_t id = m_nextId++;
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

// One running ScoreSystem for one mode. Guarded by its own mutex; whenever a
// call must take BOTH this and a session's mutex, the session mutex is taken
// FIRST everywhere (single global ordering => no deadlock).
//
// Participant semantics are mode-dependent: 2v2 tracks two TEAM scores, not
// four individual scores. This helper is the single source of truth for that
// count -- the old constructor used Dealer::playerCountForMode (4 for 2v2),
// while bridge_match_record_round correctly built two team values, producing
// a size mismatch: debug assert, release out-of-bounds read.
int participantCountForMode(GameMode m) {
    return m == GameMode::TwoVsTwo ? 2 : Dealer::playerCountForMode(m);
}

struct MatchStateImpl {
    GameMode mode;
    ScoreSystem scores;                            // the CURRENT set only
    int setWins[kMaxPlayers] = {};                 // completed sets per participant
    int setsToWin = 3;                             // best-of-5; 4 selects best-of-7
    int targetScore = 151;                         // R-06: 101 or 151 in 1v1
    int setNumber = 1;                             // 1-based, current set
    std::unordered_set<uint64_t> recordedSessions; // session handles already applied
    bool matchEnded = false;                       // the GAME is over
    int winnerParticipantIndex = -1;
    bool nextRoundStartsSet = false;
    int nextRoundStarter = -1;
    std::mutex mutex;
    MatchStateImpl(GameMode m, int sets, int target = RulesEngine::kMatchTarget)
        : mode(m), scores(m, participantCountForMode(m), target), setsToWin(sets), targetScore(target) {}
};
HandleTable<MatchStateImpl>& matchTable() { static HandleTable<MatchStateImpl> t; return t; }

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

    // Reveal-on-end: per-player remaining hand value and actual tiles,
    // populated ONLY once the round has actually finished. During play every
    // count stays 0 and no hand identity is copied -- hidden information is
    // not leaked mid-round (see SnapshotDTO comment).
    for (int p = 0; p < kMaxPlayers; ++p) {
        out.finalHandValues[p] = 0;
        out.finalHandCounts[p] = 0;
    }
    for (int slot = 0; slot < kMaxPlayers * kTotalTileCount; ++slot) {
        out.finalRevealedTiles[slot] = kNoTileDTO;
    }
    if (impl.cachedRoundOutcome != RoundOutcomeDTO::InProgress) {
        for (int p = 0; p < playerCount && p < kMaxPlayers; ++p) {
            const auto& hand = state.hand(p);
            const std::size_t cap = static_cast<std::size_t>(kTotalTileCount);
            const std::size_t count = hand.size() < cap ? hand.size() : cap;
            out.finalHandCounts[p] = static_cast<int32_t>(count);
            for (std::size_t i = 0; i < count; ++i) {

                out.finalRevealedTiles[p * kTotalTileCount + static_cast<int>(i)] = fromEngine(hand[i]);
            }
            out.finalHandValues[p] = static_cast<int32_t>(RulesEngine::handPoints(hand));
        }
    }

    // Boneyard
    out.boneyardDrawableCount = static_cast<int32_t>(state.boneyard().drawableCount());
    // R-17: the locked pair is never revealed. The fields stay in the DTO
    // for the future private-look path, but are always empty today.
    out.boneyardLockedTiles[0] = kNoTileDTO; out.boneyardLockedTiles[1] = kNoTileDTO;
    out.boneyardLockedCount = 0;

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

LockedPairDTO bridge_session_private_locked_pair(SessionHandle session, int32_t requestingPlayerIndex) {
    LockedPairDTO out{};
    out.status = BridgeStatus::InvalidRequest;
    out.tiles[0] = kNoTileDTO;
    out.tiles[1] = kNoTileDTO;
    out.count = 0;
    try {
        auto impl = sessionTable().find(session);
        if (!impl) { out.status = BridgeStatus::SessionClosed; return out; }
        std::lock_guard<std::mutex> lock(impl->mutex);
        const auto pair = impl->controller.state().privateLockedPair(requestingPlayerIndex);
        if (!pair) return out;
        out.status = BridgeStatus::Ok;
        out.tiles[0] = fromEngine((*pair)[0]);
        out.tiles[1] = fromEngine((*pair)[1]);
        out.count = 2;
        return out;
    } catch (...) {
        out.status = BridgeStatus::BridgeFailure;
        out.count = 0;
        return out;
    }
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
        if (impl->cachedRoundOutcome != RoundOutcomeDTO::InProgress) return failedCommand(BridgeStatus::RoundAlreadyOver, "round has already ended -- record it / deal the next round instead");

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
        if (impl->cachedRoundOutcome != RoundOutcomeDTO::InProgress) return failedCommand(BridgeStatus::RoundAlreadyOver, "round has already ended -- record it / deal the next round instead");

        if (!canAdvanceStateVersion(impl->stateVersion)) return failedCommand(BridgeStatus::BridgeFailure, "version exhausted");
        if (impl->controller.state().boneyard().drawableCount() == 0) return failedCommand(BridgeStatus::BoneyardEmpty, "boneyard empty");
        // The opener faces an empty chain, where every tile is a legal lead;
        // the rules require a play, so no draw is available.
        if (!impl->controller.canVoluntaryDraw()) return failedCommand(BridgeStatus::NoLegalMove, "the opener must play: drawing requires a non-empty chain");

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
        if (impl->cachedRoundOutcome != RoundOutcomeDTO::InProgress) return failedCommand(BridgeStatus::RoundAlreadyOver, "round has already ended -- record it / deal the next round instead");

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
        if (impl->cachedRoundOutcome != RoundOutcomeDTO::InProgress) return failedCommand(BridgeStatus::RoundAlreadyOver, "round has already ended -- record it / deal the next round instead");

        if (!canAdvanceStateVersion(impl->stateVersion)) return failedCommand(BridgeStatus::BridgeFailure, "version exhausted");
        if (impl->controller.currentPlayerHasLegalMove()) return failedCommand(BridgeStatus::InvalidRequest, "legal move exists");

        RoundOutcome outcome = impl->controller.endTurnWithNoPlay();
        commitSuccess(*impl, outcome.kind, outcome.decidingPlayerIndex);
        return okResult(*impl, fromEngine(outcome.kind), outcome.decidingPlayerIndex);
    } catch (...) { return failedCommand(BridgeStatus::EngineFailure, "engine exception"); }
}

// ============================================================================
// Match orchestration
// ============================================================================
namespace {

MatchResultDTO failedMatch(BridgeStatus status) noexcept {
    MatchResultDTO r{};
    r.status = status;
    r.participantCount = 0;
    for (int p = 0; p < kMaxPlayers; ++p) {
        r.scoresPerParticipant[p] = 0;
        r.setWinsPerParticipant[p] = 0;
    }
    r.matchEnded = false;
    r.winnerParticipantIndex = -1;
    r.nextRoundStarterIndex = -1;
    r.setNumber = 0;
    r.setsToWin = 0;
    r.setWinnerParticipantIndex = -1;
    r.setEnded = false;
    r.nextRoundStartsSet = false;
    return r;
}

} // namespace

MatchHandle bridge_match_begin(GameModeDTO mode) {
    return bridge_match_begin_with_format(mode, 3);
}

MatchHandle bridge_match_begin_with_format(GameModeDTO mode, int32_t setsToWin) {
    return bridge_match_begin_with_format_and_target(
        mode, setsToWin, RulesEngine::kMatchTarget);
}

MatchHandle bridge_match_begin_with_format_and_target(
    GameModeDTO mode, int32_t setsToWin, int32_t targetScore) {
    if (!isValidMode(mode)) return kInvalidMatchHandle;
    if (setsToWin != 3 && setsToWin != 4) return kInvalidMatchHandle;
    if (targetScore != RulesEngine::kMatchTarget &&
        targetScore != RulesEngine::kOneVsOneShortMatchTarget) return kInvalidMatchHandle;
    if (mode != GameModeDTO::OneVsOne &&
        targetScore != RulesEngine::kMatchTarget) return kInvalidMatchHandle;
    try {
        const GameMode engineMode = toEngine(mode);
        auto impl = std::make_unique<MatchStateImpl>(engineMode, setsToWin, targetScore);
        return matchTable().insert(std::move(impl));
    } catch (...) { return kInvalidMatchHandle; }
}

MatchResultDTO bridge_match_record_round(MatchHandle match, SessionHandle finishedRound) {
    try {
        auto m = matchTable().find(match);
        if (!m) return failedMatch(BridgeStatus::SessionClosed);
        auto sess = sessionTable().find(finishedRound);
        if (!sess) return failedMatch(BridgeStatus::SessionClosed);

        // Lock ordering: SESSION first, then MATCH -- the single global order.
        std::lock_guard<std::mutex> sLock(sess->mutex);
        std::lock_guard<std::mutex> mMLock(m->mutex);

        // AUD-01: a session and a match must describe the same game. Without
        // this guard a 1v1 session recorded into a 2v2 match reaches the
        // team branch below and calls hand(2)/hand(3) on a two-player state;
        // hand() is guarded only by assert, so Release reads out of bounds
        // (Debug aborts the process). Reject before touching any score.
        if (sess->mode != m->mode ||
            sess->controller.state().playerCount() != Dealer::playerCountForMode(m->mode)) {
            return failedMatch(BridgeStatus::ModeMismatch);
        }

        if (m->matchEnded)
            return failedMatch(BridgeStatus::InvalidRequest); // match over; no further rounds may be recorded
        if (m->recordedSessions.count(finishedRound))
            return failedMatch(BridgeStatus::InvalidRequest); // duplicate record of the same round
        if (sess->cachedRoundOutcome == RoundOutcomeDTO::InProgress)
            return failedMatch(BridgeStatus::InvalidRequest); // round not finished yet

        const GameState& state = sess->controller.state();
        const int players = state.playerCount();
        const int participantCount = participantCountForMode(m->mode);

        // Participant values: two combined team values for 2v2, one per player
        // otherwise. Every seat is live in every mode now that 1v1v1 has no
        // elimination (R-22), so every seat is scored.
        std::vector<int> participantValues;
        if (m->mode == GameMode::TwoVsTwo) {
            auto t0 = RulesEngine::playersOnTeam(0);
            auto t1 = RulesEngine::playersOnTeam(1);
            auto handValue = [&state](int p) {
                return RulesEngine::handPoints(state.hand(p));
            };
            participantValues.push_back(RulesEngine::combineTeamValue(handValue(t0.first), handValue(t0.second)));
            participantValues.push_back(RulesEngine::combineTeamValue(handValue(t1.first), handValue(t1.second)));
        } else {
            for (int p = 0; p < players; ++p) {
                participantValues.push_back(RulesEngine::handPoints(state.hand(p)));
            }
        }
        if (participantValues.empty()) return failedMatch(BridgeStatus::InvalidRequest);

        const std::vector<int> roundScores = RulesEngine::computeRoundScores(participantValues);
        m->scores.applyRoundScores(roundScores);

        const int setNumberForRound = m->setNumber;
        int setWinner = -1;
        bool gameEnded = false;

        // R-06/R-22: every mode is a straight race. The first participant to
        // reach or pass the target wins the set outright; there is no
        // elimination and no survivor phase.
        const bool setEnded = m->scores.hasMatchEnded();
        if (setEnded) {
            setWinner = m->scores.winningParticipant();
            m->setWins[setWinner]++;
            if (m->setWins[setWinner] >= m->setsToWin) {
                gameEnded = true;
                m->matchEnded = true;
                m->winnerParticipantIndex = setWinner;
            }
        }

        // Next starter: whoever won by Domino or was credited with the Close.
        int nextStarter = -1;
        if (!setEnded && sess->cachedDecidingPlayer >= 0 && sess->cachedDecidingPlayer < players) {
            nextStarter = RulesEngine::determineNextRoundStarter(sess->cachedDecidingPlayer);
        }

        int finalSetScores[kMaxPlayers] = {};
        for (int i = 0; i < participantCount && i < kMaxPlayers; ++i) {
            finalSetScores[i] = m->scores.score(i);
        }
        // Scores reset only when the game continues -- the NEXT set starts at
        // zero with every 1v1v1 seat alive again, and the double-six ritual
        // restarts because the caller is told to create a first-round
        // session (nextRoundStartsSet).
        if (setEnded && !gameEnded) {
            m->setNumber++;
            // R-06: the pre-game race target covers every set, so the fresh
            // set's tracker must carry the same 101/151 choice -- constructing
            // a default ScoreSystem here silently reverted a 101 match to 151
            // after its first set.
            m->scores = ScoreSystem(m->mode, participantCount, m->targetScore);
        }

        m->nextRoundStartsSet = setEnded && !gameEnded;
        m->nextRoundStarter = (setEnded || gameEnded) ? -1 : nextStarter;

        m->recordedSessions.insert(finishedRound);

        MatchResultDTO r{};
        r.status = BridgeStatus::Ok;
        r.participantCount = static_cast<int32_t>(participantCount);
        for (int i = 0; i < participantCount; ++i) {
            r.scoresPerParticipant[i] = finalSetScores[i];
            r.setWinsPerParticipant[i] = m->setWins[i];
        }
        r.setNumber = setNumberForRound;
        r.setsToWin = m->setsToWin;
        r.setWinnerParticipantIndex = setWinner;
        r.setEnded = setEnded;
        r.matchEnded = m->matchEnded;
        r.winnerParticipantIndex = m->matchEnded ? m->winnerParticipantIndex : -1;
        r.nextRoundStarterIndex = (setEnded || gameEnded) ? -1 : nextStarter;
        r.nextRoundStartsSet = setEnded && !gameEnded;
        return r;
    } catch (...) { return failedMatch(BridgeStatus::EngineFailure); }
}

SessionHandle bridge_match_create_next_round(MatchHandle match) {
    auto m = matchTable().find(match);
    if (!m) return kInvalidSessionHandle;
    std::lock_guard<std::mutex> lock(m->mutex);
    if (m->matchEnded) return kInvalidSessionHandle;

    if (m->nextRoundStartsSet) {
        const SessionHandle h = bridge_session_create_first_round(fromEngine(m->mode));
        if (h != kInvalidSessionHandle) m->nextRoundStartsSet = false;
        return h;
    }

    if (m->nextRoundStarter < 0) return kInvalidSessionHandle;
    const int starter = m->nextRoundStarter;
    const SessionHandle h = bridge_session_create_subsequent_round(fromEngine(m->mode), starter);
    if (h != kInvalidSessionHandle) m->nextRoundStarter = -1;
    return h;
}

void bridge_match_close(MatchHandle match) { matchTable().erase(match); }

// ============================================================================
// Difficulty
// ============================================================================
DifficultyProfileDTO bridge_difficulty_profile(int32_t strength) {
    const DifficultyProfile p = DifficultyModel::profileForStrength(strength);
    DifficultyProfileDTO out{};
    out.strength = static_cast<int32_t>(p.strength);
    out.maxDepthPlies = static_cast<int32_t>(p.maxDepthPlies);
    out.determinizationCount = static_cast<int32_t>(p.determinizationCount);
    return out;
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

AnalysisResultDTO bridge_analysis_run_with_budget(AnalysisHandle snapshot, int32_t maxDepthPlies, int32_t determinizationCount, uint64_t rngSeed, int32_t timeLimitMs) {
    try {
        auto snap = analysisTable().find(snapshot);
        // FIX-18 (audit F-07): an unknown/expired ANALYSIS handle is a
        // BridgeFailure -- "unknown snapshot" semantics. It used to
        // return SessionClosed, which describes SESSION handles; this
        // DTO's own contract (see IsolynBridge.hpp) permits only
        // BridgeFailure/EngineFailure here, so the old value violated
        // the header's declared status set. AnalysisResultDTO has no
        // diagnostic buffer; the meaning is carried by this comment and
        // the header note.
        if (!snap) return failedAnalysis(BridgeStatus::BridgeFailure);
        if (maxDepthPlies < 1 || determinizationCount < 1) return failedAnalysis(BridgeStatus::InvalidRequest);

        SearchEngine::Config config;
        config.maxDepthPlies = maxDepthPlies;
        config.determinizationCount = determinizationCount;
        config.timeLimitMs = timeLimitMs > 0 ? timeLimitMs : 0;
        // The engine's Config defaults to no voluntary draws, which made this
        // path structurally incapable of ever recommending one: the draw
        // branch is gated on this being > 0. Analysis must search the same
        // action set the player can actually take, or its "best move" is a
        // recommendation for a different game.
        // R-15: the rulebook allows unlimited voluntary draws in a turn. The
        // search bound is larger than the whole double-six set, so it is
        // effectively unlimited; the analysis deadline keeps the tree bounded.
        config.maxVoluntaryDraws = SearchEngine::kUnlimitedVoluntaryDraws;
        // The two deep tiers use PVS/LMR; every shallower tier keeps the
        // existing full-width alpha-beta path. The experiment is opt-in and
        // its depth effect is measured separately.
        config.useSelectiveSearch = maxDepthPlies >= 24;
        std::mt19937_64 rng(rngSeed);

        // Pass atomic flag directly. No new abstraction layers.
        SearchDecision decision = SearchEngine::chooseBestMove(snap->world, snap->belief, snap->mode, config, rng, &snap->cancelRequested);

        AnalysisResultDTO r{};
        r.status = BridgeStatus::Ok; r.stateVersionAnalyzed = snap->stateVersionAnalyzed;
        r.completed = decision.completed; r.samplesCompleted = decision.samplesCompleted; r.samplesConfigured = determinizationCount;
        r.recommendedMove = fromEngineMove(decision.move);
        r.isDraw = decision.isDraw;
        const std::size_t cnt = decision.expectedValuePerPlayer.size();
        const std::size_t copied = cnt < static_cast<std::size_t>(kMaxPlayers) ? cnt : static_cast<std::size_t>(kMaxPlayers);
        r.playerCount = static_cast<int32_t>(copied);
        for (int p = 0; p < kMaxPlayers; ++p) r.expectedValuePerPlayer[p] = 0.0;
        for (std::size_t p = 0; p < copied; ++p) r.expectedValuePerPlayer[p] = decision.expectedValuePerPlayer[p];
        return r;
    } catch (...) { return failedAnalysis(BridgeStatus::EngineFailure); }
}

AnalysisResultDTO bridge_analysis_run(AnalysisHandle snapshot, int32_t maxDepthPlies, int32_t determinizationCount, uint64_t rngSeed) {
    return bridge_analysis_run_with_budget(snapshot, maxDepthPlies, determinizationCount, rngSeed, 0);
}

void bridge_analysis_request_cancel(AnalysisHandle snapshot) {
    try { auto snap = analysisTable().find(snapshot); if (snap) snap->cancelRequested.store(true, std::memory_order_relaxed); } catch (...) {}
}

void bridge_analysis_snapshot_destroy(AnalysisHandle snapshot) { analysisTable().erase(snapshot); }

} // namespace isolyn::bridge