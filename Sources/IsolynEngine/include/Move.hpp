#pragma once
#include <string>
#include "DominoTile.hpp"
#include "GameState.hpp"

namespace isolyn {

// A single legal placement candidate: play `tile` against `side` of the
// chain. `side` is meaningless, though harmless, when the chain is
// currently empty -- the very first play of a round always opens the
// chain regardless of which side is specified (see
// GameState::playTile).
//
// Deliberately does NOT represent drawing. Drawing (voluntary or forced)
// doesn't consume a turn, isn't constrained by "which tile" the way a
// placement is, and its sequencing -- when a player may draw, how much,
// when they must stop -- is turn-flow logic that belongs to
// MatchController, not to the Move/MoveGenerator/MoveValidator/
// MoveExecutor system, which is scoped to placement only.
struct Move {
    DominoTile tile;
    GameState::ChainSide side;

    bool operator==(const Move& other) const {
        return tile == other.tile && side == other.side;
    }

    std::string describe() const;
};

} // namespace isolyn
