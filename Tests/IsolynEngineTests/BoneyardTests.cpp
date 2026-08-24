#include "Boneyard.hpp"
#include "TestHarness.hpp"

using isolyn::Boneyard;
using isolyn::DominoTile;
using namespace isolyn::test;

int main() {
    section("Boneyard: empty construction (1v1v1 / 2v2) is not a special case");
    {
        Boneyard empty({});
        check(empty.isEmpty(), "an empty boneyard reports empty");
        check(empty.drawableCount() == 0, "an empty boneyard has zero drawable tiles");
        check(empty.lockedTiles().empty(), "an empty boneyard has no locked tiles to reveal");
    }

    section("Boneyard: 1v1's 14-tile boneyard has 12 drawable, 2 locked");
    {
        std::vector<DominoTile> tiles;
        for (int i = 0; i < 14; ++i) tiles.push_back(DominoTile::fromIndex(i));
        Boneyard boneyard(tiles);
        check(boneyard.size() == 14, "starts with all 14 tiles");
        check(boneyard.drawableCount() == 12, "12 of the 14 are drawable");
        check(boneyard.lockedTiles().empty(), "the locked pair isn't revealed while 12 drawable tiles remain");
    }

    section("Boneyard: drawing shrinks drawableCount and preserves front-to-back order");
    {
        std::vector<DominoTile> tiles = { DominoTile(1, 1), DominoTile(2, 2), DominoTile(3, 3), DominoTile(4, 4) };
        Boneyard boneyard(tiles);
        check(boneyard.drawableCount() == 2, "4 tiles in, 2 drawable, 2 locked");

        DominoTile first = boneyard.drawNext();
        check(first == DominoTile(1, 1), "drawNext() returns tiles in front-to-back order");
        check(boneyard.drawableCount() == 1, "drawableCount() drops by one after a draw");
        check(boneyard.size() == 3, "size() also drops by one -- the tile is physically removed");

        DominoTile second = boneyard.drawNext();
        check(second == DominoTile(2, 2), "second draw continues the same front-to-back order");
        check(boneyard.drawableCount() == 0, "down to exactly the two locked tiles -- nothing left to draw");
    }

    section("Boneyard: the locked pair becomes visible once drawableCount hits zero");
    {
        std::vector<DominoTile> tiles = { DominoTile(1, 1), DominoTile(2, 2), DominoTile(3, 3), DominoTile(4, 4) };
        Boneyard boneyard(tiles);
        boneyard.drawNext();
        boneyard.drawNext();
        auto locked = boneyard.lockedTiles();
        check(locked.size() == 2, "exactly two tiles remain, both now reported as locked");
        check(locked[0] == DominoTile(3, 3) && locked[1] == DominoTile(4, 4),
              "the locked pair is whichever two were originally last in draw order");
    }

    section("Boneyard: undoDraw is the exact inverse of drawNext (engine/search use only)");
    {
        std::vector<DominoTile> tiles = { DominoTile(1, 1), DominoTile(2, 2), DominoTile(3, 3), DominoTile(4, 4) };
        Boneyard boneyard(tiles);
        DominoTile drawn = boneyard.drawNext();
        check(boneyard.size() == 3, "size drops after a draw");

        boneyard.undoDraw(drawn);
        check(boneyard.size() == 4, "undoDraw restores the physical count");
        check(boneyard.drawableCount() == 2, "undoDraw restores drawableCount too, not just size");
        DominoTile redrawn = boneyard.drawNext();
        check(redrawn == drawn, "the undone tile is exactly what gets drawn again, in the same position");
    }

    if (failureCount() == 0) {
        std::cout << "\nBoneyard: all checks passed\n";
        return 0;
    }
    std::cout << "\nBoneyard: " << failureCount() << " check(s) failed\n";
    return 1;
}
