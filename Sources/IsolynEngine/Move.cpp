#include "Move.hpp"

namespace isolyn {

std::string Move::describe() const {
    return tile.describe() + (side == GameState::ChainSide::Left ? " (left)" : " (right)");
}

} // namespace isolyn
