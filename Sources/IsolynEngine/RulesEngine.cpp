#include "RulesEngine.hpp"
#include <algorithm>
#include <cassert>
#include <optional>

namespace isolyn {

OpeningDecision RulesEngine::determineOpeningPlay(const std::vector<std::vector<DominoTile>>& hands) {
    assert(!hands.empty());

    // Pass 1: highest double across every hand. Any double at all
    // outranks every non-double -- the fallback below only applies when
    // NO player holds ANY double, not merely when the specific comparison
    // at hand lacks one.
    std::optional<int> bestDoublePlayer;
    std::optional<DominoTile> bestDouble;

    for (int playerIndex = 0; playerIndex < static_cast<int>(hands.size()); ++playerIndex) {
        for (const DominoTile& tile : hands[static_cast<std::size_t>(playerIndex)]) {
            if (!tile.isDouble()) continue;
            if (!bestDouble.has_value() || tile.value() > bestDouble->value()) {
                bestDouble = tile;
                bestDoublePlayer = playerIndex;
            }
        }
    }

    if (bestDouble.has_value()) {
        return OpeningDecision{*bestDoublePlayer, *bestDouble};
    }

    // Pass 2: nobody holds any double. Rules Spec's fallback: "the highest
    // numerical domino begins," with examples 6-5 beats 6-4, 6-4 beats
    // 6-3, 5-4 beats 5-3.
    //
    // OPEN QUESTION, flagged rather than silently resolved: every example
    // Rules Spec gives compares two tiles that share the same high side
    // (6-5 vs 6-4 vs 6-3; 5-4 vs 5-3). None of them distinguishes "rank by
    // summed value" from "rank by high side first, low side as tiebreak"
    // -- the two methods agree on every given example but would disagree
    // on a case like 6-1 (sum 7) vs 5-4 (sum 9): sum-ranking picks 5-4,
    // high-side-first ranking picks 6-1. Implemented below as sum-based,
    // because Section 1 already defines a domino's "value" as Left+Right
    // for the whole document, and reusing that established definition for
    // "highest numerical domino" is the more textually grounded reading
    // than inventing an unstated lexicographic rule. This is a single
    // isolated comparison (see the loop below) -- trivial to flip if the
    // intended rule turns out to be high-side-first.
    std::optional<int> bestPlainPlayer;
    std::optional<DominoTile> bestPlain;

    for (int playerIndex = 0; playerIndex < static_cast<int>(hands.size()); ++playerIndex) {
        for (const DominoTile& tile : hands[static_cast<std::size_t>(playerIndex)]) {
            if (!bestPlain.has_value() || tile.value() > bestPlain->value()) {
                bestPlain = tile;
                bestPlainPlayer = playerIndex;
            }
        }
    }

    assert(bestPlain.has_value() && "hands must be non-empty");
    return OpeningDecision{*bestPlainPlayer, *bestPlain};
}

int RulesEngine::determineCloser(GameMode mode, const std::vector<PlayRecord>& playedMoves) {
    assert(!playedMoves.empty());

    if (mode != GameMode::OneVsOne) {
        // 1v1v1 and 2v2 both explicitly allow doubles to close.
        return playedMoves.back().playerIndex;
    }

    // 1v1: walk backward past any run of doubles at the end of the
    // sequence to find the most recent non-double play.
    for (auto it = playedMoves.rbegin(); it != playedMoves.rend(); ++it) {
        if (!it->tile.isDouble()) {
            return it->playerIndex;
        }
    }

    // Every play in the round was a double -- see the open-question note
    // on this function in the header. Not crashing, not fabricating a
    // rule; just not silently pretending this case was specified.
    return playedMoves.back().playerIndex;
}

std::vector<int> RulesEngine::computeRoundScores(const std::vector<int>& remainingValues) {
    assert(!remainingValues.empty());
    const int minimum = *std::min_element(remainingValues.begin(), remainingValues.end());

    std::vector<int> scores;
    scores.reserve(remainingValues.size());
    for (int value : remainingValues) {
        scores.push_back(value == minimum ? 0 : value);
    }
    return scores;
}

int RulesEngine::combineTeamValue(int partnerAValue, int partnerBValue) {
    return partnerAValue + partnerBValue;
}

bool RulesEngine::hasReachedMatchLossThreshold(GameMode mode, int runningScore) {
    switch (mode) {
        case GameMode::OneVsOne: return runningScore >= kOneVsOneMatchLossThreshold;
        case GameMode::OneVsOneVsOne: return runningScore >= kOneVsOneVsOneMatchLossThreshold;
        case GameMode::TwoVsTwo: return runningScore >= kTwoVsTwoMatchLossThreshold;
    }
    return false; // unreachable -- every GameMode enumerator is handled above
}

int RulesEngine::determineNextRoundStarter(int winnerOrCloserPlayerIndex) {
    return winnerOrCloserPlayerIndex;
}

int RulesEngine::teamIndexForPlayer(int playerIndex) {
    return playerIndex % 2;
}

std::pair<int, int> RulesEngine::playersOnTeam(int teamIndex) {
    return { teamIndex, teamIndex + 2 };
}

} // namespace isolyn
