#include "Dealer.hpp"
#include "TestHarness.hpp"
#include <algorithm>
#include <vector>

using isolyn::Dealer;
using isolyn::DominoTile;
using isolyn::EntropySource;
using isolyn::GameMode;
using namespace isolyn::test;

namespace {
bool handContains(const std::vector<DominoTile>& hand, DominoTile tile) {
    return std::find(hand.begin(), hand.end(), tile) != hand.end();
}
} // namespace

int main() {
    EntropySource entropy;

    section("Dealer: 1v1 hand and boneyard sizes");
    {
        auto result = Dealer::deal(GameMode::OneVsOne, entropy);
        check(result.hands.size() == 2, "1v1 deals to exactly 2 players");
        check(result.hands[0].size() == 7 && result.hands[1].size() == 7, "each 1v1 hand has 7 tiles");
        check(result.boneyard.size() == 14, "1v1 leaves 14 tiles in the boneyard");
    }

    section("Dealer: 1v1v1 hand size, 0-0 removal, empty boneyard");
    {
        auto result = Dealer::deal(GameMode::OneVsOneVsOne, entropy);
        check(result.hands.size() == 3, "1v1v1 deals to exactly 3 players");
        for (const auto& hand : result.hands) {
            check(hand.size() == 9, "each 1v1v1 hand has 9 tiles");
            check(!handContains(hand, DominoTile(0, 0)), "0-0 never appears in a 1v1v1 hand");
        }
        check(result.boneyard.empty(), "1v1v1 leaves no boneyard (27 dealt + 0-0 removed = all 28)");
        check(!handContains(result.boneyard, DominoTile(0, 0)),
              "0-0 is not sitting in the boneyard either -- it's fully removed from the game");
    }

    section("Dealer: 2v2 hand and boneyard sizes");
    {
        auto result = Dealer::deal(GameMode::TwoVsTwo, entropy);
        check(result.hands.size() == 4, "2v2 deals to exactly 4 players");
        for (const auto& hand : result.hands) {
            check(hand.size() == 7, "each 2v2 hand has 7 tiles");
        }
        check(result.boneyard.empty(), "2v2 leaves no boneyard (7x4 = all 28)");
    }

    section("Dealer: Misdeal -- wrong hand size");
    {
        // Tile identities are placeholders here; only .size() matters for
        // this check.
        std::vector<std::vector<DominoTile>> badHands = {
            std::vector<DominoTile>(8, DominoTile(0, 0)),
            std::vector<DominoTile>(7, DominoTile(1, 1)),
        };
        check(Dealer::isMisdeal(GameMode::OneVsOne, badHands), "an 8-tile hand in a 7-tile mode is a Misdeal");
    }

    section("Dealer: Misdeal -- five or more doubles, 1v1 only");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(0, 0), DominoTile(1, 1), DominoTile(2, 2), DominoTile(3, 3),
              DominoTile(4, 4), DominoTile(5, 0), DominoTile(6, 1) },
            { DominoTile(6, 6), DominoTile(2, 3), DominoTile(4, 1), DominoTile(5, 2),
              DominoTile(0, 3), DominoTile(1, 4), DominoTile(2, 5) },
        };
        check(Dealer::isMisdeal(GameMode::OneVsOne, hands), "5 doubles in one 1v1 hand is a Misdeal");
    }

    section("Dealer: repeated deals never return a Misdeal result (200 trials)");
    {
        bool anyMisdeal = false;
        for (int trial = 0; trial < 200; ++trial) {
            auto result = Dealer::deal(GameMode::OneVsOne, entropy);
            if (Dealer::isMisdeal(GameMode::OneVsOne, result.hands)) anyMisdeal = true;
        }
        check(!anyMisdeal, "deal() always reshuffles past a Misdeal -- never hands back an invalid deal");
    }

    section("Dealer::excludedTilesForMode is the single source of truth deal() itself uses");
    {
        auto oneVsOne = Dealer::excludedTilesForMode(GameMode::OneVsOne);
        check(oneVsOne.empty(), "OneVsOne excludes nothing");

        auto twoVsTwo = Dealer::excludedTilesForMode(GameMode::TwoVsTwo);
        check(twoVsTwo.empty(), "TwoVsTwo excludes nothing");

        auto oneVsOneVsOne = Dealer::excludedTilesForMode(GameMode::OneVsOneVsOne);
        check(oneVsOneVsOne.size() == 1, "OneVsOneVsOne excludes exactly one tile");
        check(!oneVsOneVsOne.empty() && oneVsOneVsOne[0] == DominoTile(0, 0), "and it is 0-0 specifically");

        // Cross-check against deal()'s own actual output rather than just
        // asserting the two happen to agree by construction -- this is
        // what ProbabilityEngine::constructFromGameState now trusts.
        EntropySource entropy;
        auto result = Dealer::deal(GameMode::OneVsOneVsOne, entropy);
        std::size_t totalDealt = result.boneyard.size();
        for (const auto& hand : result.hands) totalDealt += hand.size();
        check(totalDealt == static_cast<std::size_t>(DominoTile::kTileCount) - oneVsOneVsOne.size(),
              "hands + boneyard for a 1v1v1 deal always total 28 minus exactly the excluded tiles");
    }

    if (failureCount() == 0) {
        std::cout << "\nDealer: all checks passed\n";
        return 0;
    }
    std::cout << "\nDealer: " << failureCount() << " check(s) failed\n";
    return 1;
}
