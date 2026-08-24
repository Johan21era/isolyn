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
