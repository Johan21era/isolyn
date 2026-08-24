#include "SearchEngine.hpp"
#include "ProbabilityEngine.hpp"
#include "Dealer.hpp"
#include "EntropySource.hpp"
#include "MoveGenerator.hpp"
#include "TestHarness.hpp"
#include <atomic>
#include <chrono>
#include <thread>

using namespace isolyn;
using namespace isolyn::test;

namespace {

// A genuine, realistically-dealt 1v1 position (not hand-crafted padding)
// -- exercises real hidden information via ProbabilityEngine, same as an
// actual in-game analysis request would.
GameState freshOneVsOnePosition() {
    EntropySource entropy;
    DealResult dealt = Dealer::deal(GameMode::OneVsOne, entropy);
    return GameState(GameMode::OneVsOne, dealt.hands, dealt.boneyard);
}

} // namespace

int main() {
    section("SearchEngine cancellation: nullptr (the default) reproduces prior behavior exactly");
    {
        // Identical scenario to SearchEngineTests.cpp's first case --
        // re-run here specifically to confirm completed/samplesCompleted
        // behave correctly on the ordinary, non-cancelled path, not just
        // that the old assertions on .move still hold.
        std::vector<DominoTile> padding;
        for (int i = 0; i < DominoTile::kTileCount; ++i) {
            DominoTile t = DominoTile::fromIndex(i);
            if (t == DominoTile(4, 6) || t == DominoTile(4, 1) || t == DominoTile(6, 6)) continue;
            padding.push_back(t);
        }
        std::deque<DominoTile> chainTiles(padding.begin(), padding.end());
        Chain chain = Chain::fromKnownState(chainTiles, 4, 4);
        std::vector<std::vector<DominoTile>> hands = {
            { DominoTile(4, 6), DominoTile(4, 1) },
            { DominoTile(6, 6) },
        };
        GameState state(GameMode::OneVsOne, hands, {}, chain, { PlayRecord{1, DominoTile(4, 4)} }, 0);
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, 0);
        std::mt19937_64 rng(2024);
        SearchEngine::Config config;
        config.maxDepthPlies = 4;
        config.determinizationCount = 1;

        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng, nullptr);

        check(decision.move.tile == DominoTile(4, 1), "chosen move is unchanged from the pre-cancellation baseline");
        check(decision.completed == true, "completed is true when cancelRequested is nullptr");
        check(decision.samplesCompleted == config.determinizationCount,
              "samplesCompleted equals the full configured determinizationCount when never cancelled");
    }

    section("SearchEngine cancellation: a non-null flag that is never set behaves identically to nullptr");
    {
        GameState state = freshOneVsOnePosition();
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, state.currentPlayerIndex());
        std::mt19937_64 rng(7);
        SearchEngine::Config config;
        config.maxDepthPlies = 2;
        config.determinizationCount = 3;
        std::atomic<bool> neverCancelled{false};

        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng, &neverCancelled);

        check(decision.completed == true, "completed is true when the flag exists but is never set");
        check(decision.samplesCompleted == config.determinizationCount, "all samples ran when the flag is never set");
    }

    section("SearchEngine cancellation: flag already set before the call returns immediately, honestly, with no crash");
    {
        GameState state = freshOneVsOnePosition();
        int player = state.currentPlayerIndex();
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, player);
        std::mt19937_64 rng(11);
        SearchEngine::Config config;
        config.maxDepthPlies = 4;
        config.determinizationCount = 500; // deliberately large -- if this ran for real, it would take a while
        std::atomic<bool> alreadyCancelled{true};

        auto start = std::chrono::steady_clock::now();
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng, &alreadyCancelled);
        auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();

        check(decision.completed == false, "completed is false when cancellation was already requested");
        check(decision.samplesCompleted == 0, "samplesCompleted is 0 -- not even the first sample ran");
        auto legal = MoveGenerator::generate(state, player);
        bool moveIsLegal = false;
        for (const auto& m : legal) {
            if (m.tile == decision.move.tile && m.side == decision.move.side) { moveIsLegal = true; break; }
        }
        check(moveIsLegal, "the fallback move (candidates[0]) is still a genuinely legal move, never fabricated");
        for (double v : decision.expectedValuePerPlayer) {
            check(v == 0.0, "expectedValuePerPlayer entries are honestly 0.0, not a misleading fabricated value");
        }
        check(elapsedMs < 2000,
              "returns essentially immediately (< 2s) rather than paying for even one full sample -- actual: "
              + std::to_string(elapsedMs) + "ms");
    }

    section("SearchEngine cancellation: a real cross-thread cancel mid-flight stops early, safely, with a usable partial result");
    {
        GameState state = freshOneVsOnePosition();
        int player = state.currentPlayerIndex();
        BeliefState belief = ProbabilityEngine::constructFromGameState(state, player);
        std::mt19937_64 rng(99);
        SearchEngine::Config config;
        config.maxDepthPlies = 4;
        config.determinizationCount = 4000; // large enough that a short real-time delay lands mid-flight
        std::atomic<bool> cancelFlag{false};

        std::thread canceller([&cancelFlag]() {
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
            cancelFlag.store(true, std::memory_order_relaxed);
        });

        auto start = std::chrono::steady_clock::now();
        auto decision = SearchEngine::chooseBestMove(state, belief, GameMode::OneVsOne, config, rng, &cancelFlag);
        auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
        canceller.join();

        // Never assert an exact sample count or exact timing -- genuinely
        // racy by nature. Assert only the properties that must ALWAYS
        // hold regardless of exactly how the race lands on this machine.
        check(decision.samplesCompleted >= 0 && decision.samplesCompleted <= config.determinizationCount,
              "samplesCompleted is always in [0, configured count] -- actual: " + std::to_string(decision.samplesCompleted));
        check(decision.completed == (decision.samplesCompleted == config.determinizationCount),
              "completed is true iff every configured sample ran -- no inconsistent combination");
        auto legal = MoveGenerator::generate(state, player);
        bool moveIsLegal = false;
        for (const auto& m : legal) {
            if (m.tile == decision.move.tile && m.side == decision.move.side) { moveIsLegal = true; break; }
        }
        check(moveIsLegal, "the returned move is always a genuinely legal candidate, completed or not");
        check(static_cast<int>(decision.expectedValuePerPlayer.size()) == state.playerCount(),
              "expectedValuePerPlayer always has exactly one entry per player, even on a partial result");
        if (!decision.completed) {
            std::cout << "  [info] cancelled after " << decision.samplesCompleted << "/" << config.determinizationCount
                      << " samples, in " << elapsedMs << "ms (informational, not a pass/fail assertion)\n";
        } else {
            std::cout << "  [info] the full search actually finished before the 30ms cancel fired ("
                      << elapsedMs << "ms total) -- cancellation path exercised elsewhere in this file instead\n";
        }
    }

    if (failureCount() == 0) {
        std::cout << "\nSearchEngineCancellation: all checks passed\n";
        return 0;
    }
    std::cout << "\nSearchEngineCancellation: " << failureCount() << " check(s) failed\n";
    return 1;
}
