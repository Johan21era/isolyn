#include "GameState.hpp"
#include "Dealer.hpp"
#include "EntropySource.hpp"
#include "RulesEngine.hpp"
#include "TestHarness.hpp"
#include <algorithm>

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("GameState: construction reflects the hands and boneyard it was given");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(1, 1), DominoTile(2, 3) },
            { DominoTile(4, 4), DominoTile(5, 6) },
        };
        std::vector<DominoTile> boneyard = { DominoTile(0, 0) };
        GameState state(GameMode::OneVsOne, hands, boneyard);

        check(state.mode() == GameMode::OneVsOne, "mode is stored as given");
        check(state.playerCount() == 2, "player count matches the number of hands given");
        check(state.hand(0).size() == 2 && state.hand(1).size() == 2, "each hand matches what was given");
        check(state.boneyard().size() == 1, "boneyard matches what was given");
        check(state.chain().isEmpty(), "the chain starts empty before any play");
        check(state.playHistory().empty(), "play history starts empty");
    }

    section("GameState: One Domino Rule: both hands on one tile force a draw at turn start (1v1 only)");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(3, 3) },
            { DominoTile(5, 5) },
        };
        // Four tiles => two drawable; the last two are locked, as always.
        std::vector<DominoTile> boneyard = {
            DominoTile(0, 0), DominoTile(6, 6), DominoTile(4, 4), DominoTile(1, 1),
        };
        GameState state(GameMode::OneVsOne, hands, boneyard);

        auto drawn = state.enforceOneDominoRule();
        check(drawn.has_value() && *drawn == DominoTile(0, 0),
              "both hands hold exactly one tile, so the current player must take the front boneyard tile");
        check(state.hand(0).size() == 2, "the mandatory draw went to the current player");
        check(state.boneyard().drawableCount() == 1, "exactly one tile was drawn -- the rule is one tile, not a loop");

        auto again = state.enforceOneDominoRule();
        check(!again.has_value(), "once a hand holds two tiles the condition is false and the other player is released");

        GameState otherTurn(GameMode::OneVsOne, hands, boneyard);
        otherTurn.setCurrentPlayerIndex(1);
        auto drewForOne = otherTurn.enforceOneDominoRule();
        check(drewForOne.has_value() && otherTurn.hand(1).size() == 2 && otherTurn.hand(0).size() == 1,
              "the draw belongs to whoever's turn it is, not to player 0 by default");

        std::vector<std::vector<DominoTile>> uneven = {
            { DominoTile(3, 3), DominoTile(2, 2) },
            { DominoTile(5, 5) },
        };
        GameState notBothOne(GameMode::OneVsOne, uneven, boneyard);
        check(!notBothOne.enforceOneDominoRule().has_value(),
              "one hand already holds two tiles, so the rule is not triggered");

        std::vector<std::vector<DominoTile>> threeHands = {
            { DominoTile(3, 3) }, { DominoTile(5, 5) }, { DominoTile(1, 2) },
        };
        GameState threeWay(GameMode::OneVsOneVsOne, threeHands, boneyard);
        check(!threeWay.enforceOneDominoRule().has_value(),
              "the One Domino Rule is 1v1-only; 1v1v1 keeps its ordinary turn flow");

        GameState dryYard(GameMode::OneVsOne, hands, {});
        check(!dryYard.enforceOneDominoRule().has_value(),
              "with no drawable tile there is nothing to take, so the rule cannot fire");
    }

    section("GameState: R-17 private look returns the locked pair only to a one-tile hand with no drawable tiles");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(3, 3) },
            { DominoTile(5, 5) },
        };
        // Exactly two remain: both are permanently locked, none drawable.
        std::vector<DominoTile> pairOnly = { DominoTile(0, 0), DominoTile(6, 6) };
        GameState state(GameMode::OneVsOne, hands, pairOnly);
        const std::uint64_t before = state.hash();

        auto pair = state.privateLockedPair(0);
        check(pair.has_value(), "a one-tile hand with no drawable tiles may look at the pair");
        if (pair.has_value()) {
            check((*pair)[0] == DominoTile(0, 0) && (*pair)[1] == DominoTile(6, 6),
                  "the look returns both locked tiles in boneyard order");
        }
        auto again = state.privateLockedPair(0);
        check(again.has_value() && again == pair, "the look is repeatable -- it is not once per hand");
        check(state.hash() == before, "looking changes nothing: the state hash is identical");

        std::vector<std::vector<DominoTile>> uneven = {
            { DominoTile(3, 3), DominoTile(2, 2) },
            { DominoTile(5, 5) },
        };
        GameState twoTiles(GameMode::OneVsOne, uneven, pairOnly);
        check(!twoTiles.privateLockedPair(0).has_value(),
              "a player still holding two tiles may not look, even at the locked pair");
        check(twoTiles.privateLockedPair(1).has_value(),
              "the look is scoped to the requester's hand, not the current player's");

        std::vector<DominoTile> drawableRemains = {
            DominoTile(0, 0), DominoTile(6, 6), DominoTile(4, 4), DominoTile(1, 1),
        };
        GameState early(GameMode::OneVsOne, hands, drawableRemains);
        check(!early.privateLockedPair(0).has_value(),
              "while any other boneyard tile is still drawable, the pair stays private");

        std::vector<std::vector<DominoTile>> threeHands = {
            { DominoTile(3, 3) }, { DominoTile(5, 5) }, { DominoTile(1, 2) },
        };
        GameState threeWay(GameMode::OneVsOneVsOne, threeHands, pairOnly);
        check(!threeWay.privateLockedPair(0).has_value(),
              "1v1v1 has no locked pair to look at, even with a constructed boneyard");

        GameState noPair(GameMode::OneVsOne, hands, {});
        check(!noPair.privateLockedPair(0).has_value(),
              "an empty boneyard has no pair; the look is not a peek at nothing");
    }

    section("GameState: hash is order-independent for hands but sensitive to turn and draw order");
    {
        std::vector<DominoTile> boneyard = {
            DominoTile(0, 0), DominoTile(1, 2), DominoTile(3, 4), DominoTile(5, 6),
        };
        std::vector<std::vector<DominoTile>> handsA = {
            { DominoTile(1, 1), DominoTile(2, 3) },
            { DominoTile(4, 4), DominoTile(5, 6) },
        };
        std::vector<std::vector<DominoTile>> handsB = {
            { DominoTile(2, 3), DominoTile(1, 1) },
            { DominoTile(5, 6), DominoTile(4, 4) },
        };
        GameState a(GameMode::OneVsOne, handsA, boneyard);
        GameState b(GameMode::OneVsOne, handsB, boneyard);
        check(a.hash() == b.hash(), "hand ordering does not change the state hash");

        GameState otherTurn(GameMode::OneVsOne, handsA, boneyard, Chain(), {}, 1);
        check(a.hash() != otherTurn.hash(), "whose turn it is changes the state hash");

        std::vector<DominoTile> reversedBoneyard(boneyard.rbegin(), boneyard.rend());
        GameState otherDrawOrder(GameMode::OneVsOne, handsA, reversedBoneyard);
        check(a.hash() != otherDrawOrder.hash(), "boneyard draw order changes the state hash");
    }

    section("GameState: playTile removes from hand, attaches to chain, records history -- atomically");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6), DominoTile(2, 3) },
            { DominoTile(6, 4) },
        };
        GameState state(GameMode::OneVsOne, hands, {});

        state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left);
        check(state.hand(0).size() == 1, "the played tile is removed from the hand");
        check(!state.chain().isEmpty() && state.chain().leftEnd() == 6, "the tile opened the chain");
        check(state.playHistory().size() == 1, "the play is recorded");
        check(state.playHistory()[0].playerIndex == 0 && state.playHistory()[0].tile == DominoTile(6, 6),
              "the recorded play matches who played what");

        state.playTile(1, DominoTile(6, 4), GameState::ChainSide::Right);
        check(state.hand(1).empty(), "player 1's hand is now empty after playing their only tile");
        check(state.chain().rightEnd() == 4, "6-4 against a 6-showing right end exposes 4");
        check(state.playHistory().size() == 2, "both plays are recorded in order");
    }

    section("GameState: drawTile removes from the boneyard, adds to the drawing player's hand");
    {
        // A boneyard of exactly 2 would leave nothing drawable (both
        // would be the locked pair -- see BoneyardTests), so this uses 3
        // to have something legitimately drawable to test against.
        std::vector<std::vector<DominoTile>> hands = { {}, {} };
        std::vector<DominoTile> boneyard = { DominoTile(3, 3), DominoTile(5, 2), DominoTile(1, 0) };
        GameState state(GameMode::OneVsOne, hands, boneyard);

        DominoTile drawn = state.drawTile(0);
        check(drawn == DominoTile(3, 3), "drawTile returns the boneyard's front tile");
        check(state.hand(0).size() == 1 && state.hand(0)[0] == DominoTile(3, 3),
              "the drawn tile is added to the drawing player's hand");
        check(state.boneyard().size() == 2, "the boneyard shrinks by one");
    }

    section("GameState: cloning is a plain, independent value copy");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(1, 1) }, { DominoTile(1, 5) } };
        GameState original(GameMode::OneVsOne, hands, {});
        original.playTile(0, DominoTile(1, 1), GameState::ChainSide::Left);

        GameState clone = original; // ordinary copy constructor, nothing custom
        clone.playTile(1, DominoTile(1, 5), GameState::ChainSide::Right); // 1-5 has a face matching the 1-1 opener

        check(original.hand(1).size() == 1, "mutating the clone leaves the original's hand untouched");
        check(original.playHistory().size() == 1, "mutating the clone leaves the original's history untouched");
        check(clone.playHistory().size() == 2, "the clone's own history reflects its own mutation");
    }

    section("GameState: playTile reports which PlacementKind actually happened");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(3, 3), DominoTile(3, 6) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        auto kind1 = state.playTile(0, DominoTile(3, 3), GameState::ChainSide::Left);
        check(kind1 == GameState::PlacementKind::Opened, "playing into an empty chain reports Opened, regardless of the side argument");
        auto kind2 = state.playTile(0, DominoTile(3, 6), GameState::ChainSide::Left);
        check(kind2 == GameState::PlacementKind::AttachedLeft, "attaching to a non-empty chain reports the actual side used");
    }

    section("GameState: undoPlayTile exactly reverses playTile -- hand, chain, and history all restored");
    {
        auto sameHandContents = [](std::vector<DominoTile> a, std::vector<DominoTile> b) {
            auto byIndex = [](DominoTile x, DominoTile y) { return x.index() < y.index(); };
            std::sort(a.begin(), a.end(), byIndex);
            std::sort(b.begin(), b.end(), byIndex);
            return a == b;
        };

        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6), DominoTile(2, 3) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        std::vector<DominoTile> handBefore = state.hand(0);

        auto kind = state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left);
        check(state.hand(0).size() == 1 && !state.chain().isEmpty(), "sanity check: the play actually happened");

        state.undoPlayTile(0, DominoTile(6, 6), kind);
        check(sameHandContents(state.hand(0), handBefore), "undoPlayTile restores the exact same tiles to the hand");
        check(state.chain().isEmpty(), "undoPlayTile restores the chain to empty");
        check(state.playHistory().empty(), "undoPlayTile removes the recorded play");
    }

    section("GameState: undoDrawTile exactly reverses drawTile");
    {
        std::vector<std::vector<DominoTile>> hands = { {}, {} };
        std::vector<DominoTile> boneyard = { DominoTile(3, 3), DominoTile(5, 2), DominoTile(1, 0) };
        GameState state(GameMode::OneVsOne, hands, boneyard);

        DominoTile drawn = state.drawTile(0);
        state.undoDrawTile(0, drawn);
        check(state.hand(0).empty(), "undoDrawTile removes the tile from the hand it was added to");
        check(state.boneyard().size() == 3, "undoDrawTile restores the boneyard's physical count");
        check(state.boneyard().drawableCount() == 1, "undoDrawTile restores drawableCount, not just size");
    }

    section("GameState: a full apply-then-undo sequence, played and drawn, returns to the exact starting hands");
    {
        auto sameHandContents = [](std::vector<DominoTile> a, std::vector<DominoTile> b) {
            auto byIndex = [](DominoTile x, DominoTile y) { return x.index() < y.index(); };
            std::sort(a.begin(), a.end(), byIndex);
            std::sort(b.begin(), b.end(), byIndex);
            return a == b;
        };

        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(4, 4), DominoTile(4, 1) },
            { DominoTile(4, 2) },
        };
        std::vector<DominoTile> boneyard = { DominoTile(0, 0), DominoTile(6, 6), DominoTile(5, 5) };
        GameState state(GameMode::OneVsOne, hands, boneyard);
        std::vector<DominoTile> hand0Before = state.hand(0);
        std::vector<DominoTile> hand1Before = state.hand(1);

        // Play, play, draw -- then undo in exact LIFO order.
        auto k1 = state.playTile(0, DominoTile(4, 4), GameState::ChainSide::Left);   // opens, leftEnd=rightEnd=4
        auto k2 = state.playTile(1, DominoTile(4, 2), GameState::ChainSide::Right);  // attaches right, rightEnd=2
        DominoTile drawnTile = state.drawTile(0);

        state.undoDrawTile(0, drawnTile);
        state.undoPlayTile(1, DominoTile(4, 2), k2);
        state.undoPlayTile(0, DominoTile(4, 4), k1);

        check(sameHandContents(state.hand(0), hand0Before), "player 0's hand matches its exact starting contents");
        check(sameHandContents(state.hand(1), hand1Before), "player 1's hand matches its exact starting contents");
        check(state.chain().isEmpty(), "the chain is back to empty");
        check(state.playHistory().empty(), "play history is back to empty");
        check(state.boneyard().size() == 3, "the boneyard is back to its original size");
    }

    section("GameState: integration -- Dealer, RulesEngine, and GameState agree with each other");
    {
        EntropySource entropy;
        auto dealt = Dealer::deal(GameMode::OneVsOne, entropy);
        auto opening = RulesEngine::determineOpeningPlay(dealt.hands);

        GameState state(GameMode::OneVsOne, dealt.hands, dealt.boneyard);
        check(state.hand(opening.openingPlayerIndex).size() ==
                  static_cast<std::size_t>(Dealer::handSizeForMode(GameMode::OneVsOne)),
              "the opening player's hand, as constructed in GameState, matches what Dealer dealt them");

        const auto& openerHand = state.hand(opening.openingPlayerIndex);
        bool tilePresent = std::find(openerHand.begin(), openerHand.end(), opening.openingTile) != openerHand.end();
        check(tilePresent, "the tile RulesEngine chose as the opener is genuinely in that player's GameState hand");

        state.playTile(opening.openingPlayerIndex, opening.openingTile, GameState::ChainSide::Left);
        check(!state.chain().isEmpty(), "playing the opening tile through GameState actually opens the chain");
        check(state.playHistory().size() == 1, "the opening play is recorded in GameState's history");
    }

    section("GameState: the extended constructor correctly accepts a pre-built chain and play history");
    {
        Chain preBuilt;
        preBuilt.placeOpening(DominoTile(3, 3));
        preBuilt.placeRight(DominoTile(3, 5));

        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6) }, { DominoTile(1, 1) } };
        std::vector<PlayRecord> history = { PlayRecord{1, DominoTile(3, 3)}, PlayRecord{0, DominoTile(3, 5)} };
        GameState state(GameMode::OneVsOne, hands, {}, preBuilt, history, 1);

        check(!state.chain().isEmpty(), "the injected chain is used directly, not started empty");
        check(state.chain().leftEnd() == 3 && state.chain().rightEnd() == 5, "the injected chain's exposed ends are exactly as given");
        check(state.chain().orderedTiles() == preBuilt.orderedTiles(), "the injected chain's tile sequence is exactly as given");
        check(state.playHistory().size() == 2, "the injected play history is used directly, not started empty");
        check(state.playHistory()[0].playerIndex == 1 && state.playHistory()[1].playerIndex == 0,
              "the injected play history's contents are exactly as given, in order");
        check(state.currentPlayerIndex() == 1, "the injected current player index is used directly");
    }

    section("GameState: the extended constructor's defaults preserve prior behavior exactly");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6) }, { DominoTile(1, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});
        check(state.chain().isEmpty(), "omitting the new parameters still starts with an empty chain");
        check(state.playHistory().empty(), "omitting the new parameters still starts with empty play history");
        check(state.currentPlayerIndex() == 0, "omitting the new parameter still defaults current player to 0");
    }

    if (failureCount() == 0) {
        std::cout << "\nGameState: all checks passed\n";
        return 0;
    }
    std::cout << "\nGameState: " << failureCount() << " check(s) failed\n";
    return 1;
}
