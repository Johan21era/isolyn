#include "EvaluationEngine.hpp"
#include "GameState.hpp"
#include "MoveGenerator.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

using namespace isolyn;

namespace {

GameState makeFixture(GameMode mode) {
    std::vector<std::vector<DominoTile>> hands;
    switch (mode) {
        case GameMode::OneVsOne:
            hands = {
                { DominoTile(6, 5), DominoTile(4, 3), DominoTile(2, 1), DominoTile(6, 0) },
                { DominoTile(5, 4), DominoTile(3, 2), DominoTile(1, 0), DominoTile(6, 3) },
            };
            break;
        case GameMode::OneVsOneVsOne:
            hands = {
                { DominoTile(6, 5), DominoTile(4, 3), DominoTile(2, 1), DominoTile(6, 0) },
                { DominoTile(5, 4), DominoTile(3, 2), DominoTile(1, 0), DominoTile(6, 3) },
                { DominoTile(5, 3), DominoTile(4, 2), DominoTile(1, 1), DominoTile(0, 0) },
            };
            break;
        case GameMode::TwoVsTwo:
            hands = {
                { DominoTile(6, 5), DominoTile(4, 3), DominoTile(2, 1), DominoTile(6, 0) },
                { DominoTile(5, 4), DominoTile(3, 2), DominoTile(1, 0), DominoTile(6, 3) },
                { DominoTile(5, 3), DominoTile(4, 2), DominoTile(1, 1), DominoTile(0, 0) },
                { DominoTile(5, 2), DominoTile(4, 1), DominoTile(3, 0), DominoTile(2, 2) },
            };
            break;
    }

    GameState state(mode, hands, {});
    state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left);
    state.setCurrentPlayerIndex(1);
    return state;
}

const char* modeName(GameMode mode) {
    switch (mode) {
        case GameMode::OneVsOne: return "1v1";
        case GameMode::OneVsOneVsOne: return "1v1v1";
        case GameMode::TwoVsTwo: return "2v2";
    }
    return "unknown";
}

template <typename Fn>
double positionsPerSecond(std::size_t positions, Fn&& fn) {
    const auto start = std::chrono::steady_clock::now();
    fn();
    const auto end = std::chrono::steady_clock::now();
    const double seconds = std::chrono::duration<double>(end - start).count();
    return seconds > 0.0 ? static_cast<double>(positions) / seconds : 0.0;
}

double median(std::array<double, 3> values) {
    std::sort(values.begin(), values.end());
    return values[1];
}

void benchmarkMode(GameMode mode) {
    const GameState state = makeFixture(mode);
    const int playerCount = state.playerCount();
    constexpr int sampleCount = 3;
    constexpr int evalIterations = 2'000'000;
    constexpr int movegenIterations = 5'000'000;
    constexpr int hashIterations = 10'000'000;

    volatile double sink = 0.0;

    // Warm up branch predictors, caches, and CPU frequency before timing.
    // The previous un-warmed, sub-second harness varied by nearly 2x under
    // scheduler noise; three longer samples make regressions comparable.
    for (int i = 0; i < 50'000; ++i) {
        for (int player = 0; player < playerCount; ++player) {
            sink += EvaluationEngine::evaluate(mode, state, player).total;
            sink += static_cast<double>(MoveGenerator::generate(state, player).size());
        }
        sink += state.hash();
    }

    std::array<double, sampleCount> evalRates{};
    std::array<double, sampleCount> moveRates{};
    std::array<double, sampleCount> hashRates{};
    for (int sample = 0; sample < sampleCount; ++sample) {
        evalRates[static_cast<std::size_t>(sample)] = positionsPerSecond(
            static_cast<std::size_t>(evalIterations) * static_cast<std::size_t>(playerCount),
            [&] {
                for (int i = 0; i < evalIterations; ++i) {
                    for (int player = 0; player < playerCount; ++player) {
                        sink += EvaluationEngine::evaluate(mode, state, player).total;
                    }
                }
            });

        moveRates[static_cast<std::size_t>(sample)] = positionsPerSecond(
            static_cast<std::size_t>(movegenIterations) * static_cast<std::size_t>(playerCount),
            [&] {
                for (int i = 0; i < movegenIterations; ++i) {
                    for (int player = 0; player < playerCount; ++player) {
                        sink += static_cast<double>(
                            MoveGenerator::generate(state, player).size());
                    }
                }
            });

        hashRates[static_cast<std::size_t>(sample)] = positionsPerSecond(
            static_cast<std::size_t>(hashIterations),
            [&] {
                for (int i = 0; i < hashIterations; ++i) sink += state.hash();
            });
    }

    std::cout << std::left << std::setw(6) << modeName(mode)
              << " eval " << std::setw(12) << std::fixed << std::setprecision(0)
              << median(evalRates)
              << " movegen " << std::setw(12) << median(moveRates)
              << " hash " << std::setw(12) << median(hashRates)
              << " sink " << sink << '\n';
}

} // namespace

int main() {
    std::cout << "IsolynV2.0 CPU benchmark (higher is better)\n";
    std::cout << "mode   eval positions/s  movegen/s    hash/s\n";
    benchmarkMode(GameMode::OneVsOne);
    benchmarkMode(GameMode::OneVsOneVsOne);
    benchmarkMode(GameMode::TwoVsTwo);
    return 0;
}
