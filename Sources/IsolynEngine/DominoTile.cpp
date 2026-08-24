#include "DominoTile.hpp"

namespace isolyn {

std::string DominoTile::describe() const {
    return std::to_string(m_low) + "-" + std::to_string(m_high);
}

} // namespace isolyn
