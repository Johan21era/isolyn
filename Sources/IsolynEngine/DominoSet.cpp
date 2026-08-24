#include "DominoSet.hpp"
#include <utility>

namespace isolyn {

namespace {
template <std::size_t... Indices>
constexpr std::array<DominoTile, sizeof...(Indices)> buildAllTiles(std::index_sequence<Indices...>) {
    return { DominoTile::fromIndex(static_cast<int>(Indices))... };
}
} // namespace

const std::array<DominoTile, DominoTile::kTileCount>& DominoSet::allTiles() {
    static const auto tiles = buildAllTiles(std::make_index_sequence<DominoTile::kTileCount>{});
    return tiles;
}

std::vector<DominoTile> DominoSet::shuffledTiles(EntropySource& entropy) {
    const auto& all = allTiles();
    std::vector<DominoTile> tiles(all.begin(), all.end());
    entropy.shuffle(tiles);
    return tiles;
}

} // namespace isolyn
