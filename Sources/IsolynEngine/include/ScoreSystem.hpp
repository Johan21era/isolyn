#pragma once
#include <vector>
#include "GameMode.hpp"
#include "RulesEngine.hpp"

namespace isolyn {

// Tracks running scores across a match and detects when the match ends.
// Operates on however many "participants" the mode has: one entry per
// player for 1v1/1v1v1, one entry per TEAM for 2v2 (team-combination via
// RulesEngine::combineTeamValue happens before scores ever reach this
// class -- ScoreSystem itself doesn't know or care whether an entry
// represents one player or a partnership).
class ScoreSystem {
public:
    explicit ScoreSystem(GameMode mode, int participantCount,
                         int oneVsOneTarget = RulesEngine::kMatchTarget);

    // How many participants this tracker holds (players for 1v1/1v1v1, teams
    // for 2v2) -- exposed so callers copying scores out can size correctly
    // without being handed the constructor arguments again.
    int participantCount() const { return static_cast<int>(m_scores.size()); }

    int score(int participantIndex) const;

    // Adds `roundScores` (as returned by RulesEngine::computeRoundScores)
    // to each participant's running total, one entry per participant, in
    // the same order.
    void applyRoundScores(const std::vector<int>& roundScores);

    // Whether any participant has reached or passed the mode's target, which
    // wins the set (RulesEngine::hasReachedMatchTarget).
    // `oneVsOneTarget` is the R-06 pre-game choice (151 by default, 101 in
    // 1v1 only); the other modes ignore it.
    bool hasMatchEnded() const;

    // The winning participant once hasMatchEnded() is true: whoever has
    // the highest running score, i.e. the participant who reached the
    // target (R-06). The same rule serves every mode -- 1v1v1 no longer
    // eliminates anyone, so there is no separate survivor winner (R-22).
    //
    // Precondition: hasMatchEnded() is true.
    int winningParticipant() const;

private:
    GameMode m_mode;
    int m_oneVsOneTarget;
    std::vector<int> m_scores;
};

} // namespace isolyn
