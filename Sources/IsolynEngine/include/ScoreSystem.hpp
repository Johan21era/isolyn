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
                         int oneVsOneTarget = RulesEngine::kOneVsOneMatchTarget);

    // How many participants this tracker holds (players for 1v1/1v1v1, teams
    // for 2v2) -- exposed so callers copying scores out can size correctly
    // without being handed the constructor arguments again.
    int participantCount() const { return static_cast<int>(m_scores.size()); }

    int score(int participantIndex) const;

    // Adds `roundScores` (as returned by RulesEngine::computeRoundScores)
    // to each participant's running total, one entry per participant, in
    // the same order.
    void applyRoundScores(const std::vector<int>& roundScores);

    // R-22: applies a round scored over only the still-active participants
    // to their slots, leaving eliminated players' frozen scores untouched.
    // `roundScores[i]` belongs to `participantIndices[i]`.
    void applyRoundScoresForParticipants(const std::vector<int>& roundScores,
                                         const std::vector<int>& participantIndices);

    // Whether any participant has reached or exceeded the mode's
    // match-loss threshold (RulesEngine::hasReachedMatchTarget).
    // `oneVsOneTarget` is the R-06 pre-game choice (151 by default, 101 in
    // 1v1 only); the other modes ignore it.
    bool hasMatchEnded() const;

    // The winning participant once hasMatchEnded() is true: whoever has
    // the strictly lowest running score among all participants.
    //
    // R-22 supersedes this for 1v1v1: that mode ends a set when only one
    // active participant remains, and that survivor is the set winner. The
    // bridge implements that directly rather than calling this method.
    // This remains the 1v1/2v2 winner rule.
    //
    // Precondition: hasMatchEnded() is true.
    int winningParticipant() const;

private:
    GameMode m_mode;
    int m_oneVsOneTarget;
    std::vector<int> m_scores;
};

} // namespace isolyn
