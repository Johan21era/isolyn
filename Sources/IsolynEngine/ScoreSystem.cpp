#include "ScoreSystem.hpp"
#include "RulesEngine.hpp"
#include <cassert>

namespace isolyn {

ScoreSystem::ScoreSystem(GameMode mode, int participantCount)
    : m_mode(mode), m_scores(static_cast<std::size_t>(participantCount), 0) {}

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
        if (RulesEngine::hasReachedMatchLossThreshold(m_mode, s)) return true;
    }
    return false;
}

int ScoreSystem::winningParticipant() const {
    assert(hasMatchEnded());
    int best = 0;
    for (int i = 1; i < static_cast<int>(m_scores.size()); ++i) {
        if (m_scores[static_cast<std::size_t>(i)] < m_scores[static_cast<std::size_t>(best)]) {
            best = i;
        }
    }
    return best;
}

} // namespace isolyn
