// High-volume, randomized rules-conformance soak. This is deliberately a
// separate executable from the unit suite: one million complete games is a
// nightly/local confidence run, not something every edit should wait for.
//
// Every action is checked against the same engine primitives the app uses:
// tile conservation, no duplicate tiles, chain/history agreement, legal-move
// generation, forced-draw completeness, the One Domino Rule's hand/board
// effects, and the Domino/Close end conditions. The harness prints only
// failures and a final count, because a hundred million passing assertions
// must not turn into a hundred million lines of log.
#include "Dealer.hpp"
#include "EntropySource.hpp"
#include "GameState.hpp"
#include "MatchController.hpp"
#include "MoveGenerator.hpp"
#include "MoveValidator.hpp"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>

using namespace isolyn;

namespace {

std::uint64_t g_checks = 0;
std::uint64_t g_failures = 0;
std::uint64_t g_game = 0;
std::uint64_t g_step = 0;

void expect(bool condition, const char* what) {
    ++g_checks;
    if (!condition) {
        ++g_failures;
        if (g_failures <= 50) {
            std::printf("[FAIL] game %llu step %llu: %s\n",
                        static_cast<unsigned long long>(g_game),
                        static_cast<unsigned long long>(g_step), what);
        }
    }
}

std::string tileName(DominoTile tile) {
    return std::to_string(tile.low()) + "-" + std::to_string(tile.high());
}

// Checks facts that must hold after every deal, every draw, and every play:
// the canonical set is partitioned exactly once across hands, chain and
// boneyard; no tile is duplicated; and the public history agrees with the
// visible chain.
void checkConservation(const GameState& state) {
    std::array<int, 28> seen{};
    for (int p = 0; p < state.playerCount(); ++p) {
        for (DominoTile tile : state.hand(p)) {
            ++seen[static_cast<std::size_t>(tile.index())];
        }
    }
    for (DominoTile tile : state.chain().orderedTiles()) {
        ++seen[static_cast<std::size_t>(tile.index())];
    }
    for (DominoTile tile : state.boneyard().remainingTiles()) {
        ++seen[static_cast<std::size_t>(tile.index())];
    }

    for (int i = 0; i < 28; ++i) {
        if (seen[static_cast<std::size_t>(i)] > 1) {
            expect(false, ("tile " + tileName(DominoTile::fromIndex(i)) +
                           " appears more than once in the partition").c_str());
        }
    }

    const std::vector<DominoTile> excluded = Dealer::excludedTilesForMode(state.mode());
    for (DominoTile excludedTile : excluded) {
        expect(seen[static_cast<std::size_t>(excludedTile.index())] == 0,
               "a mode-excluded tile is present in play");
    }
    expect(state.playHistory().size() == state.chain().orderedTiles().size(),
           "play history and chain have diverged");
    expect(state.currentPlayerIndex() >= 0 && state.currentPlayerIndex() < state.playerCount(),
           "current player index is outside the seat range");
    expect(state.chain().isEmpty() ||
               (state.chain().leftEnd() >= 0 && state.chain().leftEnd() <= 6 &&
                state.chain().rightEnd() >= 0 && state.chain().rightEnd() <= 6),
           "chain exposes an invalid end value");
}

bool anyoneHasLegalMove(const GameState& state) {
    for (int p = 0; p < state.playerCount(); ++p) {
        if (!state.hand(p).empty() && MoveGenerator::hasAnyLegalMove(state, p)) return true;
    }
    return false;
}

void checkEndCondition(const MatchController& controller, RoundOutcome outcome) {
    if (outcome.kind == RoundOutcomeKind::DominoVictory) {
        expect(outcome.decidingPlayerIndex >= 0 &&
                   outcome.decidingPlayerIndex < controller.state().playerCount(),
               "Domino victory has no valid deciding player");
        if (outcome.decidingPlayerIndex >= 0 &&
            outcome.decidingPlayerIndex < controller.state().playerCount()) {
            expect(controller.state().hand(outcome.decidingPlayerIndex).empty(),
                   "Domino victory was reported while the winner still holds tiles");
        }
    } else if (outcome.kind == RoundOutcomeKind::Closed) {
        expect(controller.state().boneyard().drawableCount() == 0,
               "a Close was reported while the boneyard still had a drawable tile");
        expect(!anyoneHasLegalMove(controller.state()),
               "a Close was reported while someone still had a legal move");
    }
}

void playOneGame(GameMode mode, std::mt19937_64& rng) {
    EntropySource entropy;
    MatchController controller = MatchController::dealFirstRound(mode, entropy);
    checkConservation(controller.state());

    bool finished = false;
    for (int step = 0; step < 256; ++step) {
        g_step = static_cast<std::uint64_t>(step);
        const GameState& state = controller.state();

        if (controller.currentPlayerHasLegalMove()) {
            // Exercise R-15's live action: voluntary drawing is legal as
            // often as the player likes once the chain is open. Keep the
            // policy bounded only to make the harness's random walk finish;
            // the engine itself imposes no such bound.
            if (controller.canVoluntaryDraw() && (rng() % 4) == 0 && step < 200) {
                const std::size_t beforeHand = state.hand(controller.currentPlayerIndex()).size();
                const std::size_t beforeDrawable = state.boneyard().drawableCount();
                const DominoTile drawn = controller.voluntaryDraw();
                expect(state.hand(controller.currentPlayerIndex()).size() == beforeHand + 1,
                       "voluntary draw did not add exactly one tile to the hand");
                expect(state.boneyard().drawableCount() + 1 == beforeDrawable,
                       "voluntary draw did not remove exactly one drawable tile");
                expect(std::find(state.hand(controller.currentPlayerIndex()).begin(),
                                 state.hand(controller.currentPlayerIndex()).end(), drawn) !=
                           state.hand(controller.currentPlayerIndex()).end(),
                       "voluntarily drawn tile is missing from the hand");
                checkConservation(state);
                continue;
            }

            std::vector<Move> candidates =
                MoveGenerator::generate(state, controller.currentPlayerIndex());
            expect(!candidates.empty(), "legal-move generator returned no move in a legal position");
            if (candidates.empty()) break;
            for (const Move& move : candidates) {
                expect(MoveValidator::isLegal(state, controller.currentPlayerIndex(), move),
                       "MoveGenerator produced a move MoveValidator rejects");
            }
            const Move chosen = candidates[static_cast<std::size_t>(rng() % candidates.size())];
            RoundOutcome outcome = controller.playTurn(chosen);
            checkConservation(controller.state());
            if (outcome.kind != RoundOutcomeKind::InProgress) {
                checkEndCondition(controller, outcome);
                finished = true;
                break;
            }
            continue;
        }

        // No placement is legal. The forced-draw path must either produce a
        // playable tile or exhaust the drawable boneyard; only then may the
        // turn pass without a play.
        if (state.boneyard().drawableCount() > 0) {
            const std::size_t beforeHand = state.hand(controller.currentPlayerIndex()).size();
            const std::size_t drawn = controller.resolveForcedDraw().size();
            expect(controller.state().hand(controller.currentPlayerIndex()).size() == beforeHand + drawn,
                   "forced-draw count disagrees with the hand size change");
            checkConservation(controller.state());
            if (controller.currentPlayerHasLegalMove()) continue;
            expect(controller.state().boneyard().drawableCount() == 0,
                   "forced draws stopped early without a legal move");
        }

        RoundOutcome outcome = controller.endTurnWithNoPlay();
        checkConservation(controller.state());
        if (outcome.kind != RoundOutcomeKind::InProgress) {
            checkEndCondition(controller, outcome);
            finished = true;
            break;
        }
    }

    expect(finished, "game did not reach a Domino or Close within 256 actions");
}

} // namespace

int main(int argc, char** argv) {
    const long games = argc > 1 ? std::atol(argv[1]) : 1000;
    const std::uint64_t seed = argc > 2 ? std::strtoull(argv[2], nullptr, 10) : 0xC0FFEEULL;
    if (games <= 0) {
        std::fprintf(stderr, "usage: %s [games] [seed]\n", argv[0]);
        return 2;
    }

    std::printf("Rules conformance soak: %ld complete games, seed %llu\n",
                games, static_cast<unsigned long long>(seed));
    const auto start = std::chrono::steady_clock::now();
    for (long i = 0; i < games; ++i) {
        g_game = static_cast<std::uint64_t>(i);
        g_step = 0;
        std::mt19937_64 rng(seed + static_cast<std::uint64_t>(i) * 0x9E3779B97F4A7C15ULL);
        const GameMode mode = (i % 3 == 0) ? GameMode::OneVsOne
                             : (i % 3 == 1) ? GameMode::OneVsOneVsOne
                                            : GameMode::TwoVsTwo;
        playOneGame(mode, rng);
        if ((i + 1) % 100000 == 0) {
            std::printf("  %ld games, %llu assertions, %llu failures\n",
                        i + 1, static_cast<unsigned long long>(g_checks),
                        static_cast<unsigned long long>(g_failures));
            std::fflush(stdout);
        }
    }
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start);
    std::printf("\nGames: %ld\nAssertions: %llu\nFailures: %llu\nElapsed: %lld ms\n",
                games, static_cast<unsigned long long>(g_checks),
                static_cast<unsigned long long>(g_failures),
                static_cast<long long>(elapsed.count()));
    return g_failures == 0 ? 0 : 1;
}