#include "BeliefState.hpp"
#include "Dealer.hpp"
#include "EntropySource.hpp"
#include "MatchController.hpp"
#include "ProbabilityEngine.hpp"
#include "TestHarness.hpp"
#include <cmath>
#include <string>

using namespace isolyn;
using namespace isolyn::test;

namespace {
bool approxEqual(double a, double b, double epsilon = 1e-9) {
    return std::abs(a - b) < epsilon;
}
} // namespace

int main() {
    section("BeliefState: initial distribution is exactly proportional to each location's pool share");
    {
        std::vector<DominoTile> myKnown;
        for (int i = 0; i < 7; ++i) myKnown.push_back(DominoTile::fromIndex(i));
        std::vector<DominoTile> otherKnown;
        for (int i = 7; i < 10; ++i) otherKnown.push_back(DominoTile::fromIndex(i));
        // Indices 10-27 (18 tiles) remain unseen: opponent=7, boneyard=11.
        std::map<int, int> locationCounts = { {1, 7}, {BeliefState::kBoneyardLocation, 11} };
        BeliefState belief(myKnown, otherKnown, locationCounts);

        DominoTile unseenTile = DominoTile::fromIndex(15);
        check(belief.isTracked(unseenTile), "an unseen tile (not in either known list) is tracked");
        check(approxEqual(belief.probability(unseenTile, 1), 7.0 / 18.0), "opponent share matches pool proportion exactly");
        check(approxEqual(belief.probability(unseenTile, BeliefState::kBoneyardLocation), 11.0 / 18.0),
              "boneyard share matches pool proportion exactly");

        DominoTile myTile = DominoTile::fromIndex(3);
        check(!belief.isTracked(myTile), "a tile in my own known hand is never tracked");
        check(belief.probability(myTile, 1) == 0.0, "an untracked tile has zero probability everywhere");

        DominoTile playedTile = DominoTile::fromIndex(8);
        check(!belief.isTracked(playedTile), "a tile already known to be elsewhere (e.g. played) is also never tracked");
    }

    section("BeliefState: totalProbabilityMass exactly matches known counts at construction");
    {
        std::vector<DominoTile> myKnown;
        for (int i = 0; i < 7; ++i) myKnown.push_back(DominoTile::fromIndex(i));
        std::vector<DominoTile> otherKnown;
        for (int i = 7; i < 10; ++i) otherKnown.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 7}, {BeliefState::kBoneyardLocation, 11} };
        BeliefState belief(myKnown, otherKnown, locationCounts);

        check(approxEqual(belief.totalProbabilityMass(1), 7.0), "opponent's aggregate mass exactly equals their known hand size");
        check(approxEqual(belief.totalProbabilityMass(BeliefState::kBoneyardLocation), 11.0),
              "boneyard's aggregate mass exactly equals its known size");
    }

    section("BeliefState: applyOpponentDraw is exact -- verified against the hand-derived formula (simple case)");
    {
        // 26 known tiles (0-25), leaving exactly 2 unseen (26, 27), split
        // opponent=1, boneyard=1.
        std::vector<DominoTile> myKnown;
        for (int i = 0; i < 26; ++i) myKnown.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 1}, {BeliefState::kBoneyardLocation, 1} };
        BeliefState belief(myKnown, {}, locationCounts);

        DominoTile a = DominoTile::fromIndex(26);
        DominoTile b = DominoTile::fromIndex(27);
        check(approxEqual(belief.probability(a, 1), 0.5) && approxEqual(belief.probability(a, BeliefState::kBoneyardLocation), 0.5),
              "sanity check: both unseen tiles start 50/50 between the single opponent and the boneyard");

        belief.applyOpponentDraw(1);
        // B = 1 before the draw. moved = p(t,boneyard)/B = 0.5/1 = 0.5 for each tile.
        // new p(t,opp) = 0.5+0.5 = 1.0. new p(t,boneyard) = 0.5-0.5 = 0.0.
        check(approxEqual(belief.probability(a, 1), 1.0), "with one boneyard-share and one opponent, all mass shifts to them");
        check(approxEqual(belief.probability(a, BeliefState::kBoneyardLocation), 0.0), "boneyard share for this tile drops to exactly zero");
        check(approxEqual(belief.probability(b, 1), 1.0), "the same exact shift applies to every tracked tile, not just one");

        check(approxEqual(belief.totalProbabilityMass(1), 2.0), "aggregate opponent mass grew by exactly 1, matching their new hand size");
        check(approxEqual(belief.totalProbabilityMass(BeliefState::kBoneyardLocation), 0.0), "aggregate boneyard mass shrank by exactly 1, to zero");
    }

    section("BeliefState: applyOpponentDraw with a genuinely mixed three-location distribution");
    {
        // 24 known (0-23), 4 unseen (24-27), split opponent1=1, opponent2=1, boneyard=2.
        std::vector<DominoTile> myKnown;
        for (int i = 0; i < 24; ++i) myKnown.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 1}, {2, 1}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(myKnown, {}, locationCounts);

        DominoTile t = DominoTile::fromIndex(24);
        check(approxEqual(belief.probability(t, 1), 0.25) && approxEqual(belief.probability(t, 2), 0.25)
                  && approxEqual(belief.probability(t, BeliefState::kBoneyardLocation), 0.5),
              "sanity check: 1/4, 1/4, 1/2 split across opponent1, opponent2, boneyard");

        belief.applyOpponentDraw(1);
        // B = 2 before the draw. moved = 0.5/2 = 0.25 for each tile.
        // new p(t,opp1) = 0.25+0.25 = 0.5. new p(t,boneyard) = 0.5-0.25 = 0.25. p(t,opp2) untouched at 0.25.
        check(approxEqual(belief.probability(t, 1), 0.5), "opponent1's share increases by exactly what moved from the boneyard");
        check(approxEqual(belief.probability(t, BeliefState::kBoneyardLocation), 0.25), "boneyard share decreases by the same amount");
        check(approxEqual(belief.probability(t, 2), 0.25), "opponent2's share is completely untouched by opponent1's draw");
        check(approxEqual(belief.probability(t, 1) + belief.probability(t, 2) + belief.probability(t, BeliefState::kBoneyardLocation), 1.0),
              "this tile's full distribution still sums to exactly 1 after the update");
    }

    section("BeliefState: applyOpponentDraw with an EMPTY boneyard is a defined no-op -- never NaN (FIX-17 / audit F-11)");
    {
        // All unseen mass sits with the opponent; locationCounts has NO
        // boneyard entry at all, so the boneyard's aggregate mass is
        // exactly 0. The class used to assert this precondition away in
        // debug builds and divide by the zero mass in release ones;
        // since FIX-17 the call is a total function: a documented,
        // harmless no-op in EVERY build configuration. This test pins
        // that contract (it cannot be red-first for the exact-zero case
        // -- the old code already no-op'd there safely; what the guard
        // adds is protection against tiny-negative FP-drift mass, where
        // share/(negative-epsilon) would silently corrupt beliefs).
        std::vector<DominoTile> myKnown;
        for (int i = 0; i < 26; ++i) myKnown.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 2} };
        BeliefState belief(myKnown, {}, locationCounts);

        check(approxEqual(belief.totalProbabilityMass(BeliefState::kBoneyardLocation), 0.0),
              "precondition pinned: boneyard aggregate mass is exactly zero");

        belief.applyOpponentDraw(1);   // must not abort, NaN, or move any mass

        DominoTile t = DominoTile::fromIndex(26);
        double pOpp = belief.probability(t, 1);
        double pBon = belief.probability(t, BeliefState::kBoneyardLocation);
        check(std::isfinite(pOpp) && std::isfinite(pBon),
              "per-tile probabilities remain finite after an empty-boneyard draw (no divide-by-zero propagation)");
        check(approxEqual(pOpp, 1.0), "opponent share unchanged by the empty-boneyard draw");
        check(pBon == 0.0, "boneyard share remains exactly zero");
        check(approxEqual(pOpp + pBon, 1.0), "per-tile normalization preserved through the no-op");
        check(approxEqual(belief.totalProbabilityMass(1), 2.0),
              "aggregate opponent mass untouched by the empty-boneyard draw");
    }

    section("BeliefState: markTileKnown removes tracking; remaining mass moves in the documented, approximate way");
    {
        // 24 known (0-23), 4 unseen (24-27), split opponent=2, boneyard=2.
        std::vector<DominoTile> myKnown;
        for (int i = 0; i < 24; ++i) myKnown.push_back(DominoTile::fromIndex(i));
        std::map<int, int> locationCounts = { {1, 2}, {BeliefState::kBoneyardLocation, 2} };
        BeliefState belief(myKnown, {}, locationCounts);

        DominoTile revealed = DominoTile::fromIndex(24);
        check(approxEqual(belief.probability(revealed, 1), 0.5), "sanity check: 50/50 before the reveal");

        belief.markTileKnown(revealed, 1, 1); // opponent had 2, played 1, now has 1
        check(!belief.isTracked(revealed), "the revealed tile is no longer tracked");
        check(belief.probability(revealed, 1) == 0.0, "an untracked tile has zero probability everywhere, including its own revealed location");

        // Hand-derived expected values for the three remaining tiles
        // (25, 26, 27), each starting at p(opp)=0.5, p(boneyard)=0.5:
        // remainingRawSum = 3*0.5 = 1.5. scale = newCount/remainingRawSum = 1/1.5 = 2/3.
        // new raw opp share per tile = 0.5*(2/3) = 1/3. boneyard raw share unchanged at 0.5.
        // new raw total per tile = 1/3+0.5 = 5/6. Normalized: p(opp) = (1/3)/(5/6) = 0.4, p(boneyard) = 0.5/(5/6) = 0.6.
        DominoTile other = DominoTile::fromIndex(25);
        check(approxEqual(belief.probability(other, 1), 0.4), "remaining tiles' opponent share drops to the hand-derived 0.4");
        check(approxEqual(belief.probability(other, BeliefState::kBoneyardLocation), 0.6), "and their boneyard share correspondingly rises to 0.6");
        check(approxEqual(belief.probability(other, 1) + belief.probability(other, BeliefState::kBoneyardLocation), 1.0),
              "per-tile normalization still holds exactly at query time, even though this rebalancing is a documented approximation");

        // Documented approximation, not exact: aggregate opponent mass is
        // close to but not exactly the new count of 1 (3 tiles * 0.4 = 1.2).
        check(approxEqual(belief.totalProbabilityMass(1), 1.2),
              "aggregate mass lands close to, but -- as documented -- not exactly at, the new count of 1");
    }

    section("BeliefState: excludedTiles removes a tile from tracking without needing a locationCounts entry for it");
    {
        // A real, reproduced bug, not a hypothetical: constructing this
        // exact shape (one tile neither known/identified NOR present in
        // any locationCounts) used to trip the trackedCount == totalUnseen
        // assertion below, every single time, for every OneVsOneVsOne
        // game -- see Dealer::excludedTilesForMode and
        // ProbabilityEngine::constructFromGameState.
        std::vector<DominoTile> myKnown = {DominoTile(1, 1)};
        std::vector<DominoTile> otherKnown = {DominoTile(2, 2)};
        std::vector<DominoTile> excluded = {DominoTile(0, 0)};
        // 28 total - 1 known - 1 identified - 1 excluded = 25 genuinely
        // trackable tiles; put them all in one location so the sum is
        // trivially checkable.
        std::map<int, int> locationCounts = {{1, 25}};

        BeliefState belief(myKnown, otherKnown, locationCounts, excluded);
        check(!belief.isTracked(DominoTile(0, 0)), "the excluded tile is not tracked");
        check(!belief.isTracked(DominoTile(1, 1)), "the believer's own known tile is not tracked (unchanged behavior)");
        check(!belief.isTracked(DominoTile(2, 2)), "the already-identified tile is not tracked (unchanged behavior)");
        check(belief.isTracked(DominoTile(3, 3)), "an ordinary unseen tile is still tracked");
        check(approxEqual(belief.probability(DominoTile(3, 3), 1), 1.0),
              "with only one location and no excluded-tile miscount, every tracked tile's full probability mass lands there");
    }

    section("BeliefState: real end-to-end OneVsOneVsOne construction via ProbabilityEngine never asserts");
    {
        // The actual bug reproduction, at the level it was originally
        // found: a genuinely dealt 3-player position, not a hand-crafted
        // one -- see ProbabilityEngineTests.cpp for more of these; this
        // one specifically documents WHY 1v1v1 needed excludedTiles at
        // all, right next to BeliefState's own constructor tests.
        for (int trial = 0; trial < 5; ++trial) {
            EntropySource entropy;
            MatchController controller = MatchController::dealFirstRound(GameMode::OneVsOneVsOne, entropy);
            const GameState& state = controller.state();
            for (int believer = 0; believer < state.playerCount(); ++believer) {
                BeliefState belief = ProbabilityEngine::constructFromGameState(state, believer);
                check(!belief.isTracked(DominoTile(0, 0)),
                      "0-0 is never tracked for a OneVsOneVsOne belief state, believer " + std::to_string(believer));
            }
        }
    }

    if (failureCount() == 0) {
        std::cout << "\nBeliefState: all checks passed\n";
        return 0;
    }
    std::cout << "\nBeliefState: " << failureCount() << " check(s) failed\n";
    return 1;
}
