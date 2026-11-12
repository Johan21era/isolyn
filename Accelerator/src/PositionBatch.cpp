#include "IsolynPositionBatch.hpp"

#include "MoveGenerator.hpp"
#include "RulesEngine.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace isolyn::accelerator {
namespace {

int handValue(const GameState& state, int player) {
    int total = 0;
    for (const DominoTile& tile : state.hand(player)) total += tile.value();
    return total;
}

} // namespace

PositionBatch encodePositionBatch(GameMode mode,
                                  const std::vector<GameState>& positions) {
    PositionBatch batch;
    if (positions.empty()) return batch;

    const std::size_t playerCount = static_cast<std::size_t>(positions.front().playerCount());
    if (playerCount < 2 || playerCount > 4) return batch;
    for (const GameState& state : positions) {
        if (static_cast<std::size_t>(state.playerCount()) != playerCount) return {};
    }

    batch.playerCount = playerCount;
    batch.rows.resize(positions.size());

    for (std::size_t index = 0; index < positions.size(); ++index) {
        const GameState& state = positions[index];
        PositionRow& row = batch.rows[index];

        for (std::size_t player = 0; player < playerCount; ++player) {
            std::uint32_t mask = 0;
            for (const DominoTile& tile : state.hand(static_cast<int>(player))) {
                mask |= 1u << static_cast<unsigned>(tile.index());
            }
            row.handMasks[player] = mask;
        }

        row.leftEnd = state.chain().isEmpty() ? -1 : state.chain().leftEnd();
        row.rightEnd = state.chain().isEmpty() ? -1 : state.chain().rightEnd();
        row.currentPlayer = static_cast<std::uint32_t>(state.currentPlayerIndex());
        row.playerCount = static_cast<std::uint32_t>(playerCount);
        row.mode = static_cast<std::uint32_t>(mode);
        row.closed = MoveGenerator::isPositionClosed(state) ? 1u : 0u;

        if (row.closed != 0) {
            if (!state.playHistory().empty()) {
                row.closerPlayer = static_cast<std::uint32_t>(
                    RulesEngine::determineCloser(mode, state.playHistory()));
            }

            std::vector<int> participantValues;
            if (mode == GameMode::TwoVsTwo) {
                const auto team0 = RulesEngine::playersOnTeam(0);
                const auto team1 = RulesEngine::playersOnTeam(1);
                participantValues = {
                    RulesEngine::combineTeamValue(handValue(state, team0.first),
                                                  handValue(state, team0.second)),
                    RulesEngine::combineTeamValue(handValue(state, team1.first),
                                                  handValue(state, team1.second)),
                };
            } else {
                for (int player = 0; player < static_cast<int>(playerCount); ++player) {
                    participantValues.push_back(handValue(state, player));
                }
            }

            const std::vector<int> scores = RulesEngine::computeRoundScores(participantValues);
            for (std::size_t i = 0; i < scores.size() && i < 4; ++i) {
                row.roundScores[i] = static_cast<std::uint32_t>(scores[i]);
            }
        }
    }

    return batch;
}

} // namespace isolyn::accelerator
