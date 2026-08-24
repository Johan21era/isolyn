#include "Boneyard.hpp"
#include <cassert>

namespace isolyn {

Boneyard::Boneyard(std::vector<DominoTile> tiles)
    : m_tiles(tiles.begin(), tiles.end()) {}

DominoTile Boneyard::drawNext() {
    assert(drawableCount() > 0);
    DominoTile tile = m_tiles.front();
    m_tiles.pop_front();
    return tile;
}

void Boneyard::undoDraw(DominoTile tile) {
    m_tiles.push_front(tile);
}

std::vector<DominoTile> Boneyard::lockedTiles() const {
    if (m_tiles.size() > 2) return {};
    return std::vector<DominoTile>(m_tiles.begin(), m_tiles.end());
}

} // namespace isolyn
