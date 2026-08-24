#pragma once
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

// Captures everything needed to exactly reverse a single applied Move.
// Returned by MoveExecutor::apply, consumed by MoveExecutor::undo.
struct AppliedMove {
    int playerIndex;
    Move move;
    GameState::PlacementKind kind;
};

// Applies and reverses Moves against a GameState. Does not itself decide
// legality (MoveValidator's job, before this is ever called) and does not
// decide WHICH move to make (EvaluationEngine/SearchEngine's job, much
// later). Pure mechanism: given a move already decided on, make it
// happen, and be able to take it back exactly.
class MoveExecutor {
public:
    // Precondition: MoveValidator::isLegal(state, playerIndex, move) is
    // true. Asserted, not re-validated -- a search loop may call this
    // many thousands of times per decision, so MoveExecutor trusts its
    // caller rather than re-running validation on every apply.
    static AppliedMove apply(GameState& state, int playerIndex, const Move& move);

    // Exact inverse of apply(). Must be called with the AppliedMove that
    // apply() returned, and only as the most recent not-yet-undone
    // apply() call against this exact GameState -- LIFO, mirroring
    // GameState/Chain's own undo stacks underneath.
    static void undo(GameState& state, const AppliedMove& applied);
};

} // namespace isolyn
