#include "Chain.hpp"
#include "TestHarness.hpp"

using isolyn::Chain;
using isolyn::DominoTile;
using namespace isolyn::test;

int main() {
    section("Chain: opening with a double exposes the same value both ends");
    {
        Chain chain;
        chain.placeOpening(DominoTile(6, 6));
        check(chain.leftEnd() == 6 && chain.rightEnd() == 6, "6-6 opens with both ends showing 6");
    }

    section("Chain: opening with a non-double, canonical low-left orientation");
    {
        Chain chain;
        chain.placeOpening(DominoTile(6, 5));
        check(chain.leftEnd() == 5 && chain.rightEnd() == 6, "6-5 opens with the low pip (5) on the left");
    }

    section("Chain: attaching to the left updates the left end, leaves right untouched");
    {
        Chain chain;
        chain.placeOpening(DominoTile(4, 4));
        chain.placeLeft(DominoTile(4, 2));
        check(chain.leftEnd() == 2, "attaching 4-2 to a 4-showing left end exposes the non-matching face (2)");
        check(chain.rightEnd() == 4, "the right end is untouched by a left-side attachment");
    }

    section("Chain: attaching to the right updates the right end, leaves left untouched");
    {
        Chain chain;
        chain.placeOpening(DominoTile(4, 4));
        chain.placeRight(DominoTile(4, 1));
        check(chain.rightEnd() == 1, "attaching 4-1 to a 4-showing right end exposes the non-matching face (1)");
        check(chain.leftEnd() == 4, "the left end is untouched by a right-side attachment");
    }

    section("Chain: attaching a double to a matching end keeps that end's value unchanged");
    {
        Chain chain;
        chain.placeOpening(DominoTile(6, 5));
        chain.placeRight(DominoTile(6, 6));
        check(chain.rightEnd() == 6, "playing 6-6 against a 6-showing end leaves that end still showing 6");
    }

    section("Chain: orderedTiles reflects true left-to-right insertion order");
    {
        Chain chain;
        chain.placeOpening(DominoTile(3, 3));
        chain.placeRight(DominoTile(3, 1));
        chain.placeLeft(DominoTile(3, 5));
        const auto& ordered = chain.orderedTiles();
        check(ordered.size() == 3, "three tiles placed, three tiles in the sequence");
        check(ordered[0] == DominoTile(3, 5), "left-placed tile ends up first in left-to-right order");
        check(ordered[1] == DominoTile(3, 3), "the opening tile stays in the middle");
        check(ordered[2] == DominoTile(3, 1), "right-placed tile ends up last in left-to-right order");
    }

    section("Chain: undoLeft and undoRight restore the prior end value, not just remove the tile");
    {
        Chain chain;
        chain.placeOpening(DominoTile(4, 4));  // leftEnd=4, rightEnd=4
        chain.placeLeft(DominoTile(4, 2));      // leftEnd becomes 2
        chain.undoLeft();
        check(chain.leftEnd() == 4, "undoLeft restores the end value that existed before that placement, not just any value");
        check(chain.orderedTiles().size() == 1, "undoLeft removes exactly the one tile it added");

        chain.placeRight(DominoTile(4, 6));     // rightEnd becomes 6
        chain.undoRight();
        check(chain.rightEnd() == 4, "undoRight restores the prior end value symmetrically");
        check(chain.orderedTiles().size() == 1, "back down to just the opening tile");
    }

    section("Chain: a full multi-move sequence undone in exact reverse order returns to empty");
    {
        Chain chain;
        chain.placeOpening(DominoTile(5, 5));   // leftEnd=5, rightEnd=5
        chain.placeLeft(DominoTile(5, 2));      // leftEnd=2
        chain.placeRight(DominoTile(5, 0));     // rightEnd=0
        chain.placeLeft(DominoTile(2, 6));      // leftEnd=6
        check(chain.leftEnd() == 6 && chain.rightEnd() == 0 && chain.orderedTiles().size() == 4,
              "sanity check on the built-up state before unwinding it");

        chain.undoLeft();   // reverses the 2-6 placement
        check(chain.leftEnd() == 2, "first undo restores leftEnd to 2 (the value before the last left placement)");
        chain.undoRight();  // reverses the 5-0 placement
        check(chain.rightEnd() == 5, "second undo restores rightEnd to 5");
        chain.undoLeft();   // reverses the 5-2 placement
        check(chain.leftEnd() == 5, "third undo restores leftEnd to 5 (back to the opening double's value)");
        chain.undoOpening();
        check(chain.isEmpty(), "after undoing every placement in exact reverse order, the chain is empty again");
    }

    section("Chain: fromKnownState reconstructs a chain matching a real one, without replaying moves");
    {
        Chain real;
        real.placeOpening(DominoTile(4, 4));
        real.placeLeft(DominoTile(4, 6));
        real.placeRight(DominoTile(4, 1));
        // real: leftEnd=6, rightEnd=1, orderedTiles=[4-6,4-4,4-1]

        Chain reconstructed = Chain::fromKnownState(real.orderedTiles(), real.leftEnd(), real.rightEnd());
        check(reconstructed.orderedTiles() == real.orderedTiles(), "reconstructed chain has the exact same tile sequence");
        check(reconstructed.leftEnd() == real.leftEnd() && reconstructed.rightEnd() == real.rightEnd(),
              "reconstructed chain has the exact same exposed end values");
        check(!reconstructed.isEmpty(), "the reconstructed chain correctly reports itself as non-empty");
    }

    if (failureCount() == 0) {
        std::cout << "\nChain: all checks passed\n";
        return 0;
    }
    std::cout << "\nChain: " << failureCount() << " check(s) failed\n";
    return 1;
}
