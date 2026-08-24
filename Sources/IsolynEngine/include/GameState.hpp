#pragma once
#include <cassert>
#include <vector>
#include "Boneyard.hpp"
#include "Chain.hpp"
#include "DominoTile.hpp"
#include "GameMode.hpp"
#include "RulesEngine.hpp"

namespace isolyn {

// The complete state of a single round in progress: each player's hand,
// the played-tile chain, the boneyard, whose turn it is, and the play
// history RulesEngine::determineCloser needs at round end. Deliberately
// NOT the state of a whole match -- running scores and team pairings live
// one level up, in MatchController/ScoreSystem, which construct a fresh
// GameState for each new round.
//
// Cloning: every member here is a small, ordinary value type (vector,
// deque, int) with normal C++ copy semantics -- no custom copy
// constructor is defined or needed. The entire state for any mode tops
// out at 28 DominoTiles (2 bytes each) plus small container overhead, so
// a full value-copy of a GameState is already "rapid cloning" as the
// master prompt requires, without copy-on-write or any other cleverness
// -- a direct consequence of how small this game's state space is
// relative to something like a chess board.
//
// Undo: playTile reports which of three things it actually did (opened
// the chain / attached left / attached right) via PlacementKind, because
// that is information undoPlayTile needs and cannot safely re-derive
// after the fact from just (playerIndex, tile) -- state has already
// changed by then. The caller (MoveExecutor) is responsible for holding
// onto that PlacementKind and handing it back to undoPlayTile later. This
// is LIFO undo throughout, mirroring Chain's own undo stacks underneath:
// each undo* method here must be called only to reverse the most recent
// not-yet-undone call, in exact reverse order.
//
// Reconstruction: the extended constructor above also accepts an
// already-built Chain, an already-recorded play history, and an
// already-established current player -- every piece of this class's
// observable state -- for reconstructing a GameState representing a
// hypothetical world consistent with already-known public facts
// (SimulationEngine's determinized worlds), rather than requiring those
// facts to be rebuilt by replaying moves through playTile. All three
// default to their original empty/zero values, so every existing call
// site is unaffected.
class GameState {
public:
    enum class ChainSide { Left, Right };
    enum class PlacementKind { Opened, AttachedLeft, AttachedRight };

    // Precondition, asserted: if `initialCurrentPlayerIndex` is given
    // explicitly (or even at its default of 0), it must be a valid index
    // into `hands`.
    GameState(GameMode mode,
              std::vector<std::vector<DominoTile>> hands,
              std::vector<DominoTile> boneyardTiles,
              Chain initialChain = Chain(),
              std::vector<PlayRecord> initialPlayHistory = {},
              int initialCurrentPlayerIndex = 0);

    GameMode mode() const { return m_mode; }
    int playerCount() const { return static_cast<int>(m_hands.size()); }
    const std::vector<DominoTile>& hand(int playerIndex) const;

    const Chain& chain() const { return m_chain; }
    const Boneyard& boneyard() const { return m_boneyard; }

    int currentPlayerIndex() const { return m_currentPlayerIndex; }
    void setCurrentPlayerIndex(int index);

    const std::vector<PlayRecord>& playHistory() const { return m_playHistory; }

    // Removes `tile` from `playerIndex`'s hand and attaches it to the
    // chain at `side` (ignored, and the chain opened instead, if the
    // chain is currently empty). Records the play. Hand-removal and
    // chain-attachment happen together here, atomically, so the two can
    // never drift out of sync with each other -- this is the only place
    // either happens. Returns which of the three actually occurred, for
    // undoPlayTile to consume later.
    //
    // This method does not check legality -- that is MoveValidator's job
    // before it is ever called. It only guarantees that IF the call is
    // legal, state stays internally consistent.
    //
    // Precondition: playerIndex's hand contains tile; if the chain is
    // non-empty, tile has a face matching the given side's exposed value.
    PlacementKind playTile(int playerIndex, DominoTile tile, ChainSide side);

    // Exact inverse of a playTile call: returns `tile` to `playerIndex`'s
    // hand, reverses the chain attachment described by `kind` (exactly as
    // returned by that playTile call), and removes the corresponding
    // playHistory entry.
    void undoPlayTile(int playerIndex, DominoTile tile, PlacementKind kind);

    // Draws the next drawable boneyard tile into playerIndex's hand.
    // Precondition: boneyard().drawableCount() > 0.
    DominoTile drawTile(int playerIndex);

    // Exact inverse of a drawTile call, on the BONEYARD side: must be
    // called in exact reverse order of drawTile calls, same as every
    // other undo in this class (see Boneyard::undoDraw, which is
    // strictly LIFO and has no other way to reconstruct draw order).
    // Engine use only -- see Boneyard::undoDraw for why this is never a
    // real in-game action.
    //
    // On the HAND side, this locates and removes `tile` from wherever it
    // currently sits in playerIndex's hand -- deliberately NOT assumed to
    // still be the last element, the same way playTile's own removal
    // isn't order-dependent either (see playTile). A hand has no
    // meaningful internal order (real dominoes in a hand aren't stacked),
    // so nothing may assume draws and plays interleave in a way that
    // keeps a drawn tile at any particular position: SearchEngine's
    // searchNode routinely draws forced tiles for a player and then
    // applies/undoes several unrelated candidate moves on that same hand
    // before undoing the draw, and playTile+undoPlayTile's own
    // find-then-erase / push_back pattern does not preserve position
    // either. (A real, reproduced bug here -- not a hypothetical -- is
    // exactly why this comment is this explicit: undoDrawTile used to
    // assume hand.back(), which a single intervening playTile/
    // undoPlayTile cycle on an unrelated tile could silently invalidate.)
    void undoDrawTile(int playerIndex, DominoTile tile);

private:
    GameMode m_mode;
    std::vector<std::vector<DominoTile>> m_hands;
    Chain m_chain;
    Boneyard m_boneyard;
    int m_currentPlayerIndex = 0;
    std::vector<PlayRecord> m_playHistory;
};

} // namespace isolyn
