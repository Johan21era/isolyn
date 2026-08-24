#include "Dealer.hpp"
#include "DominoSet.hpp"
#include <algorithm>
#include <cassert>

namespace isolyn {

int Dealer::playerCountForMode(GameMode mode) {
    switch (mode) {
        case GameMode::OneVsOne: return 2;
        case GameMode::OneVsOneVsOne: return 3;
        case GameMode::TwoVsTwo: return 4;
    }
    return 0; // unreachable -- every GameMode enumerator is handled above
}

int Dealer::handSizeForMode(GameMode mode) {
    switch (mode) {
        case GameMode::OneVsOne: return 7;
        case GameMode::OneVsOneVsOne: return 9;
        case GameMode::TwoVsTwo: return 7;
    }
    return 0; // unreachable -- every GameMode enumerator is handled above
}

std::vector<DominoTile> Dealer::excludedTilesForMode(GameMode mode) {
    if (mode == GameMode::OneVsOneVsOne) {
        // "The 0-0 domino is removed before play begins." Single source
        // of truth for this rule -- deal() below and
        // ProbabilityEngine::constructFromGameState both call this
        // rather than each hard-coding DominoTile(0, 0) separately.
        return {DominoTile(0, 0)};
    }
    return {};
}

bool Dealer::isMisdeal(GameMode mode, const std::vector<std::vector<DominoTile>>& hands) {
    // Rules Spec Sec. 12 states this trigger as "a player begins with 8
    // dominoes" -- literally true only for the 7-tile modes (1v1, 2v2),
    // where 8 is one more than dealt. Read literally it wouldn't even
    // apply to 1v1v1's 9-tile hands, where 8 would be one *short*, not
    // over. Implemented here as the more general, mode-relative reading
    // -- any hand whose size doesn't match what the mode calls for is a
    // Misdeal -- since that's the invariant "8 in a 7-tile game" is
    // clearly gesturing at, and it's the check Dealer needs regardless (a
    // fully digital deal never actually miscounts, so this mainly matters
    // as a defensive check against externally-constructed positions --
    // e.g. from the vision pipeline later).
    const int expectedHandSize = handSizeForMode(mode);
    for (const auto& hand : hands) {
        if (static_cast<int>(hand.size()) != expectedHandSize) {
            return true;
        }
    }

    // "In 1 vs 1, a player begins with five or more doubles" -- explicit,
    // unambiguous, 1v1-only.
    if (mode == GameMode::OneVsOne) {
        for (const auto& hand : hands) {
            int doubleCount = 0;
            for (const auto& tile : hand) {
                if (tile.isDouble()) ++doubleCount;
            }
            if (doubleCount >= 5) return true;
        }
    }

    return false;
}

DealResult Dealer::deal(GameMode mode, EntropySource& entropy) {
    const int playerCount = playerCountForMode(mode);
    const int handSize = handSizeForMode(mode);

    DealResult result;
    do {
        const auto& all = DominoSet::allTiles();
        std::vector<DominoTile> pool(all.begin(), all.end());

        // Removed from the pool here, before shuffling, so every player
        // draws from a clean pool with equal odds over what remains --
        // rather than being dealt into a hand and then taken back out
        // again, which would raise its own question (does the affected
        // player then draw a replacement to stay at the mode's hand
        // size?). Pre-removal is the simpler reading and the one
        // implemented. See excludedTilesForMode's own comment for which
        // tiles this is, per mode, and why ProbabilityEngine needs the
        // exact same list.
        for (const DominoTile& excluded : excludedTilesForMode(mode)) {
            pool.erase(std::remove(pool.begin(), pool.end(), excluded), pool.end());
        }

        entropy.shuffle(pool);

        result.hands.assign(static_cast<std::size_t>(playerCount), {});
        auto cursor = pool.begin();
        for (int player = 0; player < playerCount; ++player) {
            result.hands[static_cast<std::size_t>(player)].assign(cursor, cursor + handSize);
            cursor += handSize;
        }
        result.boneyard.assign(cursor, pool.end());
    } while (isMisdeal(mode, result.hands));

    return result;
}

} // namespace isolyn
