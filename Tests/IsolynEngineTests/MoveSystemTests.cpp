#include "Move.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include "MoveExecutor.hpp"
#include "GameState.hpp"
#include "TestHarness.hpp"
#include <algorithm>

using namespace isolyn;
using namespace isolyn::test;

namespace {
bool containsMove(const std::vector<Move>& moves, Move target) {
    return std::find(moves.begin(), moves.end(), target) != moves.end();
}
bool sameHandContents(std::vector<DominoTile> a, std::vector<DominoTile> b) {
    auto byIndex = [](DominoTile x, DominoTile y) { return x.index() < y.index(); };
    std::sort(a.begin(), a.end(), byIndex);
    std::sort(b.begin(), b.end(), byIndex);
    return a == b;
}
} // namespace

int main() {
    section("Move: equality and description");
    {
        Move a{DominoTile(3, 5), GameState::ChainSide::Left};
        Move b{DominoTile(5, 3), GameState::ChainSide::Left}; // same tile, different constructor argument order
        Move c{DominoTile(3, 5), GameState::ChainSide::Right};
        check(a == b, "moves referring to the same tile and side are equal regardless of constructor argument order");
        check(!(a == c), "moves with the same tile but different sides are not equal");
        check(a.describe() == "3-5 (left)", "describe() reflects the tile and side");
    }

    section("MoveGenerator: empty chain offers every hand tile as a candidate opener");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6), DominoTile(2, 3), DominoTile(0, 1) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        auto moves = MoveGenerator::generate(state, 0);
        check(moves.size() == 3, "an empty chain offers exactly one candidate per hand tile");
        check(containsMove(moves, Move{DominoTile(6, 6), GameState::ChainSide::Left}), "every hand tile appears as a candidate");
        check(containsMove(moves, Move{DominoTile(0, 1), GameState::ChainSide::Left}), "including tiles with no special properties");
    }

    section("MoveGenerator: a tile matching both ends produces two distinct candidates, not one");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6), DominoTile(4, 2), DominoTile(1, 1), DominoTile(6, 3) },
            {},
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left); // opens: leftEnd = rightEnd = 6

        auto moves = MoveGenerator::generate(state, 0);
        check(moves.size() == 2, "only 6-3 has a matching face; it's offered once per matching end, both of which match here");
        check(containsMove(moves, Move{DominoTile(6, 3), GameState::ChainSide::Left}), "6-3 is a legal left placement");
        check(containsMove(moves, Move{DominoTile(6, 3), GameState::ChainSide::Right}), "6-3 is also a legal right placement -- both ends show 6");
        check(!containsMove(moves, Move{DominoTile(4, 2), GameState::ChainSide::Left}), "4-2 has no face matching 6, so it's excluded");
    }

    section("MoveGenerator: different tiles matching different ends produce the correct separate candidates");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 5), DominoTile(5, 2), DominoTile(6, 1), DominoTile(3, 3) },
            {},
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // opens: leftEnd = 5, rightEnd = 6

        auto moves = MoveGenerator::generate(state, 0);
        check(moves.size() == 2, "exactly the two tiles with a genuinely matching face produce candidates");
        check(containsMove(moves, Move{DominoTile(5, 2), GameState::ChainSide::Left}), "5-2 legally attaches to the 5-showing left end");
        check(containsMove(moves, Move{DominoTile(6, 1), GameState::ChainSide::Right}), "6-1 legally attaches to the 6-showing right end");
        check(!containsMove(moves, Move{DominoTile(3, 3), GameState::ChainSide::Left}), "3-3 matches neither end, so it's excluded entirely");
    }

    section("MoveGenerator: hasAnyLegalMove agrees with generate()'s emptiness");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 5) }, { DominoTile(1, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // leftEnd = 5, rightEnd = 6

        check(!MoveGenerator::hasAnyLegalMove(state, 1), "player 1's only tile (1-1) matches neither end -- no legal move");
        check(MoveGenerator::generate(state, 1).empty(), "generate() agrees: no candidates for player 1");
    }

    section("MoveValidator: a genuinely legal move is legal");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6), DominoTile(6, 2) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left);
        check(MoveValidator::isLegal(state, 0, Move{DominoTile(6, 2), GameState::ChainSide::Left}),
              "6-2 legally attaches to a 6-showing end");
    }

    section("MoveValidator: a tile not in the player's hand is illegal, even if it would otherwise fit");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left);
        check(!MoveValidator::isLegal(state, 0, Move{DominoTile(6, 2), GameState::ChainSide::Left}),
              "6-2 would fit, but player 0 doesn't hold it -- illegal");
    }

    section("MoveValidator: a hand tile that doesn't match the specified side is illegal");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 5), DominoTile(1, 2) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left); // leftEnd = 5, rightEnd = 6
        check(!MoveValidator::isLegal(state, 0, Move{DominoTile(1, 2), GameState::ChainSide::Left}),
              "1-2 has neither a 5 nor a 6 face -- illegal against either end");
    }

    section("MoveValidator: an empty chain accepts any hand tile, any side");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(0, 1) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        check(MoveValidator::isLegal(state, 0, Move{DominoTile(0, 1), GameState::ChainSide::Right}),
              "any tile the player holds is a legal opening placement, regardless of side");
    }

    section("MoveExecutor: apply updates state and returns the correct AppliedMove");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6), DominoTile(6, 2) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        auto applied1 = MoveExecutor::apply(state, 0, Move{DominoTile(6, 6), GameState::ChainSide::Left});
        check(applied1.kind == GameState::PlacementKind::Opened, "opening into an empty chain reports Opened");

        auto applied2 = MoveExecutor::apply(state, 0, Move{DominoTile(6, 2), GameState::ChainSide::Right});
        check(applied2.kind == GameState::PlacementKind::AttachedRight, "attaching to the right reports AttachedRight");
        check(state.hand(0).empty(), "both tiles are now off player 0's hand");
        check(state.chain().rightEnd() == 2, "the second tile correctly updated the right end");
    }

    section("MoveExecutor: undo exactly reverses apply, in LIFO order, across multiple moves");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(6, 6), DominoTile(6, 2), DominoTile(2, 5) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        std::vector<DominoTile> handBefore = state.hand(0);

        auto applied1 = MoveExecutor::apply(state, 0, Move{DominoTile(6, 6), GameState::ChainSide::Left});
        auto applied2 = MoveExecutor::apply(state, 0, Move{DominoTile(6, 2), GameState::ChainSide::Right});
        auto applied3 = MoveExecutor::apply(state, 0, Move{DominoTile(2, 5), GameState::ChainSide::Right});
        check(state.hand(0).empty() && state.chain().rightEnd() == 5, "sanity check: all three moves actually applied");

        MoveExecutor::undo(state, applied3);
        MoveExecutor::undo(state, applied2);
        MoveExecutor::undo(state, applied1);

        check(sameHandContents(state.hand(0), handBefore), "undoing all three moves in reverse order restores the exact original hand");
        check(state.chain().isEmpty(), "the chain is back to empty");
        check(state.playHistory().empty(), "play history is back to empty");
    }

    section("MoveExecutor: integration -- generate, validate, apply, undo, using MoveGenerator's real output");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(4, 4), DominoTile(4, 1), DominoTile(0, 2) }, {} };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(4, 4), GameState::ChainSide::Left); // leftEnd = rightEnd = 4

        auto candidates = MoveGenerator::generate(state, 0);
        check(!candidates.empty(), "at least one legal move should exist here");

        Move chosen = candidates.front();
        check(MoveValidator::isLegal(state, 0, chosen), "every move MoveGenerator produces is, itself, legal per MoveValidator");

        std::size_t handSizeBefore = state.hand(0).size();
        auto applied = MoveExecutor::apply(state, 0, chosen);
        check(state.hand(0).size() == handSizeBefore - 1, "applying the chosen move removes exactly one tile from the hand");

        MoveExecutor::undo(state, applied);
        check(state.hand(0).size() == handSizeBefore, "undoing restores the hand to its prior size");
    }

    section("MoveGenerator: isPositionClosed detects a genuinely closed position");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(5, 5), DominoTile(2, 2) }, // player 0: opens with 5-5, left holding 2-2
            { DominoTile(1, 1) },                    // player 1: never matches
        };
        GameState state(GameMode::OneVsOne, hands, {}); // no boneyard
        state.playTile(0, DominoTile(5, 5), GameState::ChainSide::Left); // leftEnd = rightEnd = 5
        check(MoveGenerator::isPositionClosed(state),
              "player 0's remaining 2-2 and player 1's 1-1 both match neither end, and the boneyard is empty");
    }

    section("MoveGenerator: isPositionClosed is false when any player still has a legal move");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(5, 5), DominoTile(5, 3) }, // player 0: 5-3 still matches after opening
            { DominoTile(1, 1) },
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(5, 5), GameState::ChainSide::Left);
        check(!MoveGenerator::isPositionClosed(state), "player 0 still holds 5-3, which matches the 5-showing ends");
    }

    section("MoveGenerator: isPositionClosed is false when the boneyard still has drawable tiles, even with no hand match");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(2, 2), DominoTile(0, 1) },
            { DominoTile(1, 4) },
        };
        std::vector<DominoTile> boneyard = { DominoTile(0, 3), DominoTile(4, 1), DominoTile(6, 6) }; // drawableCount = 1
        GameState state(GameMode::OneVsOne, hands, boneyard);
        state.playTile(0, DominoTile(2, 2), GameState::ChainSide::Left); // leftEnd = rightEnd = 2
        check(!MoveGenerator::isPositionClosed(state),
              "no hand currently matches, but the boneyard still has a drawable tile -- not closed yet");
    }

    if (failureCount() == 0) {
        std::cout << "\nMoveSystem: all checks passed\n";
        return 0;
    }
    std::cout << "\nMoveSystem: " << failureCount() << " check(s) failed\n";
    return 1;
}
