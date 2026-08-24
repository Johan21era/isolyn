#pragma once
#include <utility>
#include <vector>
#include "DominoTile.hpp"
#include "GameMode.hpp"

namespace isolyn {

struct OpeningDecision {
    int openingPlayerIndex;
    DominoTile openingTile;
};

// One entry in the ordered history of dominoes played during a round.
// Deliberately minimal and self-contained rather than depending on
// GameState -- RulesEngine's closing logic only needs to know who played
// what, in order, not the full board/turn representation GameState will
// eventually own. Kept general enough that GameState can build this list
// as a byproduct of its own move history once it exists.
struct PlayRecord {
    int playerIndex;
    DominoTile tile;
};

// Pure, deterministic codification of Rules Spec. Covers opening-domino
// determination, closing/Domino-victory distinction, scoring, and
// next-round-starter logic. Setup/Misdeal detection lives in Dealer, not
// here -- RulesEngine assumes a legally-dealt position throughout.
class RulesEngine {
public:
    // Determines who opens the first round of a match and with which
    // domino, given each player's starting hand.
    //
    // Rules Spec Sec. 4: highest available double opens (6-6 down to
    // 0-0, ranked by pip value -- any double, even 0-0, outranks every
    // non-double). If no player holds any double, the highest-value
    // plain domino opens instead. That fallback exists only in Rules
    // Spec -- Concept Spec says "no exceptions" and doesn't address the
    // case -- and Rules Spec, being the literal finished ruleset, is
    // what governs here.
    //
    // Precondition: hands is non-empty and every hand is non-empty.
    // Enforcing that is Dealer's responsibility, not this function's --
    // RulesEngine assumes a legally-dealt set of hands and does not
    // re-validate what Dealer already guarantees.
    static OpeningDecision determineOpeningPlay(const std::vector<std::vector<DominoTile>>& hands);

    // Determines who is credited as the closer of a round that ended in a
    // Close (i.e. playedMoves.back() left no legal move for any player,
    // and no player emptied their hand -- Domino victory is a separate,
    // higher-precedence outcome this function does not decide between;
    // the caller establishes that a Close, not a Domino, occurred before
    // calling this).
    //
    // Rules Spec Sec. 9, "Doubles Cannot Close" (1v1 only): a double is
    // never the official closing domino. If the move that created the
    // close was a double, credit goes instead to whoever played the most
    // recent preceding non-double -- walking back through an entire run
    // of consecutive doubles if necessary. Explicitly 1v1-only: 1v1v1 and
    // 2v2 both state outright that doubles ARE allowed to close, so for
    // those modes this is simply "whoever played the last move."
    //
    // Open question, not addressed by either document: if every play in
    // the entire round was a double (no non-double exists to walk back
    // to), neither text says what happens. Falls back to crediting
    // whoever played last rather than guessing further or crashing --
    // flagged here rather than presented as settled.
    //
    // Precondition: playedMoves is non-empty.
    static int determineCloser(GameMode mode, const std::vector<PlayRecord>& playedMoves);

    // Given each participant's remaining hand value at round end (one
    // entry per player for 1v1/1v1v1, one entry per TEAM's combined value
    // for 2v2 -- see combineTeamValue), computes the score each
    // participant adds to their running match total this round.
    //
    // Unifies Domino-victory and Closed-round scoring -- Rules Spec states
    // them as separate rules per mode, but a Domino winner's hand is
    // always trivially zero, which is always the minimum, so "whoever has
    // the minimum remaining value gets zero, everyone strictly above it
    // adds their own value" reproduces every worked Domino example in
    // both documents without a separate code path. It also generalizes
    // 1v1's explicit tie rule ("if both scores are identical, no points
    // are awarded") to any number of participants: every participant AT
    // the minimum gets zero, which for exactly two tied participants is
    // the same outcome as "neither one's score changes." Extending
    // 1v1v1's "the player with the fewest" to a tie-for-fewest among 3+
    // participants the same way is this function's own generalization,
    // not an explicit example in either document.
    static std::vector<int> computeRoundScores(const std::vector<int>& remainingValues);

    // Combines two 2v2 partners' individual remaining hand values into
    // their team's single combined value, for use as one entry in
    // computeRoundScores. ("Team scores equal the combined value of both
    // remaining hands.")
    static int combineTeamValue(int partnerAValue, int partnerBValue);

    static constexpr int kOneVsOneMatchLossThreshold = 101;
    static constexpr int kOneVsOneVsOneMatchLossThreshold = 101;
    static constexpr int kTwoVsTwoMatchLossThreshold = 151;

    // Whether a running score has reached or exceeded the mode's
    // match-loss threshold ("reaches OR EXCEEDS" -- the threshold value
    // itself already loses, not just scores strictly above it).
    static bool hasReachedMatchLossThreshold(GameMode mode, int runningScore);

    // Who starts the next round, given who just won by Domino or was
    // credited as the closer. A one-line pass-through by design: Rules
    // Spec Sec. 4 states this holds "even if the close ends in a tie," so
    // this determination is deliberately independent of the round's
    // *scoring* outcome. Kept as its own named function -- rather than
    // inlined wherever MatchController needs it -- so that invariant has
    // one explicit, citable, searchable home instead of being folklore.
    static int determineNextRoundStarter(int winnerOrCloserPlayerIndex);

    // 2v2-only: which team (0 or 1) a player index belongs to. Partners
    // sit opposite one another (Rules Spec Sec. 11) -- the natural turn
    // order around a table with opposite-seated partners alternates
    // teams every turn (you, opponent, your partner, other opponent),
    // which is what fixes this specific mapping: indices 0 and 2 are one
    // team, 1 and 3 are the other. Neither document states this mapping
    // explicitly; it's inferred from "partners sit opposite" plus
    // standard partnership-game seating convention -- confident enough
    // to implement, not certain enough to treat as settled. Lives here,
    // not in MatchController, because both turn ordering AND evaluation
    // scoring need it -- a shared rules-level fact, not an orchestration
    // detail.
    static int teamIndexForPlayer(int playerIndex);

    // 2v2-only: the two player indices on the given team (0 or 1).
    static std::pair<int, int> playersOnTeam(int teamIndex);
};

} // namespace isolyn
