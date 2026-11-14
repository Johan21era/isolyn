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

    section("ScoreSystem: winningParticipant is whoever has the strictly lowest score once the match has ended");
    {
        ScoreSystem scores(GameMode::OneVsOneVsOne, 3);
        scores.applyRoundScores({0, 60, 151}); // participant 2 crosses 1v1v1's 151 threshold
        check(scores.hasMatchEnded(), "the match ends the instant anyone crosses the threshold");
        check(scores.winningParticipant() == 0, "participant 0, with the strictly lowest score, is the outright winner");
    }

    if (failureCount() == 0) {
        std::cout << "\nScoreSystem: all checks passed\n";
        return 0;
    }
    std::cout << "\nScoreSystem: " << failureCount() << " check(s) failed\n";
    return 1;
}
