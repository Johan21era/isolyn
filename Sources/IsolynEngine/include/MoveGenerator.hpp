#pragma once
#include <array>
#include <cstddef>
#include <vector>
#include "GameState.hpp"
#include "Move.hpp"

namespace isolyn {

// Produces every legal placement candidate for a given player's current
// hand against the current chain. Does not consider drawing (see Move's
// own documentation for why) and does not special-case the once-per-round
// opening rule -- for an empty chain, every hand tile is returned as a
// candidate opener; which ONE of those is actually mandated by Rules Spec
// Sec. 4 (highest double, or highest plain if nobody holds one) is
// RulesEngine::determineOpeningPlay's job, decided once by MatchController
// before this class is ever consulted for a real game's first move. This
// class stays total and correct on its own terms regardless -- it doesn't
// assume it will never be asked about an empty chain.
class MoveGenerator {
public:
    // A hand can never produce more than two candidates per tile, and a
    // standard round never puts more than 28 tiles in one hand. This bound
    // lets search keep its candidate list on the stack instead of allocating
    // a vector at every node.
    static constexpr std::size_t kMaxMoves = 64;

    static std::vector<Move> generate(const GameState& state, int playerIndex);

    // Allocation-free variant used by the search hot path. Writes candidates
    // into `moves` and returns how many were written. Equivalent, in order,
    // to generate(state, playerIndex).
    static std::size_t generateInto(const GameState& state,
                                    int playerIndex,
                                    std::array<Move, kMaxMoves>& moves) noexcept;

    // Short-circuiting existence check -- for MatchController's forced-draw
    // loop ("keep drawing until this is true or the boneyard is empty")
    // without paying for a full move list just to test non-emptiness.
    static bool hasAnyLegalMove(const GameState& state, int playerIndex);

    // Allocation-free mobility count. Equivalent to
    // generate(state, playerIndex).size(), but used by the evaluation
    // heuristics on every leaf -- building a vector there was pure waste.
    static int countLegalMoves(const GameState& state, int playerIndex);

    // Whether NO player has any legal move AND the boneyard (if one
    // exists) has nothing left to draw -- the complete condition for a
    // Close (Rules Spec Sec. 7: "no further legal moves exist"). Shared
    // by MatchController (real turn-flow) and EvaluationEngine (scoring
    // a concrete, possibly-hypothetical state) so this exact condition
    // is computed in exactly one place.
    static bool isPositionClosed(const GameState& state);
};

} // namespace isolyn
