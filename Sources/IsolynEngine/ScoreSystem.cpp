#include "ScoreSystem.hpp"
#include "RulesEngine.hpp"
#include <cassert>

namespace isolyn {

ScoreSystem::ScoreSystem(GameMode mode, int participantCount, int oneVsOneTarget)
    : m_mode(mode),
      m_oneVsOneTarget(oneVsOneTarget),
      m_scores(static_cast<std::size_t>(participantCount), 0) {}

int ScoreSystem::score(int participantIndex) const {
    assert(participantIndex >= 0 && participantIndex < static_cast<int>(m_scores.size()));
    return m_scores[static_cast<std::size_t>(participantIndex)];
}

void ScoreSystem::applyRoundScores(const std::vector<int>& roundScores) {
    assert(roundScores.size() == m_scores.size());
    for (std::size_t i = 0; i < m_scores.size(); ++i) {
        m_scores[i] += roundScores[i];
    }
}

void ScoreSystem::applyRoundScoresForParticipants(
    const std::vector<int>& roundScores,
    const std::vector<int>& participantIndices) {
    assert(roundScores.size() == participantIndices.size());
    for (std::size_t i = 0; i < roundScores.size(); ++i) {
        const int p = participantIndices[i];
        assert(p >= 0 && p < static_cast<int>(m_scores.size()));
        m_scores[static_cast<std::size_t>(p)] += roundScores[i];
    }
}

bool ScoreSystem::hasMatchEnded() const {
    for (int s : m_scores) {
        if (RulesEngine::hasReachedMatchTarget(m_mode, s, m_oneVsOneTarget)) return true;
    }
    return false;
}

int ScoreSystem::winningParticipant() const {
    assert(hasMatchEnded());
    // R-06 (rules version 2): points are scored off the opponent, so the player
    // who reaches or passes the target WINS the set. This used to return the
    // lowest scorer, which inverted the finish line.
    int best = 0;
    for (int i = 1; i < static_cast<int>(m_scores.size()); ++i) {
        if (m_scores[static_cast<std::size_t>(i)] > m_scores[static_cast<std::size_t>(best)]) {
            best = i;
        }
    }
    return best;
}

} // namespace isolyn
