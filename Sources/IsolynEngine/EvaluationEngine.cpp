#include "EvaluationEngine.hpp"
#include <optional>
#include "BlockingHeuristic.hpp"
#include "ClosingOpportunityHeuristic.hpp"
#include "ExpectedValueHeuristic.hpp"
#include "MobilityHeuristic.hpp"
#include "MoveGenerator.hpp"
#include "RulesEngine.hpp"

namespace isolyn {

namespace {

// RULEBOOK.md R-19: a hand is worth its pips, except the double blank, which
// is worth ten when it is the only tile left. Scoring uses handPoints; if the
// evaluation used raw pips, the engine would believe a lone 0-0 is worthless
// while the scoreboard charges it ten — the same defect that made the app
// under-award a round.
int handValueOf(const GameState& state, int playerIndex) {
    return RulesEngine::handPoints(state.hand(playerIndex));
}

struct HandFacts {
    int value = 0;
    int legalMoves = 0;
};

// The batch path needs both the hand value and the legal-move count. Computing
// them together avoids scanning every hand twice at every leaf.
HandFacts handFacts(const GameState& state, int playerIndex) {
    HandFacts facts;
    const auto& hand = state.hand(playerIndex);
    if (state.chain().isEmpty()) {
        facts.value = RulesEngine::handPoints(hand);
        facts.legalMoves = static_cast<int>(hand.size());
        return facts;
    }

    const int left = state.chain().leftEnd();
    const int right = state.chain().rightEnd();
            for (const auto& tile : hand) {
            if (tile.hasFace(left)) ++facts.legalMoves;
            if (tile.hasFace(right)) ++facts.legalMoves;
        }
        facts.value = RulesEngine::handPoints(hand);
    return facts;
}

bool hasImmediateDominoWin(const GameState& state, int playerIndex) {
    return state.hand(playerIndex).size() == 1 &&
           MoveGenerator::hasAnyLegalMove(state, playerIndex);
}

double teamMobility(const GameState& state, int teamIndex) {
    auto team = RulesEngine::playersOnTeam(teamIndex);
    return MobilityHeuristic::score(state, team.first) +
           MobilityHeuristic::score(state, team.second);
}

} // namespace

EvaluationBreakdown EvaluationEngine::evaluate(GameMode mode,
                                               const GameState& state,
                                               int playerIndex,
                                               const EvaluationWeights& weights,
                                               const EvaluationWeights* positionalWeights) {
    EvaluationBreakdown breakdown{};

    // Terminal Domino state. Once ANY hand is empty, the round is over;
    // this is not a normal position where the remaining players can still
    // race to finish. Award zero to the winner (and, in 2v2, the winning
    // partner) and only material loss to everyone else. Without this
    // guard a loser holding one playable tile receives the +1000 immediate
    // win-threat bonus after the opponent has already emptied their hand,
    // which makes a lost position evaluate as a win.
    int emptyPlayer = -1;
    for (int p = 0; p < state.playerCount(); ++p) {
        if (state.hand(p).empty()) {
            emptyPlayer = p;
            break;
        }
    }
    if (emptyPlayer >= 0) {
        bool onWinningSide = (playerIndex == emptyPlayer);
        if (mode == GameMode::TwoVsTwo) {
            onWinningSide = RulesEngine::teamIndexForPlayer(playerIndex) ==
                            RulesEngine::teamIndexForPlayer(emptyPlayer);
        }
        if (!onWinningSide) {
            breakdown.expectedValue = -static_cast<double>(handValueOf(state, playerIndex));
            breakdown.total = weights.expectedValue * breakdown.expectedValue;
        }
        return breakdown;
    }

    breakdown.mobility = MobilityHeuristic::score(state, playerIndex);
    breakdown.blocking = BlockingHeuristic::score(state, playerIndex);
    breakdown.expectedValue = ExpectedValueHeuristic::score(state, playerIndex);
    breakdown.closingOpportunity = 0.0;

    if (MoveGenerator::isPositionClosed(state)) {
        std::vector<int> participantValues;
        int evaluatedParticipantIndex = playerIndex;
        int closerParticipantIndex;
        int closerPlayer = RulesEngine::determineCloser(mode, state.playHistory());

        if (mode == GameMode::TwoVsTwo) {
            auto team0 = RulesEngine::playersOnTeam(0);
            auto team1 = RulesEngine::playersOnTeam(1);
            int team0Value = RulesEngine::combineTeamValue(handValueOf(state, team0.first), handValueOf(state, team0.second));
            int team1Value = RulesEngine::combineTeamValue(handValueOf(state, team1.first), handValueOf(state, team1.second));
            participantValues = { team0Value, team1Value };
            evaluatedParticipantIndex = RulesEngine::teamIndexForPlayer(playerIndex);
            closerParticipantIndex = RulesEngine::teamIndexForPlayer(closerPlayer);
        } else {
            for (int p = 0; p < state.playerCount(); ++p) {
                participantValues.push_back(handValueOf(state, p));
            }
            closerParticipantIndex = closerPlayer;
        }

        auto roundScores = RulesEngine::computeRoundScores(participantValues);
        breakdown.closingOpportunity =
            ClosingOpportunityHeuristic::score(roundScores, evaluatedParticipantIndex, closerParticipantIndex);
    }

    // Immediate-win detection. This is deliberately large enough to
    // dominate the positional terms at a search horizon: if a participant
    // can empty their hand next turn, no mobility/pip score should hide it.
    if (mode == GameMode::TwoVsTwo) {
        auto myTeam = RulesEngine::playersOnTeam(RulesEngine::teamIndexForPlayer(playerIndex));
        auto otherTeam = RulesEngine::playersOnTeam(1 - RulesEngine::teamIndexForPlayer(playerIndex));
        if (hasImmediateDominoWin(state, myTeam.first) || hasImmediateDominoWin(state, myTeam.second)) {
            breakdown.winThreat += 1000.0;
        }
        if (hasImmediateDominoWin(state, otherTeam.first) || hasImmediateDominoWin(state, otherTeam.second)) {
            breakdown.winThreat -= 1000.0;
        }
    } else {
        if (hasImmediateDominoWin(state, playerIndex)) breakdown.winThreat += 1000.0;
        for (int p = 0; p < state.playerCount(); ++p) {
            if (p != playerIndex && hasImmediateDominoWin(state, p)) breakdown.winThreat -= 1000.0;
        }
    }

    // Pip control: how many of this player's tiles can attach to either
    // exposed end. This is a sharper signal than generic mobility because
    // it measures ownership of the currently relevant numbers.
    if (!state.chain().isEmpty()) {
        int controlled = 0;
        const int left = state.chain().leftEnd();
        const int right = state.chain().rightEnd();
        for (const auto& tile : state.hand(playerIndex)) {
            if (tile.hasFace(left)) ++controlled;
            if (tile.hasFace(right)) ++controlled;
        }
        breakdown.pipControl = 0.5 * static_cast<double>(controlled);
    }

    // Tempo: acting now is a small advantage. In 2v2, either partner
    // acting counts as team tempo.
    if (mode == GameMode::TwoVsTwo) {
        if (RulesEngine::teamIndexForPlayer(state.currentPlayerIndex()) ==
            RulesEngine::teamIndexForPlayer(playerIndex)) {
            breakdown.tempo = 1.0;
        }
    } else if (state.currentPlayerIndex() == playerIndex) {
        breakdown.tempo = 1.0;
    }

    // Partnership awareness: a partner with options is an asset. This is
    // intentionally small -- it must not swamp the player's own position.
    if (mode == GameMode::TwoVsTwo) {
        const int myTeam = RulesEngine::teamIndexForPlayer(playerIndex);
        const double ourMobility = teamMobility(state, myTeam);
        breakdown.teamSupport = 0.25 * ourMobility;
    }

    // Two-regime selection. The regime is a property of the position, not of
    // the player being scored, so every player in one state is evaluated under
    // the same vector. The predicate is only consulted when a second vector
    // exists, which keeps the single-vector path byte-for-byte unchanged.
    const EvaluationWeights* effective = &weights;
    if (positionalWeights != nullptr) {
        bool anyThreat = false;
        for (int p = 0; p < state.playerCount(); ++p) {
            if (hasImmediateDominoWin(state, p)) {
                anyThreat = true;
                break;
            }
        }
        if (!anyThreat) effective = positionalWeights;
    }
    const EvaluationWeights& w = *effective;

    breakdown.total = w.mobility * breakdown.mobility
                     + w.blocking * breakdown.blocking
                     + w.expectedValue * breakdown.expectedValue
                     + w.closingOpportunity * breakdown.closingOpportunity
                     + w.winThreat * breakdown.winThreat
                     + w.pipControl * breakdown.pipControl
                     + w.tempo * breakdown.tempo
                     + w.teamSupport * breakdown.teamSupport;
    return breakdown;
}

static EvaluationTotals evaluateAllImpl(GameMode mode,
                                        const GameState& state,
                                        const EvaluationWeights& weights,
                                        std::optional<bool> knownClosed,
                                        const EvaluationWeights* positionalWeights) {
    EvaluationTotals result;
    const int playerCount = state.playerCount();
    result.playerCount = playerCount;

    std::array<int, 4> handValues{};
    std::array<double, 4> mobility{};
    std::array<bool, 4> threats{};
    int emptyPlayer = -1;
    for (int p = 0; p < playerCount; ++p) {
        if (state.hand(p).empty()) {
            emptyPlayer = p;
            break;
        }
    }

    if (emptyPlayer >= 0) {
        for (int p = 0; p < playerCount; ++p) {
            bool onWinningSide = (p == emptyPlayer);
            if (mode == GameMode::TwoVsTwo) {
                onWinningSide = RulesEngine::teamIndexForPlayer(p) ==
                                RulesEngine::teamIndexForPlayer(emptyPlayer);
            }
            result.totals[static_cast<std::size_t>(p)] = onWinningSide
                ? 0.0
                : weights.expectedValue * -static_cast<double>(handValueOf(state, p));
        }
        return result;
    }

    bool allPlayersStuck = true;
    for (int p = 0; p < playerCount; ++p) {
        const HandFacts facts = handFacts(state, p);
        handValues[static_cast<std::size_t>(p)] = facts.value;
        mobility[static_cast<std::size_t>(p)] = static_cast<double>(facts.legalMoves);
        if (facts.legalMoves > 0) allPlayersStuck = false;
        // A one-tile hand is an immediate threat exactly when it has a legal
        // move; mobility already answers that question without a second scan.
        threats[static_cast<std::size_t>(p)] =
            state.hand(p).size() == 1 && facts.legalMoves > 0;
    }

    // Two-regime selection: one vector per state, chosen from the threat scan
    // that already ran above. Null (the default) keeps the single-vector path
    // and costs nothing.
    const EvaluationWeights* effective = &weights;
    if (positionalWeights != nullptr) {
        bool anyThreat = false;
        for (int p = 0; p < playerCount; ++p) {
            if (threats[static_cast<std::size_t>(p)]) {
                anyThreat = true;
                break;
            }
        }
        if (!anyThreat) effective = positionalWeights;
    }
    const EvaluationWeights& w = *effective;

    std::array<double, 4> closing{};
    const bool positionClosed = knownClosed.value_or(
        state.boneyard().drawableCount() == 0 && allPlayersStuck);
    if (positionClosed) {
        std::vector<int> participantValues;
        int closerPlayer = RulesEngine::determineCloser(mode, state.playHistory());
        if (mode == GameMode::TwoVsTwo) {
            const auto team0 = RulesEngine::playersOnTeam(0);
            const auto team1 = RulesEngine::playersOnTeam(1);
            participantValues = {
                RulesEngine::combineTeamValue(handValues[static_cast<std::size_t>(team0.first)],
                                              handValues[static_cast<std::size_t>(team0.second)]),
                RulesEngine::combineTeamValue(handValues[static_cast<std::size_t>(team1.first)],
                                              handValues[static_cast<std::size_t>(team1.second)]),
            };
            const auto roundScores = RulesEngine::computeRoundScores(participantValues);
            for (int p = 0; p < playerCount; ++p) {
                const int participant = RulesEngine::teamIndexForPlayer(p);
                const int closerParticipant = RulesEngine::teamIndexForPlayer(closerPlayer);
                closing[static_cast<std::size_t>(p)] =
                    ClosingOpportunityHeuristic::score(roundScores, participant, closerParticipant);
            }
        } else {
            participantValues.assign(handValues.begin(),
                                     handValues.begin() + playerCount);
            const auto roundScores = RulesEngine::computeRoundScores(participantValues);
            for (int p = 0; p < playerCount; ++p) {
                closing[static_cast<std::size_t>(p)] =
                    ClosingOpportunityHeuristic::score(roundScores, p, closerPlayer);
            }
        }
    }

    std::array<double, 4> teamSupport{};
    if (mode == GameMode::TwoVsTwo) {
        for (int p = 0; p < playerCount; ++p) {
            const auto team = RulesEngine::playersOnTeam(
                RulesEngine::teamIndexForPlayer(p));
            teamSupport[static_cast<std::size_t>(p)] = 0.25 *
                (mobility[static_cast<std::size_t>(team.first)] +
                 mobility[static_cast<std::size_t>(team.second)]);
        }
    }

    std::array<double, 4> pipControl{};
    if (!state.chain().isEmpty()) {
        for (int p = 0; p < playerCount; ++p) {
            pipControl[static_cast<std::size_t>(p)] = 0.5 * mobility[static_cast<std::size_t>(p)];
        }
    }

    for (int p = 0; p < playerCount; ++p) {
        double opponentMobility = 0.0;
        for (int q = 0; q < playerCount; ++q) {
            if (q != p) opponentMobility += mobility[static_cast<std::size_t>(q)];
        }

        double winThreat = 0.0;
        if (mode == GameMode::TwoVsTwo) {
            const auto myTeam = RulesEngine::playersOnTeam(
                RulesEngine::teamIndexForPlayer(p));
            const auto otherTeam = RulesEngine::playersOnTeam(
                1 - RulesEngine::teamIndexForPlayer(p));
            if (threats[static_cast<std::size_t>(myTeam.first)] ||
                threats[static_cast<std::size_t>(myTeam.second)]) {
                winThreat += 1000.0;
            }
            if (threats[static_cast<std::size_t>(otherTeam.first)] ||
                threats[static_cast<std::size_t>(otherTeam.second)]) {
                winThreat -= 1000.0;
            }
        } else {
            if (threats[static_cast<std::size_t>(p)]) winThreat += 1000.0;
            for (int q = 0; q < playerCount; ++q) {
                if (q != p && threats[static_cast<std::size_t>(q)]) winThreat -= 1000.0;
            }
        }

        double tempo = 0.0;
        if (mode == GameMode::TwoVsTwo) {
            if (RulesEngine::teamIndexForPlayer(state.currentPlayerIndex()) ==
                RulesEngine::teamIndexForPlayer(p)) {
                tempo = 1.0;
            }
        } else if (state.currentPlayerIndex() == p) {
            tempo = 1.0;
        }

        const double expectedValue = -static_cast<double>(handValues[static_cast<std::size_t>(p)]);
        result.totals[static_cast<std::size_t>(p)] =
            w.mobility * mobility[static_cast<std::size_t>(p)]
            + w.blocking * -opponentMobility
            + w.expectedValue * expectedValue
            + w.closingOpportunity * closing[static_cast<std::size_t>(p)]
            + w.winThreat * winThreat
            + w.pipControl * pipControl[static_cast<std::size_t>(p)]
            + w.tempo * tempo
            + w.teamSupport * teamSupport[static_cast<std::size_t>(p)];
    }
    return result;
}

EvaluationTotals EvaluationEngine::evaluateAll(GameMode mode,
                                               const GameState& state,
                                               const EvaluationWeights& weights,
                                               const EvaluationWeights* positionalWeights) {
    return evaluateAllImpl(mode, state, weights, std::nullopt, positionalWeights);
}

EvaluationTotals EvaluationEngine::evaluateAllWithClosed(
    GameMode mode,
    const GameState& state,
    bool positionClosed,
    const EvaluationWeights& weights,
    const EvaluationWeights* positionalWeights) {
    return evaluateAllImpl(mode, state, weights, positionClosed, positionalWeights);
}

} // namespace isolyn
