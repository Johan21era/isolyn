#include "GameState.hpp"
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <vector>

namespace isolyn {

namespace {

constexpr std::uint64_t kFnvOffset = 1469598103934665603ULL;
constexpr std::uint64_t kFnvPrime = 1099511628211ULL;

void hashMix(std::uint64_t& hash, std::uint64_t value) noexcept {
    hash ^= value;
    hash *= kFnvPrime;
}

} // namespace

std::uint64_t GameState::transpositionKey(TranspositionKeyMode mode) const {
    std::uint64_t hash = kFnvOffset;

    hashMix(hash, static_cast<std::uint64_t>(m_mode));
    hashMix(hash, static_cast<std::uint64_t>(m_currentPlayerIndex));
    hashMix(hash, static_cast<std::uint64_t>(m_hands.size()));

    // A hand has no meaningful order (see the undoDrawTile comment in the
    // header), so sort canonical tile indices before hashing. Two states
    // that differ only by hand ordering are genuinely the same state and
    // should share a transposition-table entry.
    for (const auto& hand : m_hands) {
        // Hands are at most 28 tiles. Keep the canonical sort on the stack:
        // hash() runs once per search node, so a heap allocation per hand
        // was measurable overhead in the leaf-heavy search.
        std::array<int, DominoTile::kTileCount> indices{};
        const auto handSize = hand.size();
        for (std::size_t i = 0; i < handSize; ++i) indices[i] = hand[i].index();
        std::sort(indices.begin(), indices.begin() + static_cast<std::ptrdiff_t>(handSize));
        hashMix(hash, static_cast<std::uint64_t>(handSize));
        for (std::size_t i = 0; i < handSize; ++i) {
            hashMix(hash, static_cast<std::uint64_t>(indices[i]));
        }
    }

    const auto& chainTiles = m_chain.orderedTiles();
    hashMix(hash, static_cast<std::uint64_t>(chainTiles.size()));
    for (const auto& tile : chainTiles) hashMix(hash, static_cast<std::uint64_t>(tile.index()));
    if (m_chain.isEmpty()) {
        hashMix(hash, 0xFFFFFFFFULL);
    } else {
        hashMix(hash, static_cast<std::uint64_t>(m_chain.leftEnd()));
        hashMix(hash, static_cast<std::uint64_t>(m_chain.rightEnd()));
    }

    // Draw order matters: a future forced draw can expose different tiles.
    const auto& boneyard = m_boneyard.remainingTiles();
    hashMix(hash, static_cast<std::uint64_t>(boneyard.size()));
    for (const auto& tile : boneyard) hashMix(hash, static_cast<std::uint64_t>(tile.index()));

    if (mode == TranspositionKeyMode::FullHistory) {
        hashMix(hash, static_cast<std::uint64_t>(m_playHistory.size()));
        for (const auto& record : m_playHistory) {
            hashMix(hash, static_cast<std::uint64_t>(record.playerIndex));
            hashMix(hash, static_cast<std::uint64_t>(record.tile.index()));
        }
    } else {
        // Only the two facts RulesEngine::determineCloser reads. A state with
        // no plays yet and one whose first play is still pending both key as
        // "no last player", which is correct: neither has a closer.
        std::uint64_t lastPlayer = 0xFFFFFFFFULL;
        std::uint64_t lastNonDouble = 0xFFFFFFFFULL;
        for (auto it = m_playHistory.rbegin(); it != m_playHistory.rend(); ++it) {
            if (lastPlayer == 0xFFFFFFFFULL) {
                lastPlayer = static_cast<std::uint64_t>(it->playerIndex);
            }
            if (!it->tile.isDouble()) {
                lastNonDouble = static_cast<std::uint64_t>(it->playerIndex);
                break;
            }
        }
        hashMix(hash, lastPlayer);
        hashMix(hash, lastNonDouble);
    }

    return hash;
}

std::uint64_t GameState::hash() const {
    return transpositionKey(TranspositionKeyMode::FullHistory);
}

GameState::GameState(GameMode mode,
                      std::vector<std::vector<DominoTile>> hands,
                      std::vector<DominoTile> boneyardTiles,
                      Chain initialChain,
                      std::vector<PlayRecord> initialPlayHistory,
                      int initialCurrentPlayerIndex)
    : m_mode(mode), m_hands(std::move(hands)), m_chain(std::move(initialChain)),
      m_boneyard(std::move(boneyardTiles)), m_currentPlayerIndex(initialCurrentPlayerIndex),
      m_playHistory(std::move(initialPlayHistory)) {
    assert(m_currentPlayerIndex >= 0 && m_currentPlayerIndex < playerCount() &&
           "initialCurrentPlayerIndex must be a valid player index for the given hands");
}

const std::vector<DominoTile>& GameState::hand(int playerIndex) const {
    assert(playerIndex >= 0 && playerIndex < playerCount());
    return m_hands[static_cast<std::size_t>(playerIndex)];
}

void GameState::setCurrentPlayerIndex(int index) {
    assert(index >= 0 && index < playerCount());
    m_currentPlayerIndex = index;
}

GameState::PlacementKind GameState::playTile(int playerIndex, DominoTile tile, ChainSide side) {
    assert(playerIndex >= 0 && playerIndex < playerCount());
    auto& hand = m_hands[static_cast<std::size_t>(playerIndex)];
    auto it = std::find(hand.begin(), hand.end(), tile);
    assert(it != hand.end() && "tile must be in the player's hand");
    hand.erase(it);

    PlacementKind kind;
    if (m_chain.isEmpty()) {
        m_chain.placeOpening(tile);
        kind = PlacementKind::Opened;
    } else if (side == ChainSide::Left) {
        m_chain.placeLeft(tile);
        kind = PlacementKind::AttachedLeft;
    } else {
        m_chain.placeRight(tile);
        kind = PlacementKind::AttachedRight;
    }

    m_playHistory.push_back(PlayRecord{playerIndex, tile});
    return kind;
}

void GameState::undoPlayTile(int playerIndex, DominoTile tile, PlacementKind kind) {
    assert(playerIndex >= 0 && playerIndex < playerCount());
    assert(!m_playHistory.empty());
    assert(m_playHistory.back().playerIndex == playerIndex && m_playHistory.back().tile == tile &&
           "undoPlayTile must reverse the most recent playTile call, with matching arguments");
    m_playHistory.pop_back();

    switch (kind) {
        case PlacementKind::Opened: m_chain.undoOpening(); break;
        case PlacementKind::AttachedLeft: m_chain.undoLeft(); break;
        case PlacementKind::AttachedRight: m_chain.undoRight(); break;
    }

    m_hands[static_cast<std::size_t>(playerIndex)].push_back(tile);
}

DominoTile GameState::drawTile(int playerIndex) {
    assert(playerIndex >= 0 && playerIndex < playerCount());
    DominoTile tile = m_boneyard.drawNext();
    m_hands[static_cast<std::size_t>(playerIndex)].push_back(tile);
    return tile;
}

std::optional<DominoTile> GameState::enforceOneDominoRule() {
    if (m_boneyard.drawableCount() == 0) return std::nullopt;
    // R-18 is a two-hand rule. R-22's survivor phase is a 1v1 played in a
    // three-seat state, where exactly two hands are non-empty; counting
    // non-empty hands keeps the rule correct there without teaching every
    // caller a separate mode.
    std::vector<int> active;
    active.reserve(m_hands.size());
    for (int p = 0; p < playerCount(); ++p) {
        if (!m_hands[static_cast<std::size_t>(p)].empty()) active.push_back(p);
    }
    if (active.size() != 2) return std::nullopt;
    if (m_hands[static_cast<std::size_t>(active[0])].size() != 1 ||
        m_hands[static_cast<std::size_t>(active[1])].size() != 1) return std::nullopt;
    if (m_currentPlayerIndex != active[0] && m_currentPlayerIndex != active[1]) return std::nullopt;
    return drawTile(m_currentPlayerIndex);
}

std::optional<std::array<DominoTile, 2>> GameState::privateLockedPair(int playerIndex) const {
    // R-17 is a two-player rule. R-22's survivor phase is exactly that, 1v1,
    // even though the seat array still has three entries; an eliminated
    // seat's empty hand is not a third live hand.
    if (playerIndex < 0 || playerIndex >= playerCount()) return std::nullopt;
    if (m_hands[static_cast<std::size_t>(playerIndex)].size() != 1) return std::nullopt;
    if (m_boneyard.drawableCount() != 0) return std::nullopt;
    int activeCount = 0;
    for (const auto& hand : m_hands) {
        if (!hand.empty()) ++activeCount;
    }
    if (activeCount != 2) return std::nullopt;
    const std::vector<DominoTile> locked = m_boneyard.lockedTiles();
    if (locked.size() != 2) return std::nullopt;
    return std::array<DominoTile, 2>{locked[0], locked[1]};
}

void GameState::undoDrawTile(int playerIndex, DominoTile tile) {
    assert(playerIndex >= 0 && playerIndex < playerCount());
    auto& hand = m_hands[static_cast<std::size_t>(playerIndex)];
    // Deliberately NOT hand.back()/pop_back() -- see the header comment
    // on why this must be order-independent, the same way playTile's own
    // removal already is. Locates and removes `tile` from wherever it
    // currently sits in the hand.
    auto it = std::find(hand.begin(), hand.end(), tile);
    assert(it != hand.end() &&
           "undoDrawTile must reverse the most recent drawTile call for this player, with a matching tile");
    hand.erase(it);
    m_boneyard.undoDraw(tile);
}

} // namespace isolyn
