#pragma once
#include <vector>
#include "DominoTile.hpp"
#include "EntropySource.hpp"
#include "GameMode.hpp"

namespace isolyn {

struct DealResult {
    std::vector<std::vector<DominoTile>> hands;
    std::vector<DominoTile> boneyard;
};

// There is no dealer role in Albanian Dominoes -- players freely choose
// their own starting dominoes from a shuffled, face-down pile (Rules Spec
// Sec. 3). A genuine shuffle followed by handing out the first N tiles to
// each player is the exact digital equivalent of that: face-down free
// choice from a shuffled pile carries the same distribution as being
// handed the top N tiles of that same shuffle. This class owns that
// equivalence, per-mode hand sizing, the 1v1v1 zero-zero removal, and
// Misdeal detection/reshuffling (Rules Spec Sec. 12).
class Dealer {
public:
    // Deals a fresh round for the given mode using genuine entropy.
    // Internally reshuffles and re-deals, as many times as needed, until
    // the result is not a Misdeal -- so the DealResult returned is always
    // a legally dealt starting position; the caller never has to validate
    // it itself.
    static DealResult deal(GameMode mode, EntropySource& entropy);

    // Exposed separately from deal() so RulesEngine, tests, and (later)
    // the vision-reconstructed-position path can check Misdeal conditions
    // against a given set of hands without forcing a fresh shuffle.
    static bool isMisdeal(GameMode mode, const std::vector<std::vector<DominoTile>>& hands);

    static int playerCountForMode(GameMode mode);
    static int handSizeForMode(GameMode mode);

    // The tiles permanently removed from this mode's play entirely --
    // never dealt to anyone, never in the boneyard, never seen by
    // anyone -- as opposed to merely hidden. Currently only the 0-0
    // removal for OneVsOneVsOne (Rules Spec Sec. 3). Single source of
    // truth for that rule: deal() below uses this directly, and so does
    // ProbabilityEngine::constructFromGameState, which needs to know
    // these tiles are excluded from its own "every one of the 28
    // canonical tiles is somewhere" accounting -- see BeliefState's
    // excludedTiles constructor parameter for exactly why that matters.
    static std::vector<DominoTile> excludedTilesForMode(GameMode mode);
};

} // namespace isolyn
