#include "RulesEngine.hpp"
#include "TestHarness.hpp"
#include <vector>

using isolyn::DominoTile;
using isolyn::RulesEngine;
using namespace isolyn::test;

int main() {
    section("RulesEngine: highest double opens");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(1, 1), DominoTile(3, 2) },
            { DominoTile(4, 4), DominoTile(0, 1) },
            { DominoTile(6, 2), DominoTile(5, 5) },
        };
        auto decision = RulesEngine::determineOpeningPlay(hands);
        check(decision.openingPlayerIndex == 2 && decision.openingTile == DominoTile(5, 5),
              "5-5 (player 2) beats 4-4 and 1-1 for the opening play");
    }

    section("RulesEngine: no doubles anywhere, highest value opens (Sec. 4 examples)");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 5), DominoTile(1, 0) },
            { DominoTile(6, 4), DominoTile(2, 1) },
        };
        auto decision = RulesEngine::determineOpeningPlay(hands);
        check(decision.openingPlayerIndex == 0 && decision.openingTile == DominoTile(6, 5),
              "6-5 beats 6-4 when nobody holds a double, per Sec. 4's own example");
    }

    section("RulesEngine: any double outranks every non-double, not just the best overall tile");
    {
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(6, 5) },
            { DominoTile(0, 0) },
        };
        auto decision = RulesEngine::determineOpeningPlay(hands);
        check(decision.openingPlayerIndex == 1 && decision.openingTile == DominoTile(0, 0),
              "0-0, the lowest possible double, still opens over 6-5 -- "
              "the fallback only fires when NO player holds ANY double");
    }

    section("RulesEngine: determineCloser -- doubles CAN close outside 1v1");
    {
        std::vector<isolyn::PlayRecord> moves = {
            { 0, DominoTile(3, 2) },
            { 1, DominoTile(2, 2) }, // closing double, 1v1v1 -- should count
        };
        check(RulesEngine::determineCloser(isolyn::GameMode::OneVsOneVsOne, moves) == 1,
              "1v1v1: a closing double is credited to whoever played it");
    }

    section("RulesEngine: determineCloser -- doubles CANNOT close in 1v1, walks back one");
    {
        std::vector<isolyn::PlayRecord> moves = {
            { 0, DominoTile(6, 3) },
            { 1, DominoTile(3, 3) }, // closing double, 1v1 -- doesn't count
        };
        check(RulesEngine::determineCloser(isolyn::GameMode::OneVsOne, moves) == 0,
              "1v1: closing double is skipped, credit goes to the preceding non-double's player");
    }

    section("RulesEngine: determineCloser -- 1v1 walks back through a whole run of doubles");
    {
        std::vector<isolyn::PlayRecord> moves = {
            { 0, DominoTile(4, 3) },
            { 1, DominoTile(2, 2) },
            { 0, DominoTile(5, 5) }, // two doubles in a row before the close
        };
        check(RulesEngine::determineCloser(isolyn::GameMode::OneVsOne, moves) == 0,
              "1v1: walks back through consecutive doubles to the last real non-double play");
    }

    section("RulesEngine: determineCloser -- 1v1 with no double involved at all");
    {
        std::vector<isolyn::PlayRecord> moves = { { 0, DominoTile(1, 1) }, { 1, DominoTile(5, 2) } };
        check(RulesEngine::determineCloser(isolyn::GameMode::OneVsOne, moves) == 1,
              "1v1: a non-double closer is simply credited directly, no walk-back needed");
    }

    section("RulesEngine: computeRoundScores -- worked examples from both source documents");
    {
        // R-03 / R-20: the higher hand loses and its total is credited to the
        // lower hand. "If it's 50-50 and you catch me with 43, it's 93-50."
        auto domino1v1 = RulesEngine::computeRoundScores({0, 22});
        check(domino1v1 == std::vector<int>({22, 0}), "1v1 Domino: the winner's empty hand is credited with the opponent's 22");

        auto closed1v1 = RulesEngine::computeRoundScores({24, 9});
        check(closed1v1 == std::vector<int>({0, 24}), "1v1 Close: 24 vs 9 -> the lower hand (9) takes the 24");

        auto tied1v1 = RulesEngine::computeRoundScores({10, 10});
        check(tied1v1 == std::vector<int>({0, 0}), "1v1 Close, tied at 10: no points awarded to either side");

        // R-04: with three players each hand above the lowest adds its own.
        auto oneVsOneVsOne = RulesEngine::computeRoundScores({6, 12, 41});
        check(oneVsOneVsOne == std::vector<int>({0, 12, 41}), "1v1v1: hands of 6, 12, 41 -> 0-12-41, the rulebook's own example");
        auto oneVsOneVsOneWorked = RulesEngine::computeRoundScores({10, 24, 31});
        check(oneVsOneVsOneWorked == std::vector<int>({0, 24, 31}), "1v1v1: A=10 -> 0, B=24 -> 24, C=31 -> 31");
        // R-04: the closer is not exempt when his hand is above the lowest.
        auto closerWithHighest = RulesEngine::computeRoundScores({41, 6, 12});
        check(closerWithHighest == std::vector<int>({41, 0, 12}),
              "1v1v1: the closer is not exempt -- 41, 6, 12 -> 41-0-12, only the lowest is spared");

        // R-05: 2v2 combines partners, then the losing team's total moves over.
        int teamA = RulesEngine::combineTeamValue(20, 6);
        int teamB = RulesEngine::combineTeamValue(15, 12);
        check(teamA == 26 && teamB == 27, "2v2 team combination: 20+6=26, 15+12=27");
        auto twoVsTwo = RulesEngine::computeRoundScores({teamA, teamB});
        check(twoVsTwo == std::vector<int>({27, 0}), "2v2: lower combined (26) takes the opponent team's 27");
        auto teamOnSixteen = RulesEngine::computeRoundScores({16, 21});
        check(teamOnSixteen == std::vector<int>({21, 0}), "2v2: a team on 16 losing to 21 scores the 21");
    }

    section("RulesEngine: the double blank -- ten when alone, zero when paired");
    {
        check(DominoTile(0, 0).value() == 0, "double blank bears zero pips");
        check(RulesEngine::handPoints({DominoTile(0, 0)}) == 10,
              "a hand of only the double blank is worth ten");
        check(RulesEngine::handPoints({DominoTile(4, 3), DominoTile(0, 0), DominoTile(2, 1)}) == 10,
              "the rulebook's tally: 4-3 + 0-0 + 2-1 = 10");
        check(RulesEngine::handPoints({DominoTile(0, 0), DominoTile(0, 5)}) == 5,
              "paired with any other tile the blank adds nothing");
        check(RulesEngine::handPoints({DominoTile(6, 3)}) == 9, "ordinary tiles score their pips");
        check(RulesEngine::handPoints({DominoTile(6, 6)}) == 12, "double six scores twelve");
        auto blankDoubleLoses = RulesEngine::computeRoundScores({10, 0});
        check(blankDoubleLoses == std::vector<int>({0, 10}),
              "the double blank alone hands the winner ten");
    }

    section("RulesEngine: hasReachedMatchLossThreshold -- reaches OR exceeds, not strictly exceeds");
    {
        check(!RulesEngine::hasReachedMatchLossThreshold(isolyn::GameMode::OneVsOne, 100),
              "1v1: 100 has not reached the 101 threshold");
        check(RulesEngine::hasReachedMatchLossThreshold(isolyn::GameMode::OneVsOne, 101),
              "1v1: exactly 101 has reached the threshold");
        check(!RulesEngine::hasReachedMatchLossThreshold(isolyn::GameMode::TwoVsTwo, 150),
              "2v2: 150 has not reached the 151 threshold");
        check(RulesEngine::hasReachedMatchLossThreshold(isolyn::GameMode::TwoVsTwo, 151),
              "2v2: exactly 151 has reached the threshold");
        check(!RulesEngine::hasReachedMatchLossThreshold(isolyn::GameMode::OneVsOneVsOne, 150),
              "1v1v1: 150 has not reached the 151 threshold");
        check(RulesEngine::hasReachedMatchLossThreshold(isolyn::GameMode::OneVsOneVsOne, 151),
              "1v1v1: 151 is the locked threshold, not 101 (RULEBOOK R-06)");
    }

    section("RulesEngine: determineNextRoundStarter -- pass-through, documented invariant");
    {
        check(RulesEngine::determineNextRoundStarter(2) == 2,
              "whoever won by Domino or was credited as closer starts next, regardless of round outcome");
    }

    if (failureCount() == 0) {
        std::cout << "\nRulesEngine: all checks passed\n";
        return 0;
    }
    std::cout << "\nRulesEngine: " << failureCount() << " check(s) failed\n";
    return 1;
}
