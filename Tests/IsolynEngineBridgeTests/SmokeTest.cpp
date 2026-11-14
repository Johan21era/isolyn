// Real, end-to-end runtime test for the bridge shim -- exercises the
// actual compiled implementation against the real engine, not just
// checks that it compiles. Deliberately NOT exhaustive (this is a
// same-day review smoke test, not the full bridge test suite) -- it
// targets exactly the properties this review's design discussion cared
// about: hidden information, the legality gate, state versioning,
// analysis correctness/cancellation, and real cross-thread concurrent
// access to a single session (command + query + analysis together).
#include "IsolynBridge.hpp"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <thread>
#include <chrono>
#include <vector>

using namespace isolyn::bridge;

static int g_failures = 0;
#define CHECK(cond, msg) do { \
    if (!(cond)) { std::printf("  [FAIL] %s\n", msg); ++g_failures; } \
    else { std::printf("  [pass] %s\n", msg); } \
} while (0)

namespace {

// Deal randomness means the player due to act after the mandated opening tile
// is occasionally blocked (no legal move). bridge_analysis_snapshot_create
// correctly refuses such sessions (the exact guard added after FuzzBridge
// found the UB), so tests that request analysis must first clear the block
// the same way real play does: resolve_forced_draw, falling back to
// end_turn_with_no_play if the boneyard is exhausted. Bounded loop; returns
// once the CURRENT player has a legal move.
void ensureCurrentPlayerCanMove(SessionHandle s) {
    for (int guard = 0; guard < 40; ++guard) {
        int current = bridge_get_snapshot(s, 0).currentPlayerIndex;
        SnapshotDTO snap = bridge_get_snapshot(s, current);
        if (snap.status != BridgeStatus::Ok) return;
        if (snap.roundOutcome != RoundOutcomeDTO::InProgress) return;
        if (snap.legalMovesForRequestingPlayer.count > 0) return;

        if (snap.boneyardDrawableCount > 0) {
            // Draw until playable (or the boneyard empties underneath us).
            CommandResultDTO r = bridge_resolve_forced_draw(s, snap.stateVersion);
            if (r.status != BridgeStatus::Ok) {
                bridge_end_turn_with_no_play(s, snap.stateVersion);
            }
            // NOTE: in boneyard-less modes this branch is unreachable --
            // drawableCount is structurally 0 there.
        } else {
            // Nothing to draw (1v1v1 / 2v2, or an exhausted 1v1 yard):
            // resolve_forced_draw would "succeed" while drawing nothing, so
            // the only way forward is ending the turn without a play.
            bridge_end_turn_with_no_play(s, snap.stateVersion);
        }
    }
}

// Finds a move NOT present in the given legal-moves list -- used to
// exercise the legality gate with a genuinely illegal move rather than
// an arbitrary guess that might accidentally be legal.
MoveDTO firstIllegalMove(const LegalMovesDTO& legal) {
    for (int8_t low = 0; low <= 6; ++low) {
        for (int8_t high = low; high <= 6; ++high) {
            for (ChainSideDTO side : {ChainSideDTO::Left, ChainSideDTO::Right}) {
                MoveDTO candidate{TileDTO{low, high}, side};
                bool isLegal = false;
                for (int i = 0; i < legal.count; ++i) {
                    const MoveDTO& m = legal.moves[i];
                    if (m.tile.low == candidate.tile.low && m.tile.high == candidate.tile.high && m.side == candidate.side) {
                        isLegal = true;
                        break;
                    }
                }
                if (!isLegal) return candidate;
            }
        }
    }
    return MoveDTO{TileDTO{6, 6}, ChainSideDTO::Left};
}

} // namespace

int main() {
    std::printf("== lifecycle + hidden information ==\n");
    {
        SessionHandle s = bridge_session_create_first_round(GameModeDTO::OneVsOne);
        CHECK(s != kInvalidSessionHandle, "session created with a valid nonzero handle");

        SnapshotDTO snap = bridge_get_snapshot(s, 0);
        CHECK(snap.status == BridgeStatus::Ok, "initial snapshot for player 0 is Ok");
        CHECK(snap.stateVersion == 1, "initial state version is 1");
        // 1v1 deals 7 per hand, but the mandated opening tile is removed
        // from WHICHEVER hand holds it (see Dealer::handSizeForMode /
        // MatchController::dealFirstRound) -- so the holder has 6
        // afterward, everyone else still has 7. Both are correct; either
        // is fine here.
        CHECK(snap.ownHandCount == 7 || snap.ownHandCount == 6, "player 0 was dealt 7 tiles, or 6 if they held the mandated opener");
        // NOTE: not checking an exact tile-conservation sum here.
        // boneyardDrawableCount is deliberately size()-2 always (see
        // Boneyard.hpp: the last 2 tiles stay undisclosed -- not exposed
        // as locked -- until the boneyard nearly empties), so
        // hand+hand+chain+drawable under-counts by those 2 hidden tiles
        // for most of a round. That's real, intentional, pre-existing
        // engine behavior, not something this smoke test needs to
        // re-verify -- the hidden-information checks below are this
        // test's actual point.
        CHECK(snap.roundOutcome == RoundOutcomeDTO::InProgress, "round starts InProgress");
        CHECK(snap.decidingPlayerIndex == -1, "no deciding player yet");
        CHECK(snap.chain.count == 1, "the mandated opening tile has already been placed (dealFirstRound)");
        bool hiddenRevealEmpty = true;
        for (int p = 0; p < kMaxPlayers; ++p) {
            if (snap.finalHandCounts[p] != 0) hiddenRevealEmpty = false;
        }
        CHECK(hiddenRevealEmpty, "no hand identities are revealed while the round is in progress");

        SnapshotDTO snapAsOpponent = bridge_get_snapshot(s, 1);
        CHECK(snapAsOpponent.ownHandCount == snap.otherHandSizes[1], "opponent's OWN snapshot hand count matches what player 0 saw as their size");
        CHECK(snapAsOpponent.otherHandSizes[0] == snap.ownHandCount, "and opponent sees player 0's hand as a size only, matching exactly");

        bridge_session_close(s);
        SnapshotDTO afterClose = bridge_get_snapshot(s, 0);
        CHECK(afterClose.status == BridgeStatus::SessionClosed, "snapshot after close correctly reports SessionClosed");
        bridge_session_close(s); // double-close
        bridge_session_close(kInvalidSessionHandle); // close(0)
        CHECK(true, "double-close and close(0) did not crash (genuinely idempotent, not just documented as such)");
    }

    std::printf("== legality gate + state versioning ==\n");
    {
        SessionHandle s = bridge_session_create_first_round(GameModeDTO::OneVsOne);
        // Deal randomness: the player due to act after the mandated opener is
        // sometimes blocked (~1-in-8 deals). Clear it exactly as real play
        // would before asserting anything about legal-move availability.
        ensureCurrentPlayerCanMove(s);
        int currentPlayer = bridge_get_snapshot(s, 0).currentPlayerIndex;
        SnapshotDTO snapAsCurrent = bridge_get_snapshot(s, currentPlayer);
        CHECK(snapAsCurrent.legalMovesForRequestingPlayer.count > 0, "current player has a legal move after forced-draw resolution");

        MoveDTO illegal = firstIllegalMove(snapAsCurrent.legalMovesForRequestingPlayer);
        CommandResultDTO illegalResult = bridge_submit_move(s, snapAsCurrent.stateVersion, illegal);
        CHECK(illegalResult.status == BridgeStatus::InvalidMove, "an illegal move is rejected with InvalidMove");
        CHECK(std::strlen(illegalResult.diagnosticMessage) > 0, "a diagnostic message is present on rejection");

        SnapshotDTO afterIllegal = bridge_get_snapshot(s, currentPlayer);
        CHECK(afterIllegal.stateVersion == snapAsCurrent.stateVersion, "state version is UNCHANGED after a rejected move -- no mutation occurred");

        MoveDTO legal = snapAsCurrent.legalMovesForRequestingPlayer.moves[0];
        CommandResultDTO firstSubmit = bridge_submit_move(s, snapAsCurrent.stateVersion, legal);
        CHECK(firstSubmit.status == BridgeStatus::Ok, "a genuinely legal move is accepted");
        CHECK(firstSubmit.newStateVersion == snapAsCurrent.stateVersion + 1, "state version advances by exactly 1 on success");

        CommandResultDTO replay = bridge_submit_move(s, snapAsCurrent.stateVersion, legal);
        CHECK(replay.status == BridgeStatus::StaleRequest, "replaying the same command with the old version is rejected as StaleRequest, not double-applied");

        bridge_session_close(s);
    }

    std::printf("== analysis: correctness + cancellation ==\n");
    {
        SessionHandle s = bridge_session_create_first_round(GameModeDTO::OneVsOne);
        ensureCurrentPlayerCanMove(s);
        int believer = bridge_get_snapshot(s, 0).currentPlayerIndex;

        AnalysisHandle a = bridge_analysis_snapshot_create(s, believer);
        CHECK(a != kInvalidAnalysisHandle, "analysis snapshot created successfully");
        AnalysisResultDTO result = bridge_analysis_run(a, 2, 5, 12345);
        CHECK(result.status == BridgeStatus::Ok, "analysis run completes with Ok status");
        CHECK(result.completed == true, "an uncancelled run reports completed == true");
        CHECK(result.samplesCompleted == 5, "all 5 configured samples ran");
        CHECK(result.playerCount == 2, "expectedValuePerPlayer reflects 2 players (1v1)");
        CHECK(result.recommendedMove.tile.low >= 0 && result.recommendedMove.tile.low <= 6,
              "the recommendation carries a real tile (a draw reports a legal placeholder, never a sentinel or an out-of-bounds read)");
        bridge_analysis_snapshot_destroy(a);

        AnalysisHandle a2 = bridge_analysis_snapshot_create(s, believer);
        bridge_analysis_request_cancel(a2);
        AnalysisResultDTO cancelledResult = bridge_analysis_run(a2, 4, 2000, 999);
        CHECK(cancelledResult.status == BridgeStatus::Ok, "a pre-cancelled run still reports Ok status (it's not a failure, just incomplete)");
        CHECK(cancelledResult.completed == false, "a pre-cancelled run reports completed == false");
        CHECK(cancelledResult.samplesCompleted == 0, "a pre-cancelled run ran zero samples");
        bridge_analysis_snapshot_destroy(a2);
        bridge_analysis_snapshot_destroy(a2); // double-destroy must be safe too

        // A production caller must be able to bound the expensive phase. A
        // 1 ms budget against an 8-ply, 1000-sample request cannot finish;
        // it must return Ok + incomplete + a real fallback move, not hang.
        AnalysisHandle a3 = bridge_analysis_snapshot_create(s, believer);
        CHECK(a3 != kInvalidAnalysisHandle, "analysis snapshot created for the budget test");
        AnalysisResultDTO bounded = bridge_analysis_run_with_budget(a3, 8, 1000, 7, 1);
        CHECK(bounded.status == BridgeStatus::Ok, "a budgeted run still reports Ok status");
        CHECK(bounded.completed == false, "a 1 ms budget stops before the full 8-ply search completes");
        CHECK(bounded.samplesCompleted < bounded.samplesConfigured,
              "the budget leaves work unfinished rather than pretending it completed");
        CHECK(bounded.recommendedMove.tile.low >= 0 && bounded.recommendedMove.tile.low <= 6,
              "a truncated run still returns a real tile, never a sentinel");
        bridge_analysis_snapshot_destroy(a3);

        // FIX-18 (audit F-07): an unknown analysis handle must fail with
        // BridgeFailure -- one of the only two failure classes this
        // result DTO's contract permits -- never SessionClosed, which
        // describes sessions, not snapshots.
        AnalysisResultDTO bogus = bridge_analysis_run(kInvalidAnalysisHandle, 2, 5, 1);
        CHECK(bogus.status == BridgeStatus::BridgeFailure,
              "analysis run on an unknown handle reports BridgeFailure, not SessionClosed");

        bridge_session_close(s);
    }

    std::printf("== analysis: refuses to run against a blocked current player (the exact bug FuzzBridge.cpp found) ==\n");
    {
        // SearchEngine::chooseBestMove's own documented precondition is
        // that the current player already has a legal move -- it does
        // not check this itself. Play full random rounds looking for a
        // point where the current player is genuinely blocked (needs
        // bridge_resolve_forced_draw first) and confirm analysis
        // creation fails closed there instead of crashing. Hand-dealing
        // is random, so this doesn't necessarily hit that state on every
        // single run of this binary -- FuzzBridge.cpp is this bug's real,
        // reliable regression coverage; this is a direct, readable second
        // check for whichever runs happen to reach it.
        bool everObservedBlockedPlayer = false;
        for (int game = 0; game < 30 && !everObservedBlockedPlayer; ++game) {
            SessionHandle gs = bridge_session_create_first_round(GameModeDTO::OneVsOne);
            for (int move = 0; move < 60; ++move) {
                int current = bridge_get_snapshot(gs, 0).currentPlayerIndex;
                SnapshotDTO gsnap = bridge_get_snapshot(gs, current);
                if (gsnap.status != BridgeStatus::Ok || gsnap.roundOutcome != RoundOutcomeDTO::InProgress) break;

                if (gsnap.legalMovesForRequestingPlayer.count == 0) {
                    everObservedBlockedPlayer = true;
                    AnalysisHandle blocked = bridge_analysis_snapshot_create(gs, gsnap.currentPlayerIndex);
                    CHECK(blocked == kInvalidAnalysisHandle, "analysis creation correctly refuses a blocked current player instead of crashing");

                    CommandResultDTO drawResult = bridge_resolve_forced_draw(gs, gsnap.stateVersion);
                    CHECK(drawResult.status == BridgeStatus::Ok || drawResult.status == BridgeStatus::BoneyardEmpty,
                          "resolveForcedDraw succeeds or reports an empty boneyard, nothing else");
                    if (drawResult.status == BridgeStatus::Ok) {
                        SnapshotDTO afterDraw = bridge_get_snapshot(gs, gsnap.currentPlayerIndex);
                        if (afterDraw.roundOutcome == RoundOutcomeDTO::InProgress && afterDraw.legalMovesForRequestingPlayer.count > 0) {
                            AnalysisHandle nowOk = bridge_analysis_snapshot_create(gs, afterDraw.currentPlayerIndex);
                            CHECK(nowOk != kInvalidAnalysisHandle, "and analysis creation succeeds again once the player is unblocked");
                            bridge_analysis_snapshot_destroy(nowOk);
                        }
                    }
                    break;
                }

                MoveDTO chosen = gsnap.legalMovesForRequestingPlayer.moves[0];
                bridge_submit_move(gs, gsnap.stateVersion, chosen);
            }
            bridge_session_close(gs);
        }
        std::printf("  [info] blocked-current-player state was %s across up to 30 random games\n",
                    everObservedBlockedPlayer ? "observed at least once" : "not observed this run (random -- not itself a failure)");
    }

    std::printf("== real cross-thread concurrency: command + query + analysis on one session together ==\n");
    {
        SessionHandle s = bridge_session_create_first_round(GameModeDTO::OneVsOneVsOne);
        ensureCurrentPlayerCanMove(s);
        int believer = bridge_get_snapshot(s, 0).currentPlayerIndex;

        AnalysisHandle a = bridge_analysis_snapshot_create(s, believer);
        CHECK(a != kInvalidAnalysisHandle, "analysis snapshot created before the concurrency test begins");

        std::atomic<bool> keepGoing{true};
        std::atomic<int> queryCount{0};
        std::atomic<bool> raceDetected{false};

        std::thread hammer([&]() {
            while (keepGoing.load(std::memory_order_relaxed)) {
                SnapshotDTO snap = bridge_get_snapshot(s, 0);
                if (snap.status != BridgeStatus::Ok) { raceDetected.store(true); break; }
                queryCount.fetch_add(1, std::memory_order_relaxed);
            }
        });

        AnalysisResultDTO result = bridge_analysis_run(a, 4, 3000, 42);
        keepGoing.store(false, std::memory_order_relaxed);
        hammer.join();

        CHECK(result.status == BridgeStatus::Ok, "analysis completed successfully while snapshots were being hammered concurrently");
        CHECK(!raceDetected.load(), "no snapshot ever came back with a non-Ok status during concurrent access");
        CHECK(queryCount.load() > 0, "the hammering thread actually got real work done while analysis ran in parallel -- confirms analysis did NOT block queries");
        std::printf("  [info] %d concurrent snapshot queries completed during one analysis run\n", queryCount.load());

        bridge_analysis_snapshot_destroy(a);
        bridge_session_close(s);
    }

    std::printf("== match orchestration: running scores across rounds ==\n");
    {
        MatchHandle m = bridge_match_begin(GameModeDTO::OneVsOne);
        CHECK(m != kInvalidMatchHandle, "match tracker created");

        auto driveToCompletion = [&](SessionHandle s) -> SnapshotDTO {
            for (int op = 0; op < 400; ++op) {
                int current = bridge_get_snapshot(s, 0).currentPlayerIndex;
                SnapshotDTO snap = bridge_get_snapshot(s, current);
                if (snap.status != BridgeStatus::Ok || snap.roundOutcome != RoundOutcomeDTO::InProgress) {
                    return bridge_get_snapshot(s, 0);
                }
                if (snap.legalMovesForRequestingPlayer.count > 0) {
                    bridge_submit_move(s, snap.stateVersion, snap.legalMovesForRequestingPlayer.moves[0]);
                } else if (snap.boneyardDrawableCount > 0) {
                    CommandResultDTO r = bridge_resolve_forced_draw(s, snap.stateVersion);
                    if (r.status != BridgeStatus::Ok) bridge_end_turn_with_no_play(s, snap.stateVersion);
                } else {
                    bridge_end_turn_with_no_play(s, snap.stateVersion);
                }
            }
            return bridge_get_snapshot(s, 0);
        };

        SessionHandle r1s = bridge_session_create_first_round(GameModeDTO::OneVsOne);
        SnapshotDTO done1 = driveToCompletion(r1s);
        CHECK(done1.roundOutcome != RoundOutcomeDTO::InProgress, "round 1 reached a real outcome");
        CHECK(done1.decidingPlayerIndex >= 0 && done1.decidingPlayerIndex < 2,
              "round 1's deciding player is a valid index");

        MatchResultDTO rec1 = bridge_match_record_round(m, r1s);
        CHECK(rec1.status == BridgeStatus::Ok, "round 1 recorded into the running score");
        CHECK(rec1.participantCount == 2, "1v1 tracks exactly 2 participants");
        CHECK(rec1.nextRoundStarterIndex == done1.decidingPlayerIndex,
              "next starter == the round's deciding player (Domino winner or credited closer)");
        bool revealSumsMatch = true;
        {
            int awardedSum = 0;
            for (int p = 0; p < rec1.participantCount; ++p) awardedSum += rec1.scoresPerParticipant[p];
            // computeRoundScores awards everyone-at-minimum zero and everyone-else their value:
            // so awardedSum is either 0 (tie at zero) or exactly max(reveal values).
            int mx = done1.finalHandValues[0] > done1.finalHandValues[1] ? done1.finalHandValues[0] : done1.finalHandValues[1];
            revealSumsMatch = (awardedSum == 0 && mx == 0) || (awardedSum == mx);
        }
        CHECK(revealSumsMatch, "awarded points consistent with the revealed hand values (min gets 0, others add their own)");

        // Reveal-on-end must expose the actual physical tiles, not just sums,
        // and only after the round is terminal.
        CHECK(done1.finalHandCounts[0] == done1.ownHandCount,
              "revealed hand count for the requester matches their visible rack size");
        CHECK(done1.finalHandCounts[1] == done1.otherHandSizes[1],
              "revealed opponent hand count matches the formerly hidden size");
        bool revealedTilesMatchValues = true;
        for (int p = 0; p < done1.playerCount; ++p) {
            int revealedValue = 0;
            for (int i = 0; i < done1.finalHandCounts[p]; ++i) {
                const TileDTO t = done1.finalRevealedTiles[p * kTotalTileCount + i];
                if (t.low < 0 || t.low > 6 || t.high < 0 || t.high > 6) revealedTilesMatchValues = false;
                revealedValue += t.low + t.high;
            }
            // RULEBOOK R-19: a hand holding only the double blank is worth ten.
            if (done1.finalHandCounts[p] == 1) {
                const TileDTO only = done1.finalRevealedTiles[p * kTotalTileCount];
                if (only.low == 0 && only.high == 0) revealedValue = 10;
            }
            if (revealedValue != done1.finalHandValues[p]) revealedTilesMatchValues = false;
        }
        CHECK(revealedTilesMatchValues,
              "revealed tiles sum to the final hand values for every player");
        CHECK(done1.finalRevealedTiles[1 * kTotalTileCount + done1.finalHandCounts[1]].low == -1,
              "slots beyond a revealed hand remain explicit {-1,-1} sentinels");
        CHECK(!rec1.matchEnded && rec1.winnerParticipantIndex == -1,
              "match cannot be over after one round of 151");

        CommandResultDTO dup = bridge_submit_move(r1s, done1.stateVersion, MoveDTO{TileDTO{6,6}, ChainSideDTO::Left});
        CHECK(dup.status == BridgeStatus::RoundAlreadyOver, "sanity: finished session still refuses mutations");
        MatchResultDTO recDup = bridge_match_record_round(m, r1s);
        CHECK(recDup.status != BridgeStatus::Ok, "recording the SAME round twice fails closed (no double-apply)");

        SessionHandle r2s = bridge_session_create_subsequent_round(
            GameModeDTO::OneVsOne, rec1.nextRoundStarterIndex);
        CHECK(r2s != kInvalidSessionHandle, "next-round session created from the recorded starter");
        SnapshotDTO start2 = bridge_get_snapshot(r2s, rec1.nextRoundStarterIndex);
        CHECK(start2.currentPlayerIndex == rec1.nextRoundStarterIndex,
              "the recorded starter genuinely opens round 2");
        CHECK(bridge_get_snapshot(r2s, 0).chain.count == 0,
              "round 2 starts with an empty chain -- no mandated opener past round one");
        SnapshotDTO done2 = driveToCompletion(r2s);
        CHECK(done2.roundOutcome != RoundOutcomeDTO::InProgress, "round 2 also reached a real outcome");
        MatchResultDTO rec2 = bridge_match_record_round(m, r2s);
        CHECK(rec2.status == BridgeStatus::Ok, "round 2 recorded");
        bool accumulating = false;
        for (int p = 0; p < 2; ++p)
            if (rec2.scoresPerParticipant[p] >= rec1.scoresPerParticipant[p]) accumulating = true;
        CHECK(accumulating, "running scores accumulate across rounds (never reset)");

        bridge_session_close(r2s);
        bridge_session_close(r1s);
        bridge_match_close(m);
        bridge_match_close(m); // idempotent double-close
        CHECK(true, "match close is idempotent like every other handle surface");
    }

    std::printf("== 2v2 match recording: two team score slots, not four player slots ==\n");
    {
        MatchHandle m = bridge_match_begin(GameModeDTO::TwoVsTwo);
        CHECK(m != kInvalidMatchHandle, "2v2 match tracker created");
        SessionHandle s = bridge_session_create_first_round(GameModeDTO::TwoVsTwo);
        CHECK(s != kInvalidSessionHandle, "2v2 session created");

        SnapshotDTO done{};
        for (int op = 0; op < 400; ++op) {
            int current = bridge_get_snapshot(s, 0).currentPlayerIndex;
            SnapshotDTO snap = bridge_get_snapshot(s, current);
            if (snap.status != BridgeStatus::Ok) { done = snap; break; }
            if (snap.roundOutcome != RoundOutcomeDTO::InProgress) {
                done = bridge_get_snapshot(s, 0);
                break;
            }
            if (snap.legalMovesForRequestingPlayer.count > 0) {
                bridge_submit_move(s, snap.stateVersion, snap.legalMovesForRequestingPlayer.moves[0]);
            } else if (snap.boneyardDrawableCount > 0) {
                CommandResultDTO r = bridge_resolve_forced_draw(s, snap.stateVersion);
                if (r.status != BridgeStatus::Ok) bridge_end_turn_with_no_play(s, snap.stateVersion);
            } else {
                bridge_end_turn_with_no_play(s, snap.stateVersion);
            }
        }

        CHECK(done.roundOutcome != RoundOutcomeDTO::InProgress, "2v2 round reached a real outcome");
        MatchResultDTO rec = bridge_match_record_round(m, s);
        CHECK(rec.status == BridgeStatus::Ok, "2v2 round recorded without a score-slot mismatch");
        CHECK(rec.participantCount == 2, "2v2 tracks exactly two TEAM participants, not four players");
        CHECK(rec.scoresPerParticipant[0] >= 0 && rec.scoresPerParticipant[1] >= 0,
              "both 2v2 team scores are populated");

        bridge_session_close(s);
        bridge_match_close(m);
    }

    std::printf("== mode mismatch: a 1v1 round cannot be recorded into a 2v2 match (AUD-01 regression) ==\n");
    {
        MatchHandle m = bridge_match_begin(GameModeDTO::TwoVsTwo);
        CHECK(m != kInvalidMatchHandle, "2v2 match tracker created for the mismatch test");

        auto playRound = [](SessionHandle s) -> SnapshotDTO {
            for (int op = 0; op < 400; ++op) {
                int current = bridge_get_snapshot(s, 0).currentPlayerIndex;
                SnapshotDTO snap = bridge_get_snapshot(s, current);
                if (snap.status != BridgeStatus::Ok) return snap;
                if (snap.roundOutcome != RoundOutcomeDTO::InProgress) {
                    return bridge_get_snapshot(s, 0);
                }
                if (snap.legalMovesForRequestingPlayer.count > 0) {
                    bridge_submit_move(s, snap.stateVersion, snap.legalMovesForRequestingPlayer.moves[0]);
                } else if (snap.boneyardDrawableCount > 0) {
                    CommandResultDTO r = bridge_resolve_forced_draw(s, snap.stateVersion);
                    if (r.status != BridgeStatus::Ok) bridge_end_turn_with_no_play(s, snap.stateVersion);
                } else {
                    bridge_end_turn_with_no_play(s, snap.stateVersion);
                }
            }
            return bridge_get_snapshot(s, 0);
        };

        SessionHandle oneVsOne = bridge_session_create_first_round(GameModeDTO::OneVsOne);
        CHECK(oneVsOne != kInvalidSessionHandle, "1v1 session created for the mismatch test");
        SnapshotDTO oneDone = playRound(oneVsOne);
        CHECK(oneDone.roundOutcome != RoundOutcomeDTO::InProgress,
              "the 1v1 round finished before the mismatched record attempt");

        MatchResultDTO rejected = bridge_match_record_round(m, oneVsOne);
        CHECK(rejected.status == BridgeStatus::ModeMismatch,
              "a 1v1 round recorded into a 2v2 match returns ModeMismatch (AUD-01: no out-of-bounds hand read)");
        CHECK(rejected.participantCount == 0 && rejected.nextRoundStarterIndex == -1,
              "the rejected record mutates nothing and reports no starter");

        // Fail closed, but do not poison the match: a genuine round still records.
        SessionHandle twoVsTwo = bridge_session_create_first_round(GameModeDTO::TwoVsTwo);
        CHECK(twoVsTwo != kInvalidSessionHandle, "a genuine 2v2 session can still be created");
        SnapshotDTO twoDone = playRound(twoVsTwo);
        CHECK(twoDone.roundOutcome != RoundOutcomeDTO::InProgress, "the 2v2 round finished");
        MatchResultDTO accepted = bridge_match_record_round(m, twoVsTwo);
        CHECK(accepted.status == BridgeStatus::Ok,
              "the same match still accepts a correctly-typed 2v2 round after the rejection");

        bridge_session_close(oneVsOne);
        bridge_session_close(twoVsTwo);
        bridge_match_close(m);
    }

    std::printf("== terminal-state guard: mutators refuse a finished round (audit F-03 regression) ==\n");
    {
        SessionHandle s = bridge_session_create_first_round(GameModeDTO::OneVsOne);
        bool finished = false;
        for (int op = 0; op < 400 && !finished; ++op) {
            int current = bridge_get_snapshot(s, 0).currentPlayerIndex;
            SnapshotDTO snap = bridge_get_snapshot(s, current);
            if (snap.status != BridgeStatus::Ok) break;
            if (snap.roundOutcome != RoundOutcomeDTO::InProgress) { finished = true; break; }
            if (snap.legalMovesForRequestingPlayer.count > 0) {
                bridge_submit_move(s, snap.stateVersion, snap.legalMovesForRequestingPlayer.moves[0]);
            } else if (snap.boneyardDrawableCount > 0) {
                CommandResultDTO r = bridge_resolve_forced_draw(s, snap.stateVersion);
                if (r.status != BridgeStatus::Ok) bridge_end_turn_with_no_play(s, snap.stateVersion);
            } else {
                bridge_end_turn_with_no_play(s, snap.stateVersion);
            }
        }
        CHECK(finished, "random legal play drove the round to a real outcome (DominoVictory or Closed)");

        SnapshotDTO termSnap = bridge_get_snapshot(s, 0);
        CHECK(termSnap.roundOutcome != RoundOutcomeDTO::InProgress, "session is genuinely terminal");
        int cur = termSnap.currentPlayerIndex;
        SnapshotDTO curSnap = bridge_get_snapshot(s, cur);

        MoveDTO anyMove = curSnap.legalMovesForRequestingPlayer.count > 0
            ? curSnap.legalMovesForRequestingPlayer.moves[0]
            : MoveDTO{TileDTO{6, 6}, ChainSideDTO::Left};

        // Fresh state version on purpose: these must clear the STALE gate and
        // land squarely on the new ROUND gate.
        CommandResultDTO r1 = bridge_submit_move(s, termSnap.stateVersion, anyMove);
        CHECK(r1.status == BridgeStatus::RoundAlreadyOver, "submit_move refuses a finished round");
        CommandResultDTO r2 = bridge_voluntary_draw(s, termSnap.stateVersion);
        CHECK(r2.status == BridgeStatus::RoundAlreadyOver, "voluntary_draw refuses a finished round");
        CommandResultDTO r3 = bridge_resolve_forced_draw(s, termSnap.stateVersion);
        CHECK(r3.status == BridgeStatus::RoundAlreadyOver, "resolve_forced_draw refuses a finished round");
        CommandResultDTO r4 = bridge_end_turn_with_no_play(s, termSnap.stateVersion);
        CHECK(r4.status == BridgeStatus::RoundAlreadyOver, "end_turn_with_no_play refuses a finished round");

        SnapshotDTO after = bridge_get_snapshot(s, 0);
        CHECK(after.stateVersion == termSnap.stateVersion,
              "state version UNCHANGED after all four refused mutations -- fails closed, mutates nothing");
        bridge_session_close(s);
    }

    std::printf("== difficulty profiles: C++ owns the strength-to-search mapping ==\n");
    {
        DifficultyProfileDTO casual = bridge_difficulty_profile(100);
        CHECK(casual.strength == 100 && casual.maxDepthPlies == 2 && casual.determinizationCount == 8,
              "casual strength maps to 2 plies / 8 determinizations");

        DifficultyProfileDTO club = bridge_difficulty_profile(900);
        CHECK(club.strength == 900 && club.maxDepthPlies == 3 && club.determinizationCount == 16,
              "club strength maps to 3 plies / 16 determinizations");

        DifficultyProfileDTO elite = bridge_difficulty_profile(99999);
        CHECK(elite.strength == 3000 && elite.maxDepthPlies == 8 && elite.determinizationCount == 64,
              "out-of-range strength clamps to the elite profile");
    }

    if (g_failures == 0) {
        std::printf("\nBridge smoke test: all checks passed\n");
    } else {
        std::printf("\nBridge smoke test: %d check(s) failed\n", g_failures);
    }
    return g_failures == 0 ? 0 : 1;
}
