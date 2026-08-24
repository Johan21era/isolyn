#pragma once
#include <vector>
#include "GameMode.hpp"

namespace isolyn {

// Tracks running scores across a match and detects when the match ends.
// Operates on however many "participants" the mode has: one entry per
// player for 1v1/1v1v1, one entry per TEAM for 2v2 (team-combination via
// RulesEngine::combineTeamValue happens before scores ever reach this
// class -- ScoreSystem itself doesn't know or care whether an entry
// represents one player or a partnership).
class ScoreSystem {
public:
    explicit ScoreSystem(GameMode mode, int participantCount);

    // How many participants this tracker holds (players for 1v1/1v1v1, teams
    // for 2v2) -- exposed so callers copying scores out can size correctly
    // without being handed the constructor arguments again.
    int participantCount() const { return static_cast<int>(m_scores.size()); }

    int score(int participantIndex) const;

    // Adds `roundScores` (as returned by RulesEngine::computeRoundScores)
    // to each participant's running total, one entry per participant, in
    // the same order.
    void applyRoundScores(const std::vector<int>& roundScores);

    // Whether any participant has reached or exceeded the mode's
    // match-loss threshold (RulesEngine::hasReachedMatchLossThreshold).
    bool hasMatchEnded() const;

    // The winning participant once hasMatchEnded() is true: whoever has
    // the strictly lowest running score among all participants.
    //
    // Assumption, not stated by either document: neither text says what
    // happens with more than two participants once the threshold is
    // crossed -- specifically, whether the non-crossing participants in
    // 1v1v1 are both declared winners, or the lower of the two wins
    // outright. Implemented as a single outright winner (lowest score,
    // full stop), matching the conventional handling in comparable
    // threshold-ending scoring games. Flagged for confirmation, not
    // treated as settled.
    //
    // Precondition: hasMatchEnded() is true.
    int winningParticipant() const;

private:
    GameMode m_mode;
    std::vector<int> m_scores;
};

} // namespace isolyn
