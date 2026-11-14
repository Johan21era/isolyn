#include "MatchController.hpp"
#include "EntropySource.hpp"
#include "MoveGenerator.hpp"
#include "RulesEngine.hpp"
#include "TestHarness.hpp"

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("MatchController: dealFirstRound applies the mandated opening play (1v1)");
    {
        EntropySource entropy;
        MatchController controller = MatchController::dealFirstRound(GameMode::OneVsOne, entropy);
        check(!controller.state().chain().isEmpty(), "construction already applied the mandated opening play");
        check(controller.state().playHistory().size() == 1, "exactly one play (the opening) has been recorded");
        int opener = controller.state().playHistory()[0].playerIndex;
        check(controller.currentPlayerIndex() == 1 - opener, "turn advanced to the other player (1v1 has only two)");
        check(controller.state().hand(0).size() + controller.state().hand(1).size() == 13,
              "one tile played from the dealt 14 (7+7) leaves 13 remaining across both hands");
    }

    section("MatchController: dealFirstRound also works for 1v1v1 and 2v2, both with empty boneyards");
    {
        EntropySource entropy;
        MatchController oneVsOneVsOne = MatchController::dealFirstRound(GameMode::OneVsOneVsOne, entropy);
        check(!oneVsOneVsOne.state().chain().isEmpty(), "1v1v1 construction applies the opening play too");
        check(oneVsOneVsOne.state().boneyard().isEmpty(), "1v1v1 has no boneyard, as established earlier");

        MatchController twoVsTwo = MatchController::dealFirstRound(GameMode::TwoVsTwo, entropy);
        check(!twoVsTwo.state().chain().isEmpty(), "2v2 construction applies the opening play too");
        check(twoVsTwo.state().boneyard().isEmpty(), "2v2 has no boneyard either");
    }

    section("MatchController: dealSubsequentRound leaves the chain empty -- no mandated opening tile past round one");
    {
        EntropySource entropy;
        MatchController controller = MatchController::dealSubsequentRound(GameMode::OneVsOne, entropy, /*startingPlayerIndex=*/1);
        check(controller.state().chain().isEmpty(), "no opening tile is auto-applied -- the round starter chooses freely, like any other turn");
        check(controller.state().playHistory().empty(), "no play has happened yet, so history is empty");
        check(controller.currentPlayerIndex() == 1, "whoever the caller designated as starter (from the previous round's outcome) goes first");
        check(controller.state().hand(0).size() == 7 && controller.state().hand(1).size() == 7,
              "both hands are freshly dealt at full size -- nothing has been played from either yet");

        // The starter is free to open with ANY of their 7 tiles -- MoveGenerator
        // should offer all of them as candidates, exactly like a normal turn
        // against an empty chain, not a single rules-mandated one.
        auto candidates = MoveGenerator::generate(controller.state(), 1);
        check(candidates.size() == 7, "the starting player has all 7 of their tiles available as legal opening candidates");
    }

    section("MatchController: dealSubsequentRound also produces a genuinely empty boneyard for 1v1v1/2v2");
    {
        EntropySource entropy;
        MatchController oneVsOneVsOne = MatchController::dealSubsequentRound(GameMode::OneVsOneVsOne, entropy, 2);
        check(oneVsOneVsOne.currentPlayerIndex() == 2, "starter respected");
        check(oneVsOneVsOne.state().boneyard().isEmpty(), "1v1v1 still has no boneyard in a subsequent round");
        check(oneVsOneVsOne.state().hand(2).size() == 9, "1v1v1 hands are still 9 tiles each");
    }

    section("MatchController: raw-GameState constructor is for sandbox/loaded positions -- no deal, no auto-opening");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(3, 3) }, { DominoTile(1, 1) } };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(3, 3), GameState::ChainSide::Left); // manually opened, simulating a loaded position
        state.setCurrentPlayerIndex(1);

        MatchController controller(state);
        check(controller.currentPlayerIndex() == 1, "the raw constructor respects the given currentPlayerIndex exactly");
        check(controller.state().playHistory().size() == 1, "no extra opening play is injected -- the state is used as given");
    }

    section("MatchController: voluntaryDraw draws exactly one tile into the current player's hand");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(3, 3) }, { DominoTile(1, 5) } };
        std::vector<DominoTile> boneyard = { DominoTile(0, 0), DominoTile(6, 6), DominoTile(5, 5) };
        GameState state(GameMode::OneVsOne, hands, boneyard);
        state.playTile(0, DominoTile(3, 3), GameState::ChainSide::Left);
        state.setCurrentPlayerIndex(1);

        MatchController controller(state);
        std::size_t before = controller.state().hand(1).size();
        DominoTile drawn = controller.voluntaryDraw();
        check(drawn == DominoTile(0, 0), "voluntaryDraw returns the boneyard's front tile, same as an ordinary draw");
        check(controller.state().hand(1).size() == before + 1, "the drawn tile is added to the current player's hand");
    }

    section("MatchController: resolveForcedDraw draws until a playable tile is found");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(1, 1) },   // never matches 3 or 6
            { DominoTile(6, 3) },   // opens
        };
        // Drawable order: 2-2 (no match), 0-5 (no match), 6-4 (matches -- stop here). Locked: 3-1, 0-1.
        std::vector<DominoTile> boneyard = { DominoTile(2, 2), DominoTile(0, 5), DominoTile(6, 4), DominoTile(3, 1), DominoTile(0, 1) };
        GameState state(GameMode::OneVsOne, hands, boneyard);
        state.playTile(1, DominoTile(6, 3), GameState::ChainSide::Left); // leftEnd = 3, rightEnd = 6
        state.setCurrentPlayerIndex(0);

        MatchController controller(state);
        check(!controller.currentPlayerHasLegalMove(), "player 0's only tile (1-1) matches neither end");

        auto drawn = controller.resolveForcedDraw();
        check(drawn.size() == 3, "drew three tiles before finding one that's playable");
        check(drawn[0] == DominoTile(2, 2) && drawn[1] == DominoTile(0, 5) && drawn[2] == DominoTile(6, 4),
              "drew in exact boneyard order, stopping the instant a playable tile (6-4) was drawn");
        check(controller.currentPlayerHasLegalMove(), "after resolveForcedDraw, the player now has a legal move");
    }

    section("MatchController: resolveForcedDraw stops once the boneyard is exhausted, even without a playable tile");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(1, 1) }, { DominoTile(6, 3) } };
        // None of the drawable tiles match 3 or 6 either.
        std::vector<DominoTile> boneyard = { DominoTile(2, 2), DominoTile(0, 5), DominoTile(4, 4), DominoTile(2, 0), DominoTile(5, 5) };
        GameState state(GameMode::OneVsOne, hands, boneyard);
        state.playTile(1, DominoTile(6, 3), GameState::ChainSide::Left);
        state.setCurrentPlayerIndex(0);

        MatchController controller(state);
        auto drawn = controller.resolveForcedDraw();
        check(drawn.size() == 3, "drew all three drawable tiles -- none matched, drawing stops once the boneyard is exhausted");
        check(!controller.currentPlayerHasLegalMove(), "still no legal move after exhausting the boneyard");
        check(controller.state().boneyard().drawableCount() == 0, "the boneyard is now fully exhausted");
    }

    section("MatchController: endTurnWithNoPlay advances the turn and correctly reports InProgress when someone else can still move");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(1, 1) },
            { DominoTile(6, 3), DominoTile(6, 5) }, // still holds a legal move (6-5) after opening with 6-3
        };
        std::vector<DominoTile> boneyard = { DominoTile(2, 2), DominoTile(0, 5), DominoTile(4, 4) }; // only 2-2 drawable
        GameState state(GameMode::OneVsOne, hands, boneyard);
        state.playTile(1, DominoTile(6, 3), GameState::ChainSide::Left); // leftEnd = 3, rightEnd = 6
        state.setCurrentPlayerIndex(0);

        MatchController controller(state);
        controller.resolveForcedDraw();
        check(!controller.currentPlayerHasLegalMove(), "player 0 still has no legal move after exhausting the boneyard");

        RoundOutcome outcome = controller.endTurnWithNoPlay();
        check(outcome.kind == RoundOutcomeKind::InProgress, "player 1 can still play their remaining 6-5 -- correctly not a Close");
        check(controller.currentPlayerIndex() == 1, "the turn correctly advanced to player 1");
    }

    section("MatchController: playTurn detects Domino victory when a player empties their hand");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6) },               // player 0's only tile -- will Domino
            { DominoTile(6, 3), DominoTile(1, 2) },
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(1, DominoTile(6, 3), GameState::ChainSide::Left); // leftEnd = 3, rightEnd = 6

        MatchController controller(state);
        check(controller.currentPlayerIndex() == 0, "sanity: it's player 0's turn");

        RoundOutcome outcome = controller.playTurn(Move{DominoTile(6, 6), GameState::ChainSide::Right});
        check(outcome.kind == RoundOutcomeKind::DominoVictory, "playing the player's last tile is detected as a Domino victory");
        check(outcome.decidingPlayerIndex == 0, "the winner is correctly identified as player 0");
    }

    section("MatchController: playTurn detects a Close when no player anywhere has a legal move and the boneyard is empty");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 4), DominoTile(2, 2) },
            { DominoTile(4, 4), DominoTile(1, 1) },
        };
        GameState state(GameMode::OneVsOne, hands, {}); // no boneyard, to isolate Close detection
        state.playTile(1, DominoTile(4, 4), GameState::ChainSide::Left); // leftEnd = rightEnd = 4

        MatchController controller(state);
        RoundOutcome outcome = controller.playTurn(Move{DominoTile(6, 4), GameState::ChainSide::Left});
        // leftEnd becomes 6; rightEnd stays 4. Remaining tiles: player 0 has 2-2 (matches neither),
        // player 1 has 1-1 (matches neither). Boneyard is empty.
        check(outcome.kind == RoundOutcomeKind::Closed, "no player has a legal move and the boneyard is empty");
        check(outcome.decidingPlayerIndex == 0, "player 0, who made the closing play (a non-double), is credited as the closer");
    }

    section("MatchController: playTurn reports InProgress for an ordinary play that doesn't end the round");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6), DominoTile(4, 1) },
            { DominoTile(6, 2), DominoTile(2, 3) },
        };
        GameState state(GameMode::OneVsOne, hands, {});
        state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left); // leftEnd = rightEnd = 6
        state.setCurrentPlayerIndex(1);

        MatchController controller(state);
        RoundOutcome outcome = controller.playTurn(Move{DominoTile(6, 2), GameState::ChainSide::Left});
        // newLeftEnd = 2; player 1's remaining tile (2-3) still matches it.
        check(outcome.kind == RoundOutcomeKind::InProgress, "a legal move remains available -- correctly still in progress");
    }

    section("MatchController: One Domino Rule draws for the incoming player when both 1v1 hands reach one");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6), DominoTile(6, 5) },
            { DominoTile(5, 5) },
        };
        std::vector<DominoTile> boneyard = {
            DominoTile(4, 4), DominoTile(3, 3), DominoTile(2, 2), DominoTile(1, 1),
        };
        GameState state(GameMode::OneVsOne, hands, boneyard);
        MatchController controller(state);

        RoundOutcome outcome = controller.playTurn(Move{DominoTile(6, 6), GameState::ChainSide::Left});
        check(outcome.kind == RoundOutcomeKind::InProgress, "the play itself does not end the round");
        check(controller.currentPlayerIndex() == 1, "turn advanced to player 1");
        check(controller.state().hand(0).size() == 1, "player 0 is down to one tile but has already taken their turn");
        check(controller.state().hand(1).size() == 2,
              "player 1's turn began with both hands on one, so the mandatory 4-4 draw was applied");
        check(controller.state().boneyard().drawableCount() == 1, "exactly one tile was drawn");
    }

    section("MatchController: One Domino Rule does not fire when only one hand is on one tile");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6), DominoTile(6, 5) },
            { DominoTile(5, 5), DominoTile(5, 4) },
        };
        std::vector<DominoTile> boneyard = {
            DominoTile(4, 4), DominoTile(3, 3), DominoTile(2, 2), DominoTile(1, 1),
        };
        GameState state(GameMode::OneVsOne, hands, boneyard);
        MatchController controller(state);

        controller.playTurn(Move{DominoTile(6, 6), GameState::ChainSide::Left});
        check(controller.state().hand(0).size() == 1, "player 0 played down to one tile");
        check(controller.state().hand(1).size() == 2,
              "player 1 already held two tiles, so no mandatory draw is added");
        check(controller.state().boneyard().drawableCount() == 2, "the boneyard is untouched");
    }

    section("MatchController: One Domino Rule cannot draw from an empty boneyard");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 6), DominoTile(6, 5) },
            { DominoTile(5, 5) },
        };
        GameState state(GameMode::OneVsOne, hands, {});
        MatchController controller(state);

        controller.playTurn(Move{DominoTile(6, 6), GameState::ChainSide::Left});
        check(controller.state().hand(0).size() == 1 && controller.state().hand(1).size() == 1,
              "with no drawable tile both hands stay on one -- the rule has nothing to take");
        check(controller.state().boneyard().drawableCount() == 0, "the boneyard is genuinely empty");
    }

    section("MatchController: 2v2 team-index mapping now lives on RulesEngine (see RulesEngine.hpp comment)");
    {
        check(RulesEngine::teamIndexForPlayer(0) == 0 && RulesEngine::teamIndexForPlayer(2) == 0,
              "players 0 and 2 are on team 0, matching opposite-seat partnership");
        check(RulesEngine::teamIndexForPlayer(1) == 1 && RulesEngine::teamIndexForPlayer(3) == 1,
              "players 1 and 3 are on team 1");
        auto team0 = RulesEngine::playersOnTeam(0);
        check(team0.first == 0 && team0.second == 2, "playersOnTeam(0) returns the (0, 2) pairing");
        auto team1 = RulesEngine::playersOnTeam(1);
        check(team1.first == 1 && team1.second == 3, "playersOnTeam(1) returns the (1, 3) pairing");
    }

    section("MatchController: the opener may not draw into an empty chain");
    {
        std::vector<std::vector<DominoTile>> hands = { { DominoTile(3, 3) }, { DominoTile(1, 5) } };
        // Four tiles, because the boneyard's final two are locked and never
        // drawable -- with two, drawableCount is 0 for an unrelated reason.
        std::vector<DominoTile> boneyard = { DominoTile(0, 0), DominoTile(6, 6),
                                             DominoTile(5, 5), DominoTile(4, 4) };

        GameState empty(GameMode::OneVsOne, hands, boneyard);
        empty.setCurrentPlayerIndex(0);
        MatchController opener(empty);
        check(!opener.canVoluntaryDraw(),
              "the opener faces an empty chain and holds a legal lead, so a draw is not a rules action");

        GameState opened(GameMode::OneVsOne, hands, boneyard);
        opened.playTile(0, DominoTile(3, 3), GameState::ChainSide::Left);
        opened.setCurrentPlayerIndex(1);
        MatchController afterOpen(opened);
        check(afterOpen.canVoluntaryDraw(),
              "once the chain is open, a voluntary draw is available again");
    }

    if (failureCount() == 0) {
        std::cout << "\nMatchController: all checks passed\n";
        return 0;
    }
    std::cout << "\nMatchController: " << failureCount() << " check(s) failed\n";
    return 1;
}
