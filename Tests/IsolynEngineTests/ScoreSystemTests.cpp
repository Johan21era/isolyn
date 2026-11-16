#include "ScoreSystem.hpp"
#include "TestHarness.hpp"

using namespace isolyn;
using namespace isolyn::test;

int main() {
    section("ScoreSystem: initial scores are zero for every participant");
    {
        ScoreSystem scores(GameMode::OneVsOne, 2);
        check(scores.score(0) == 0 && scores.score(1) == 0, "every participant starts at zero");
    }

    section("ScoreSystem: applyRoundScores adds to the running total, doesn't replace it");
    {
        ScoreSystem scores(GameMode::OneVsOne, 2);
        scores.applyRoundScores({0, 22});
        check(scores.score(0) == 0 && scores.score(1) == 22, "first round's scores applied directly");
        scores.applyRoundScores({0, 15});
        check(scores.score(0) == 0 && scores.score(1) == 37, "second round adds onto the running total (22+15=37)");
    }

    section("ScoreSystem: hasMatchEnded respects each mode's own threshold");
    {
        ScoreSystem oneVsOne(GameMode::OneVsOne, 2);
        oneVsOne.applyRoundScores({0, 150});
        check(!oneVsOne.hasMatchEnded(), "150 hasn't reached 1v1's 151 threshold yet");
        oneVsOne.applyRoundScores({0, 1});
        check(oneVsOne.hasMatchEnded(), "151 has reached the threshold");

        ScoreSystem twoVsTwo(GameMode::TwoVsTwo, 2);
        twoVsTwo.applyRoundScores({0, 150});
        check(!twoVsTwo.hasMatchEnded(), "150 hasn't reached 2v2's 151 threshold yet");
        twoVsTwo.applyRoundScores({0, 1});
        check(twoVsTwo.hasMatchEnded(), "151 has reached the threshold");
    }

    section("ScoreSystem: R-06 1v1 short game ends at 101, other modes stay at 151");
    {
        ScoreSystem shortOneVsOne(GameMode::OneVsOne, 2, 101);
        shortOneVsOne.applyRoundScores({100, 0});
        check(!shortOneVsOne.hasMatchEnded(), "1v1 short game: 100 is still live");
        shortOneVsOne.applyRoundScores({1, 0});
        check(shortOneVsOne.hasMatchEnded(), "1v1 short game: 101 ends the set");

        ScoreSystem shortOneVsOneVsOne(GameMode::OneVsOneVsOne, 3, 101);
        shortOneVsOneVsOne.applyRoundScores({101, 0, 0});
        check(!shortOneVsOneVsOne.hasMatchEnded(),
              "1v1v1 ignores the short target and does not end at 101");
        shortOneVsOneVsOne.applyRoundScores({50, 0, 0});
        check(shortOneVsOneVsOne.hasMatchEnded(),
              "1v1v1 still ends at its locked 151 threshold");
    }

    section("ScoreSystem: R-22 applies a survivor round to only the live participants");
    {
        ScoreSystem scores(GameMode::OneVsOneVsOne, 3);
        scores.applyRoundScores({0, 60, 151}); // participant 2 is out
        scores.applyRoundScoresForParticipants({12}, {1});
        check(scores.score(0) == 0 && scores.score(1) == 72 && scores.score(2) == 151,
              "a survivor round credits only participant 1 and leaves the eliminated participant's frozen total alone");
    }

    section("ScoreSystem: R-06 winningParticipant is whoever reached the target, because those points were scored off the opponent");
    {
        ScoreSystem scores(GameMode::OneVsOneVsOne, 3);
        scores.applyRoundScores({0, 60, 151}); // participant 2 crosses 1v1v1's 151 threshold
        check(scores.hasMatchEnded(), "the match ends the instant anyone crosses the threshold");
        check(scores.winningParticipant() == 2, "participant 2, who reached the target, wins -- not the lowest score");
    }

    if (failureCount() == 0) {
        std::cout << "\nScoreSystem: all checks passed\n";
        return 0;
    }
    std::cout << "\nScoreSystem: " << failureCount() << " check(s) failed\n";
    return 1;
}
