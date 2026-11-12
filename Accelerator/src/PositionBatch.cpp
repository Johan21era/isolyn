#include "IsolynPositionBatch.hpp"

#include "RulesEngine.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace isolyn::accelerator {
namespace {

// One bit per tile carrying each face; the same layout as the Metal shader.
constexpr std::array<std::uint32_t, 7> kFaceMasks = {
    0x0020844bu, 0x00410896u, 0x00821138u, 0x010423c0u,
    0x02087c00u, 0x041f8000u, 0x0fe00000u,
};

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

        // Reuse the masks instead of rescanning every hand through
        // MoveGenerator::isPositionClosed. A hand is stuck when none of its
        // tiles carries either chain end; an empty chain accepts every tile.
        // Match isPositionClosed's early exit: a drawable boneyard means the
        // position cannot be closed, so the hand masks need not be checked.
        bool positionClosed = false;
        if (state.boneyard().drawableCount() == 0) {
            bool allPlayersStuck = true;
            if (state.chain().isEmpty()) {
                for (std::size_t player = 0; player < playerCount; ++player) {
                    if (row.handMasks[player] != 0) {
                        allPlayersStuck = false;
                        break;
                    }
                }
            } else {
                const std::uint32_t playable =
                    kFaceMasks[static_cast<std::size_t>(row.leftEnd)] |
                    kFaceMasks[static_cast<std::size_t>(row.rightEnd)];
                for (std::size_t player = 0; player < playerCount; ++player) {
                    if ((row.handMasks[player] & playable) != 0) {
                        allPlayersStuck = false;
                        break;
                    }
                }
            }
            positionClosed = allPlayersStuck;
        }
        row.closed = positionClosed ? 1u : 0u;

        if (row.closed != 0) {
            if (!state.playHistory().empty()) {
                row.closerPlayer = static_cast<std::uint32_t>(
                    RulesEngine::determineCloser(mode, state.playHistory()));
            }

            std::array<int, 4> handValues{};
            for (std::size_t player = 0; player < playerCount; ++player) {
                int value = 0;
                for (const DominoTile& tile : state.hand(static_cast<int>(player))) {
                    value += tile.value();
                }
                handValues[player] = value;
            }

            std::vector<int> participantValues;
            if (mode == GameMode::TwoVsTwo) {
                const auto team0 = RulesEngine::playersOnTeam(0);
                const auto team1 = RulesEngine::playersOnTeam(1);
                participantValues = {
                    RulesEngine::combineTeamValue(handValues[static_cast<std::size_t>(team0.first)],
                                                  handValues[static_cast<std::size_t>(team0.second)]),
                    RulesEngine::combineTeamValue(handValues[static_cast<std::size_t>(team1.first)],
                                                  handValues[static_cast<std::size_t>(team1.second)]),
                };
            } else {
                for (int player = 0; player < static_cast<int>(playerCount); ++player) {
                    participantValues.push_back(handValues[static_cast<std::size_t>(player)]);
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
