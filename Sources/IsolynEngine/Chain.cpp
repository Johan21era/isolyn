#include "Chain.hpp"
#include <cassert>

namespace isolyn {

void Chain::placeOpening(DominoTile tile) {
    assert(isEmpty());
    m_tiles.push_back(tile);
    m_leftEnd = tile.low();
    m_rightEnd = tile.high();
}

void Chain::placeLeft(DominoTile tile) {
    assert(!isEmpty());
    assert(tile.hasFace(m_leftEnd));
    m_leftEndHistory.push_back(m_leftEnd);
    m_tiles.push_front(tile);
    m_leftEnd = (tile.low() == m_leftEnd) ? tile.high() : tile.low();
}

void Chain::placeRight(DominoTile tile) {
    assert(!isEmpty());
    assert(tile.hasFace(m_rightEnd));
    m_rightEndHistory.push_back(m_rightEnd);
    m_tiles.push_back(tile);
    m_rightEnd = (tile.low() == m_rightEnd) ? tile.high() : tile.low();
}

void Chain::undoOpening() {
    assert(m_tiles.size() == 1 && m_leftEndHistory.empty() && m_rightEndHistory.empty() &&
           "undoOpening requires every later placement to have already been undone");
    m_tiles.pop_back();
    m_leftEnd = -1;
    m_rightEnd = -1;
}

void Chain::undoLeft() {
    assert(!m_leftEndHistory.empty());
    m_tiles.pop_front();
    m_leftEnd = m_leftEndHistory.back();
    m_leftEndHistory.pop_back();
}

void Chain::undoRight() {
    assert(!m_rightEndHistory.empty());
    m_tiles.pop_back();
    m_rightEnd = m_rightEndHistory.back();
    m_rightEndHistory.pop_back();
}

Chain Chain::fromKnownState(const std::deque<DominoTile>& tiles, int leftEnd, int rightEnd) {
    Chain chain;
    chain.m_tiles = tiles;
    chain.m_leftEnd = leftEnd;
    chain.m_rightEnd = rightEnd;
    return chain;
}

} // namespace isolyn
