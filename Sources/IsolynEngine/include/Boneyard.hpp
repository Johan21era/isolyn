#pragma once
#include <cassert>
#include <deque>
#include <vector>
#include "DominoTile.hpp"

namespace isolyn {

// The undealt tiles for a round -- non-empty only in 1v1 (Rules Spec
// setup: 14 remain after two 7-tile hands are dealt); always empty in
// 1v1v1 and 2v2, where the full 28 tiles are dealt out completely. Empty
// construction is not a special case here -- every method below already
// behaves correctly with zero tiles, so those two modes need no
// conditional logic anywhere in this class.
//
// Rules Spec Sec. 5: "the final two dominoes on the locked side remain
// visible but may never be touched," and the physical direction chosen
// for the first draw fixes which end that ends up being. There is no
// actual gameplay difference between the two physical directions -- both
// were already randomized by the shuffle before any draw happens -- so
// rather than modeling "direction" as a runtime choice with no real
// consequence, this class fixes a single canonical draw order once, at
// construction: draws always come from the front, and the final two
// positions in that same original order are always the ones that end up
// permanently locked. That single design choice is what lets
// drawableCount() below be a plain size-based formula instead of needing
// branching state.
class Boneyard {
public:
    explicit Boneyard(std::vector<DominoTile> tiles);

    bool isEmpty() const { return m_tiles.empty(); }
    std::size_t size() const { return m_tiles.size(); }

    // Tiles that can still legally be drawn -- always size() minus the
    // two permanently-locked tiles, floored at zero. Correctly yields
    // zero for an empty boneyard (1v1v1, 2v2) without any special-casing.
    std::size_t drawableCount() const {
        return m_tiles.size() >= 2 ? m_tiles.size() - 2 : 0;
    }

    // Draws and removes the next drawable tile. Precondition:
    // drawableCount() > 0.
    DominoTile drawNext();

    // Returns a tile to the front of the boneyard -- the exact inverse of
    // drawNext(). This exists purely for search/analysis undo and is
    // never a real in-game action: Rules Spec's Touching Dominoes section
    // is explicit that a drawn domino may never be returned during actual
    // play. Must only be called to reverse the most recent drawNext()
    // call.
    void undoDraw(DominoTile tile);

    // The two permanently-locked tiles -- visible per the rules, never
    // returned by drawNext(). Empty until at most two tiles remain
    // undrawn (which includes an empty boneyard to begin with).
    std::vector<DominoTile> lockedTiles() const;

    // Full remaining order, including the locked tail. Search needs this
    // for a state hash: draw order is part of the state, even though the
    // identities are hidden from every player. Exposed read-only; gameplay
    // never changes the order except through drawNext()/undoDraw().
    const std::deque<DominoTile>& remainingTiles() const { return m_tiles; }

private:
    std::deque<DominoTile> m_tiles;
};

} // namespace isolyn
