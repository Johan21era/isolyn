#pragma once
#include <utility>
#include <vector>
#include "Dealer.hpp"
#include "EntropySource.hpp"
#include "GameMode.hpp"
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

enum class RoundOutcomeKind { InProgress, DominoVictory, Closed };

struct RoundOutcome {
    RoundOutcomeKind kind;
    // Valid only when kind != InProgress: the Domino winner, or the
    // player RulesEngine::determineCloser credited for a Close.
    int decidingPlayerIndex = -1;
};

// Orchestrates a single round's turn flow: the mandated opening play,
// whose turn it is, voluntary and forced drawing, and Domino/Close
// detection after every play. Does not decide WHICH move to make, or
// WHETHER to voluntarily draw -- those are strategic choices belonging to
// whoever is driving a given player's turn (a human via UI, or later an
// engine via EvaluationEngine/SearchEngine), never to this class. Pure
// turn-flow mechanism, same philosophy as MoveExecutor.
//
// NOT YET IMPLEMENTED: the 1v1-only "One Domino Rule" (Rules Spec Sec.
// 9) -- when both players hold exactly one domino, each must draw one
// before attempting to finish, continuing until someone wins, the
// boneyard is exhausted, or a player must draw more than one domino.
// The exact mechanics of that repeating cycle are genuinely
// underspecified by both source documents -- specifically, how a Domino
// victory can occur *within* it at all, given normal play is exactly one
// placement per turn (draw-one-then-play-one always nets back to the
// same hand size, never down to zero). Several readings were worked
// through and none is clearly the intended one. Deliberately left out
// rather than guessed at; flagged for discussion. Ordinary Mandatory
// Play and Forced Drawing, both implemented below, already govern every
// other 1v1 endgame correctly -- only this specific
// both-down-to-one-tile scenario needs it.
class MatchController {
public:
    // Deals the very first round of a brand new match: the mandated
    // opening play (RulesEngine::determineOpeningPlay's highest-double,
    // or highest-plain-if-no-doubles across every hand) is determined and
    // applied automatically.
    //
    // Rules Spec Sec. 4 scopes this to "the first round" specifically --
    // "Beginning Future Rounds" is a separate rule that says only WHO
    // starts a later round (the Domino winner or credited closer), never
    // which tile they must open with. That scoping isn't just textual:
    // the highest-double/highest-plain comparison requires seeing every
    // player's hand at once, which only makes sense before anyone has
    // hidden anything from anyone -- at the very first deal. A real
    // player starting round 2 cannot see an opponent's hand to know
    // which tile they'd be "required" to open with; they freely choose,
    // exactly like any other turn. Use dealSubsequentRound for every
    // round after the first.
    static MatchController dealFirstRound(GameMode mode, EntropySource& entropy);

    // Deals a round after the first one in a match, where the starting
    // player is already fixed by the previous round's outcome
    // (RulesEngine::determineNextRoundStarter applied to that round's
    // Domino winner or credited closer). The chain is left empty --
    // there is no mandated opening tile past round one (see
    // dealFirstRound) -- so the starting player's first move is an
    // ordinary, freely-chosen playTurn() call like any other turn; an
    // empty chain already accepts any hand tile as a legal candidate, no
    // special-casing needed here.
    static MatchController dealSubsequentRound(GameMode mode, EntropySource& entropy, int startingPlayerIndex);

    // Constructs around an already-existing GameState -- for tests,
    // sandbox positions, and loaded positions, none of which should go
    // through a fresh Dealer shuffle or either opening-round rule above.
    // Uses the state's mode() and currentPlayerIndex() exactly as given.
    explicit MatchController(GameState state);

    const GameState& state() const { return m_state; }
    int currentPlayerIndex() const { return m_state.currentPlayerIndex(); }

    // Whether the current player has any legal move right now, without
    // drawing. False means their turn needs resolveForcedDraw() before
    // (or instead of) any play.
    bool currentPlayerHasLegalMove() const;

    // Draws one tile into the current player's hand. For voluntary
    // drawing: callable any number of times, by whatever external
    // decision-maker chooses to call it, for as long as
    // state().boneyard().drawableCount() > 0. This class does not decide
    // WHETHER to voluntarily draw.
    DominoTile voluntaryDraw();

    // The deterministic, rules-mandated forced-draw loop (Rules Spec
    // Sec. 5): draws for the current player until either a playable tile
    // is obtained or the boneyard is exhausted. Returns every tile
    // drawn, in order. No decision-making involved, unlike
    // voluntaryDraw -- which is why this is one method rather than
    // something the caller loops externally.
    //
    // Precondition: !currentPlayerHasLegalMove().
    std::vector<DominoTile> resolveForcedDraw();

    // Applies `move` for the current player, advances whose turn it is,
    // and returns the resulting RoundOutcome.
    //
    // Precondition: MoveValidator::isLegal(state(), currentPlayerIndex(),
    // move) is true.
    RoundOutcome playTurn(const Move& move);

    // If resolveForcedDraw() exhausts the boneyard without producing a
    // playable tile, the current player's turn ends immediately with no
    // play (Rules Spec Sec. 5). Call this to advance to the next player
    // and check whether the round has become Closed as a result. No
    // Domino-victory path here, since no play was made.
    RoundOutcome endTurnWithNoPlay();

private:
    MatchController(GameMode mode, DealResult dealt);

    void advanceToNextPlayer();
    RoundOutcome checkForClose() const;

    GameMode m_mode;
    GameState m_state;
};

} // namespace isolyn
