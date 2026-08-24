#pragma once
#include <array>
#include <vector>
#include "DominoTile.hpp"
#include "EntropySource.hpp"

namespace isolyn {

// The fixed, immutable Double-Six domino set: exactly the 28 tiles defined
// by DominoTile's canonical indexing. This is a constant of the game, not
// game state -- GameState references tiles from here, it never owns a
// separate mutable copy of "the set".
class DominoSet {
public:
    // All 28 tiles, ordered by canonical index (see DominoTile::index()).
    static const std::array<DominoTile, DominoTile::kTileCount>& allTiles();

    // A freshly, genuinely shuffled ordering of all 28 tiles, via
    // EntropySource. Every call is independent -- no seed is stored or
    // reused, and every one of the 28! orderings is equally likely.
    static std::vector<DominoTile> shuffledTiles(EntropySource& entropy);
};

} // namespace isolyn
