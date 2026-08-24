#pragma once
#include <cstdint>

// ============================================================================
// ISOLYN ENGINE BRIDGE -- the ONLY header exposed to Swift.
// ============================================================================
//
// This is the narrow, deterministic, ownership-safe boundary between the
// SwiftUI application and the authoritative C++ IsolynEngine. See
// docs/BRIDGE_ARCHITECTURE.md for the full design rationale; this header is
// the contract itself, deliberately kept small enough to read end to end.
//
// GOVERNING RULES (see docs/BRIDGE_ARCHITECTURE.md for why each exists):
//
// 1. POD-only public surface. Every type below is a plain enum, a plain
//    struct of fixed-size fields (primitives, fixed C arrays, nested POD
//    structs), or a plain uint64_t handle. Nothing here is a std::vector,
//    std::string, std::optional, std::variant, reference, template, or
//    even a raw pointer -- Swift/C++ interop support for those is real
//    but this boundary deliberately does not depend on any of it, so the
//    exact toolchain version in whichever Xcode this is opened in cannot
//    silently change how (or whether) this header imports.
//
// 2. No exceptions cross this boundary. Every function below is
//    exception-safe: any C++ exception thrown underneath (the engine's
//    only throw site is EntropySource's OS-CSPRNG failure path -- see
//    IsolynBridge.cpp) is caught inside the .cpp and converted to a
//    BridgeStatus::EngineFailure result. Nothing here can unwind into
//    Swift.
//
// 3. This header enforces NOTHING about GAME state by itself -- it is not
//    internally thread-safe with respect to a session's own engine
//    state, and mutating calls on the SAME session must be serialized by
//    the caller (intended: a single Swift actor per session; see
//    docs/BRIDGE_ARCHITECTURE.md). This matches the underlying engine
//    exactly: IsolynEngine has zero internal synchronization primitives
//    (verified by direct audit -- zero mutex/atomic/thread usage
//    anywhere in Sources/IsolynEngine), so "the bridge is thread-safe"
//    would be a false claim; instead, this header is explicit about
//    exactly where the caller's own serialization obligation begins and
//    ends (see each function's comment) rather than pretending an
//    unenforced contract is a guarantee. The one exception is the small,
//    explicitly internally-synchronized handle-table bookkeeping itself
//    (rule 5) -- that part IS safe to call from multiple sessions'
//    threads concurrently, since a desktop app is not guaranteed to only
//    ever have one session alive.
//
// 4. Legality is enforced HERE, not assumed from the engine. A real,
//    audited fact about IsolynEngine: MatchController::playTurn and
//    MoveExecutor::apply only ASSERT their legality precondition
//    (MoveValidator::isLegal) -- assert() compiles to nothing under
//    NDEBUG, which Xcode Release builds define by default. Calling
//    either with an illegal move in a Release build is therefore
//    undefined behavior in the engine itself, not a safe rejection.
//    Every bridge_submit_move call below explicitly re-checks
//    MoveValidator::isLegal itself, in the .cpp, before ever touching
//    MatchController -- independent of build configuration. This is the
//    single most load-bearing design fact in this file.
//
// 5. Integer handles backed by a table, deliberately NOT raw/opaque
//    pointers. A SessionHandle/AnalysisHandle is an opaque uint64_t
//    token (0 is reserved as "never valid," returned on creation
//    failure) looked up in a small internal table on every call. This
//    was a deliberate choice over an opaque pointer for two concrete
//    reasons, not just a style preference: (a) it makes
//    bridge_session_close/bridge_analysis_snapshot_destroy GENUINELY
//    idempotent -- closing an already-closed handle is a safe table-miss
//    (BridgeStatus::SessionClosed / a harmless no-op), never a
//    use-after-free, which a raw "delete this pointer" design cannot
//    honestly claim against a caller that calls close twice; (b) plain
//    uint64_t values have zero ambiguity crossing into Swift regardless
//    of exactly which Cxx-interop version ends up importing this header,
//    unlike an opaque pointer type, which this project has no way to
//    verify without a Swift toolchain (see HANDOFF.md -- no session
//    building this codebase has ever had one). IDs are never reused
//    (monotonic per-process counters), so there is no ABA-style risk of
//    a stale handle silently addressing a different, later session.
//
// 6. State versioning for staleness rejection. Every mutating call takes
//    expectedStateVersion; a session tracks its own monotonically
//    increasing version, bumped on every successful mutation. A mismatch
//    fails closed with BridgeStatus::StaleRequest and mutates nothing.
//    This is also how duplicate/replayed commands are rejected: the
//    first occurrence of a submitted command bumps the version, so a
//    second, identical submission (same expectedStateVersion) is
//    automatically stale, not double-applied.
//
// ============================================================================

namespace isolyn::bridge {

// ---------------------------------------------------------------------------
// Handles
// ---------------------------------------------------------------------------

using SessionHandle = uint64_t;
using AnalysisHandle = uint64_t;
inline constexpr SessionHandle kInvalidSessionHandle = 0;
inline constexpr AnalysisHandle kInvalidAnalysisHandle = 0;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum class GameModeDTO : int32_t {
    OneVsOne = 0,
    OneVsOneVsOne = 1,
    TwoVsTwo = 2,
};

enum class ChainSideDTO : int32_t {
    Left = 0,
    Right = 1,
};

enum class RoundOutcomeDTO : int32_t {
    InProgress = 0,
    DominoVictory = 1,
    Closed = 2,
};

// Every failure mode a caller can observe. Deliberately specific enough
// to drive real UI behavior (e.g. StaleRequest vs InvalidMove are NOT the
// same user-facing situation) without exposing engine internals.
enum class BridgeStatus : int32_t {
    Ok = 0,
    InvalidRequest = 1,   // malformed input caught by the shim itself (e.g. out-of-range player index, out-of-range tile pips)
    InvalidMove = 2,      // MoveValidator::isLegal rejected this specific move
    SessionClosed = 3,    // handle is 0, unknown, or already closed
    StaleRequest = 4,     // expectedStateVersion did not match the session's current version
    NotYourTurn = 5,      // requestingPlayerIndex != currentPlayerIndex for a player-scoped command
    NoLegalMove = 6,      // e.g. bridge_resolve_forced_draw called while a legal move already exists
    BoneyardEmpty = 7,    // e.g. bridge_voluntary_draw called with drawableCount() == 0
    EngineFailure = 8,    // a genuine engine-thrown exception was caught (EntropySource CSPRNG failure)
    BridgeFailure = 9,    // an internal invariant the shim itself expected did not hold -- see IsolynBridge.cpp
    RoundAlreadyOver = 10,// a mutating command arrived after this session's round reached DominoVictory or Closed.
                          // Audit F-03: without this, a fresh-version command against a finished round would keep
                          // mutating state (a Closed position naturally rejects via legality, but a DOMINO VICTORY
                          // leaves other players holding legal moves -- play could continue past the round's end).
                          // Checked after the stale-version gate so an accidental duplicate tap still reports
                          // StaleRequest (idempotent), while a genuinely fresh command reports this.
};

// ---------------------------------------------------------------------------
// POD value types
// ---------------------------------------------------------------------------

// The game has exactly 28 tiles, full stop -- every fixed-size array below
// is sized against that hard, provable ceiling rather than a "realistic"
// smaller number, specifically because Sandbox Mode (docs/FEATURE_SPECS.md)
// is explicit that positions may be arbitrary and user-constructed, not
// only ever normally-dealt hands. Truncating real data to fit an assumed
// "typical" bound would silently corrupt whatever didn't fit -- see the
// mission statement's "must never... silently manufacture game state."
inline constexpr int32_t kTotalTileCount = 28;
inline constexpr int32_t kMaxPlayers = 4; // TwoVsTwo
inline constexpr int32_t kMaxLegalMoves = kTotalTileCount * 2; // each tile, both sides, upper bound

// low/high in [0, 6]; a value of -1 for both fields is used as an
// explicit "no tile" sentinel where a fixed slot may be unfilled (see
// boneyardLockedTiles below) -- never as a silent default, always
// checked against the relevant count field first.
struct TileDTO {
    int8_t low;
    int8_t high;
};

struct MoveDTO {
    TileDTO tile;
    ChainSideDTO side;
};

struct LegalMovesDTO {
    MoveDTO moves[kMaxLegalMoves];
    int32_t count;
};

struct ChainDTO {
    TileDTO tiles[kTotalTileCount];
    int32_t count;
    int32_t leftEnd;   // meaningful only when count > 0
    int32_t rightEnd;  // meaningful only when count > 0
};

// A snapshot is always taken FROM one specific player's point of view
// (requestingPlayerIndex). Only that player's own hand is populated with
// real tile identities; every other player's hand is exposed as a SIZE
// only. This is the mechanism that keeps hidden information hidden --
// see docs/BRIDGE_ARCHITECTURE.md's "Snapshot model" section. This is
// not a UI convenience choice: the shim has no way to know whether a
// future caller intends to render another player's hand, so it never
// hands over the data at all, the same way the C++ engine's own
// BeliefState/ProbabilityEngine design keeps hidden and known
// information structurally separate rather than trusting a caller not to
// look.
struct SnapshotDTO {
    BridgeStatus status; // check this FIRST -- every other field is meaningless if status != Ok

    uint64_t stateVersion;
    GameModeDTO mode;
    int32_t playerCount;
    int32_t requestingPlayerIndex;
    int32_t currentPlayerIndex;

    TileDTO ownHand[kTotalTileCount];
    int32_t ownHandCount;

    int32_t otherHandSizes[kMaxPlayers]; // entry [requestingPlayerIndex] is always 0 -- see ownHand instead

    ChainDTO chain;

    int32_t boneyardDrawableCount;
    TileDTO boneyardLockedTiles[2]; // {-1,-1} sentinel for a slot not yet revealed
    int32_t boneyardLockedCount;    // 0, 1 (never in practice, but not disallowed), or 2

    // Deliberately NO running match score field here. An EngineSession
    // wraps exactly one ROUND -- the same scope MatchController itself
    // has (see MatchController.hpp: "construct a fresh GameState for
    // each new round"). Match-level score accumulation across rounds is
    // ScoreSystem's job, is genuinely separate C++ state this bridge
    // does not yet own or wire up, and needs a real round-to-round
    // orchestration design (when does a new session get created for
    // round 2? who calls RulesEngine::determineNextRoundStarter and
    // holds the running ScoreSystem in between rounds?) that is real,
    // scoped, undone work -- not something to guess at here. See
    // docs/BRIDGE_ARCHITECTURE.md's "Explicitly out of scope" section.
    // roundOutcome/decidingPlayerIndex below are what THIS round
    // produced; turning that into match scores and starting the next
    // round is the caller's job for now.
    RoundOutcomeDTO roundOutcome;
    int32_t decidingPlayerIndex; // meaningful only if roundOutcome != InProgress

    // Populated ONLY when currentPlayerIndex == requestingPlayerIndex --
    // there is no legitimate reason to compute or expose legal moves for
    // a hand the requester cannot see, and every other player's hand is
    // exactly that. Zeroed (count == 0) otherwise.
    LegalMovesDTO legalMovesForRequestingPlayer;
};

struct CommandResultDTO {
    BridgeStatus status;
    uint64_t newStateVersion;      // meaningful only if status == Ok; unchanged session version otherwise
    RoundOutcomeDTO roundOutcome;  // meaningful only if status == Ok
    int32_t decidingPlayerIndex;   // meaningful only if status == Ok && roundOutcome != InProgress
    char diagnosticMessage[128];   // empty ("") on Ok; a short, non-sensitive, human-readable detail otherwise (never contains hidden game state)
};

struct AnalysisResultDTO {
    BridgeStatus status;             // BridgeFailure/EngineFailure only -- analysis has no InvalidMove/NotYourTurn/etc failure modes of its own
    uint64_t stateVersionAnalyzed;   // the session state version this snapshot was taken from -- compare against the session's CURRENT version yourself; a match does not by itself guarantee freshness if analysis ran a long time, only that nothing has mutated the session since
    bool completed;                  // false if cancellation cut this short -- see SearchEngine::chooseBestMove's own cancelRequested contract, which this passes through unchanged
    int32_t samplesCompleted;
    int32_t samplesConfigured;
    MoveDTO recommendedMove;         // a genuinely legal move even when completed is false and samplesCompleted is 0 (falls back to the first legal candidate) -- NEVER fabricated, but caller should treat samplesCompleted == 0 as "no real analysis happened, do not display this as a recommendation"
    double expectedValuePerPlayer[kMaxPlayers];
    int32_t playerCount;
};

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// Deals the first round of a brand-new match (MatchController::dealFirstRound
// underneath -- applies the once-per-match mandated opening tile
// automatically). Returns kInvalidSessionHandle (0) on an invalid mode or a
// genuine engine failure (EntropySource's CSPRNG throwing); check for that
// before use.
SessionHandle bridge_session_create_first_round(GameModeDTO mode);

// Deals a round after the first, with the given player already
// established as the starter (MatchController::dealSubsequentRound
// underneath -- chain starts empty, no mandated opening tile). Returns
// kInvalidSessionHandle (0) on an invalid mode, invalid startingPlayerIndex,
// or genuine engine failure.
SessionHandle bridge_session_create_subsequent_round(GameModeDTO mode, int32_t startingPlayerIndex);

// Genuinely idempotent (see rule 5 above): closing an already-closed or
// never-valid handle, including 0, is a safe no-op, not a crash and not
// undefined behavior. After this returns, the handle is permanently
// invalid -- it is never reused for a future session.
void bridge_session_close(SessionHandle session);

// ---------------------------------------------------------------------------
// Queries (non-mutating; still must be called from the session's serial
// context, since the engine's own GameState has no internal
// synchronization and a concurrent mutation could otherwise be observed
// mid-update)
// ---------------------------------------------------------------------------

SnapshotDTO bridge_get_snapshot(SessionHandle session, int32_t requestingPlayerIndex);

// ---------------------------------------------------------------------------
// Commands (mutating; caller MUST serialize ALL calls -- commands and
// queries alike -- against a single session on one execution context)
// ---------------------------------------------------------------------------

CommandResultDTO bridge_submit_move(SessionHandle session, uint64_t expectedStateVersion, MoveDTO move);
CommandResultDTO bridge_voluntary_draw(SessionHandle session, uint64_t expectedStateVersion);
CommandResultDTO bridge_resolve_forced_draw(SessionHandle session, uint64_t expectedStateVersion);
CommandResultDTO bridge_end_turn_with_no_play(SessionHandle session, uint64_t expectedStateVersion);

// ---------------------------------------------------------------------------
// Analysis -- the one deliberately two-phase part of this API. Phase 1
// is cheap and must run on the session's serial context (it reads live
// session state). Phase 2 is expensive and is SAFE to run on any thread,
// because by the time it is called it no longer touches the session at
// all -- see docs/BRIDGE_ARCHITECTURE.md's "Analysis / threading"
// section for the full reasoning (it rests directly on
// SearchEngine::chooseBestMove's own const-correctness and GameState's
// documented cheap-clone design).
// ---------------------------------------------------------------------------

// PHASE 1 -- must be called on the session's serial context. Cheap
// (one GameState copy, one BeliefState construction). Returns
// kInvalidAnalysisHandle (0) on invalid believerPlayerIndex, a closed
// session, OR if the session's current player does not currently have a
// legal move (SearchEngine::chooseBestMove's own precondition -- see
// IsolynBridge.cpp; call bridge_resolve_forced_draw first in that case,
// same as real play would).
AnalysisHandle bridge_analysis_snapshot_create(SessionHandle session, int32_t believerPlayerIndex);

// PHASE 2 -- safe to call from ANY thread once bridge_analysis_snapshot_create
// has returned; does not touch the originating session in any way. May
// take a while (bounded by maxDepthPlies x determinizationCount); this is
// the whole reason phase 2 is split out from phase 1. rngSeed is
// caller-supplied so production code can pass genuine fresh randomness
// each call while tests pass a fixed seed for determinism -- the shim
// itself has no opinion on which.
AnalysisResultDTO bridge_analysis_run(AnalysisHandle snapshot, int32_t maxDepthPlies,
                                       int32_t determinizationCount, uint64_t rngSeed);

// Safe to call from ANY thread, at any time after snapshot creation,
// including concurrently with an in-flight bridge_analysis_run on the
// SAME snapshot (that is precisely what this exists for). Does not
// itself stop bridge_analysis_run any faster than "finish whichever
// determinization sample is already in flight" -- see
// SearchEngine::chooseBestMove's own cancelRequested contract, which
// this is a thin pass-through to. Idempotent: calling it more than once,
// on an unknown handle, or on a snapshot where analysis already
// finished, is always harmless.
void bridge_analysis_request_cancel(AnalysisHandle snapshot);

// Genuinely idempotent, same as bridge_session_close. Should be called
// exactly once per snapshot in the ordinary case (after
// bridge_analysis_run has returned, or instead of ever calling it at all
// if the snapshot is being abandoned unused), but calling it again, or on
// an unknown/already-destroyed handle, is a safe no-op.
void bridge_analysis_snapshot_destroy(AnalysisHandle snapshot);

} // namespace isolyn::bridge
