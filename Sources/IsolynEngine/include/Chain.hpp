#pragma once
#include <cassert>
#include <deque>
#include <vector>
#include "DominoTile.hpp"

namespace isolyn {

// The played-domino layout. Rules Spec Sec. 6 is explicit that "the
// layout always remains a single chain with two playable ends" -- no
// spinner/branching behavior for doubles, unlike some domino variants.
// That single guarantee is what makes this representation this simple:
// just an ordered sequence with two tracked exposed values, never a tree.
class Chain {
public:
    bool isEmpty() const { return m_tiles.empty(); }

    // Exposed pip value at each end. Precondition: !isEmpty().
    int leftEnd() const { assert(!isEmpty()); return m_leftEnd; }
    int rightEnd() const { assert(!isEmpty()); return m_rightEnd; }

    // Places the very first tile of the round. For a double, both ends
    // trivially show its pip value. For a non-double opener (only
    // reachable via RulesEngine's no-doubles fallback), the low pip is
    // canonically placed on the left -- an arbitrary but deterministic
    // rendering choice, not a rule requirement; nothing downstream
    // depends on which orientation is picked, only on which values end
    // up exposed where.
    //
    // Precondition: isEmpty().
    void placeOpening(DominoTile tile);

    // Attaches to the given end. Preconditions: !isEmpty(), and tile has
    // a face matching that end's currently exposed value.
    void placeLeft(DominoTile tile);
    void placeRight(DominoTile tile);

    // Exact inverses of the three place* methods above, restoring both
    // the tile sequence and the exposed end values to precisely what they
    // were beforehand. This is LIFO undo, not general removal -- each
    // must be called in exact reverse order of the place* calls it
    // undoes. (Orientation isn't stored per-tile -- see orderedTiles()
    // below -- so a single isolated tile could not, on its own, tell you
    // which face used to be exposed before it was attached; these small
    // history stacks are what make restoring that O(1) instead of
    // needing to re-walk the whole chain from the opening tile to
    // re-derive it.)
    void undoOpening();
    void undoLeft();
    void undoRight();

    // Full sequence in left-to-right order, for serialization, replay,
    // and UI rendering. Per-tile orientation isn't stored separately --
    // it's always derivable by walking adjacent matches from either end,
    // so there's exactly one source of truth for what's on the board.
    const std::deque<DominoTile>& orderedTiles() const { return m_tiles; }

    // Constructs a Chain directly from an already-known, already-valid
    // state -- for reconstructing a chain whose orientation history
    // isn't available (SimulationEngine's determinized worlds; later,
    // PositionConstructor/loaded positions), rather than requiring it to
    // be rebuilt via placeOpening/placeLeft/placeRight. Trusts the
    // caller that `tiles` (left-to-right) and the given end values are
    // mutually consistent -- this reconstructs a state already known to
    // be valid, it does not validate one.
    //
    // The undo history starts empty for a chain built this way -- only
    // placements made AFTER this reconstruction can be undone; undoing
    // "into" the reconstructed base state is not supported and will
    // violate undoOpening's own precondition if attempted.
    static Chain fromKnownState(const std::deque<DominoTile>& tiles, int leftEnd, int rightEnd);

private:
    std::deque<DominoTile> m_tiles;
    int m_leftEnd = -1;
    int m_rightEnd = -1;
    std::vector<int> m_leftEndHistory;
    std::vector<int> m_rightEndHistory;
};

} // namespace isolyn
