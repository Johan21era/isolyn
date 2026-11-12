#include "IsolynAccelerator.hpp"
#include "IsolynEvaluationBatch.hpp"
#include "IsolynPositionBatch.hpp"
#include "EvaluationEngine.hpp"
#include "MoveGenerator.hpp"
#include "TestHarness.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <chrono>
#include <cstddef>
#include <iostream>
#include <vector>

using namespace isolyn;
using namespace isolyn::accelerator;
using namespace isolyn::test;

namespace {

GameState makeState() {
    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(6, 5), DominoTile(4, 3) },
        { DominoTile(5, 2), DominoTile(1, 1) },
    };
    GameState state(GameMode::OneVsOne, hands, {});
    state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left);
    return state;
}

GameState makeModeState(GameMode mode) {
    if (mode == GameMode::OneVsOne) return makeState();

    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(6, 5), DominoTile(4, 3) },
        { DominoTile(5, 2), DominoTile(1, 1) },
        { DominoTile(6, 4), DominoTile(2, 2) },
        { DominoTile(5, 3), DominoTile(0, 0) },
    };
    if (mode == GameMode::OneVsOneVsOne) hands.pop_back();
    GameState state(mode, hands, {});
    state.playTile(0, DominoTile(6, 5), GameState::ChainSide::Left);
    return state;
}

GameState makeTerminalState() {
    std::vector<std::vector<DominoTile>> hands = { {}, { DominoTile(4, 1) } };
    return GameState(GameMode::OneVsOne, hands, {});
}

GameState makeClosedState() {
    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(6, 4), DominoTile(2, 2) },
        { DominoTile(4, 4), DominoTile(1, 1) },
    };
    GameState state(GameMode::OneVsOne, hands, {});
    state.playTile(1, DominoTile(4, 4), GameState::ChainSide::Left);
    state.playTile(0, DominoTile(6, 4), GameState::ChainSide::Left);
    return state;
}

GameState makeStuckWithBoneyardState() {
    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(6, 6) },
        { DominoTile(5, 5) },
    };
    GameState state(GameMode::OneVsOne, hands,
                    { DominoTile(1, 1), DominoTile(2, 2), DominoTile(3, 3) });
    state.playTile(0, DominoTile(6, 6), GameState::ChainSide::Left);
    return state;
}

GameState makeEmptyChainState() {
    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(6, 5), DominoTile(2, 1) },
        { DominoTile(5, 2), DominoTile(1, 1) },
    };
    return GameState(GameMode::OneVsOne, hands, {});
}

GameState makeEqualEndsState() {
    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(4, 4), DominoTile(2, 2) },
        { DominoTile(4, 3), DominoTile(1, 1) },
    };
    GameState state(GameMode::OneVsOne, hands, {});
    state.playTile(0, DominoTile(4, 4), GameState::ChainSide::Left);
    state.setCurrentPlayerIndex(1);
    return state;
}

GameState makeThreatState() {
    std::vector<std::vector<DominoTile>> hands = {
        { DominoTile(4, 4), DominoTile(2, 2) },
        { DominoTile(4, 3) },
    };
    GameState state(GameMode::OneVsOne, hands, {});
    state.playTile(0, DominoTile(4, 4), GameState::ChainSide::Left);
    state.setCurrentPlayerIndex(1);
    return state;
}

bool closeEnough(float actual, double expected) {
    return std::fabs(static_cast<double>(actual) - expected) <= 1e-3;
}

} // namespace

int main() {
    section("Accelerator: CPU reference matches EvaluationEngine's weighted components");
    {
        const GameState state = makeState();
        const EvaluationBatch encoded =
            encodeEvaluationBatch(GameMode::OneVsOne, {state});
        check(encoded.positionCount == 1, "one position is encoded");
        check(encoded.playerCount == 2, "the 1v1 batch has two player rows");
        check(encoded.componentCount == kEvaluationComponentCount,
              "the encoder emits all eight evaluation components");
        check(encoded.features.size() == 2 * kEvaluationComponentCount,
              "the feature matrix has one eight-component row per player");

        std::vector<float> cpu(2, -1.0f);
        BatchView batch{encoded.features.data(), encoded.positionCount,
                        encoded.playerCount * encoded.componentCount,
                        cpu.data(), encoded.playerCount};
        check(evaluateCpuReference(batch), "the CPU reference accepts the encoded batch");
        for (int player = 0; player < 2; ++player) {
            const double expected =
                EvaluationEngine::evaluate(GameMode::OneVsOne, state, player).total;
            check(closeEnough(cpu[static_cast<std::size_t>(player)], expected),
                  "CPU feature sum equals EvaluationEngine total for player "
                  + std::to_string(player));
        }
    }

    section("Accelerator: malformed batches fail closed");
    {
        float features[16] = {};
        float values[2] = { 7.0f, 8.0f };
        check(!evaluateCpuReference(BatchView{}),
              "a default-empty batch is rejected");

        BatchView nullFeatures{nullptr, 1, 16, values, 2};
        check(!evaluateCpuReference(nullFeatures),
              "a null feature matrix is rejected");

        BatchView nullValues{features, 1, 16, nullptr, 2};
        check(!evaluateCpuReference(nullValues),
              "a null output matrix is rejected");

        BatchView zeroPositions{features, 0, 16, values, 2};
        check(!evaluateCpuReference(zeroPositions),
              "a zero-position batch is rejected");

        BatchView uneven{features, 1, 15, values, 2};
        check(!evaluateCpuReference(uneven),
              "a feature count not divisible by player count is rejected");

        BatchView tooManyComponents{features, 1, 2 * 65, values, 2};
        check(!evaluateCpuReference(tooManyComponents),
              "a component count above the supported cap is rejected");
    }

    section("Accelerator: synthetic CPU/GPU batch parity");
    {
        constexpr std::size_t positionCount = 257;
        constexpr std::size_t playerCount = 2;
        constexpr std::size_t componentCount = 8;
        std::vector<float> features(positionCount * playerCount * componentCount);
        for (std::size_t i = 0; i < features.size(); ++i) {
            features[i] = static_cast<float>((i * 17) % 29) / 7.0f - 1.5f;
        }

        std::vector<float> cpu(positionCount * playerCount);
        BatchView batch{features.data(), positionCount,
                        playerCount * componentCount, cpu.data(), playerCount};
        check(evaluateCpuReference(batch), "CPU reference evaluates the synthetic batch");

        Backend* backend = metalBackend();
        if (backend == nullptr) {
            std::cout << "  [skip] no Metal pipeline available; CPU path verified\n";
        } else {
            const Capabilities caps = backend->capabilities();
            check(caps.available, "Metal backend reports available");
            check(caps.unifiedMemory, "Apple Silicon reports unified memory");
            check(caps.maxBatchSize >= positionCount, "the synthetic batch fits the device limit");
            check(!caps.name.empty(), "the backend reports a device name");

            std::vector<float> gpu(positionCount * playerCount);
            BatchView gpuBatch{features.data(), positionCount,
                               playerCount * componentCount, gpu.data(), playerCount};
            check(backend->evaluate(gpuBatch), "Metal evaluates the synthetic batch");
            bool parity = true;
            for (std::size_t i = 0; i < cpu.size(); ++i) {
                if (std::fabs(cpu[i] - gpu[i]) > 1e-4f) parity = false;
            }
            check(parity, "Metal values match the CPU reference within 1e-4");

            BatchView tooLarge{features.data(), caps.maxBatchSize + 1,
                               playerCount * componentCount, gpu.data(), playerCount};
            check(!backend->evaluate(tooLarge),
                  "Metal rejects a batch above its advertised maximum");
        }
    }

    section("Accelerator: real EvaluationEngine batch parity through Metal");
    {
        Backend* backend = metalBackend();
        if (backend == nullptr) {
            std::cout << "  [skip] no Metal pipeline available\n";
        } else {
            const GameState state = makeState();
            const EvaluationBatch encoded =
                encodeEvaluationBatch(GameMode::OneVsOne, {state, state});
            std::vector<float> cpu(encoded.positionCount * encoded.playerCount);
            std::vector<float> gpu(cpu.size());
            BatchView cpuBatch{encoded.features.data(), encoded.positionCount,
                               encoded.playerCount * encoded.componentCount,
                               cpu.data(), encoded.playerCount};
            BatchView gpuBatch{encoded.features.data(), encoded.positionCount,
                               encoded.playerCount * encoded.componentCount,
                               gpu.data(), encoded.playerCount};
            check(evaluateCpuReference(cpuBatch), "CPU reference evaluates the encoded batch");
            check(backend->evaluate(gpuBatch), "Metal evaluates the encoded batch");
            bool parity = true;
            for (std::size_t i = 0; i < cpu.size(); ++i) {
                if (std::fabs(cpu[i] - gpu[i]) > 1e-4f) parity = false;
            }
            check(parity, "encoded EvaluationEngine rows match through Metal");
        }
    }

    section("Accelerator: batch throughput");
    {
        constexpr std::size_t positionCount = 16384;
        constexpr std::size_t playerCount = 2;
        constexpr std::size_t componentCount = 8;
        std::vector<float> features(positionCount * playerCount * componentCount);
        for (std::size_t i = 0; i < features.size(); ++i) {
            features[i] = static_cast<float>((i * 13) % 31) / 9.0f - 1.0f;
        }
        std::vector<float> values(positionCount * playerCount);
        BatchView batch{features.data(), positionCount,
                        playerCount * componentCount, values.data(), playerCount};

        auto measure = [&](bool useMetal) -> double {
            const auto start = std::chrono::steady_clock::now();
            constexpr int iterations = 12;
            for (int i = 0; i < iterations; ++i) {
                if (useMetal) {
                    if (metalBackend() == nullptr || !metalBackend()->evaluate(batch)) return -1.0;
                } else if (!evaluateCpuReference(batch)) {
                    return -1.0;
                }
            }
            const auto end = std::chrono::steady_clock::now();
            return std::chrono::duration<double>(end - start).count() /
                   static_cast<double>(iterations);
        };

        const double cpuSeconds = measure(false);
        check(cpuSeconds > 0.0, "CPU batch benchmark completed");
        if (cpuSeconds > 0.0) {
            std::cout << "  [info] CPU: " << (positionCount / cpuSeconds)
                      << " positions/sec\n";
        }

        if (metalBackend() != nullptr) {
            const double gpuSeconds = measure(true);
            check(gpuSeconds > 0.0, "Metal batch benchmark completed");
            if (gpuSeconds > 0.0) {
                std::cout << "  [info] Metal: " << (positionCount / gpuSeconds)
                          << " positions/sec\n";
            }
        }
    }

    section("Accelerator: compact position parity across modes");
    {
        Backend* backend = metalBackend();
        if (backend == nullptr) {
            std::cout << "  [skip] no Metal position pipeline available\n";
        } else {
            const std::array<GameMode, 3> modes = {
                GameMode::OneVsOne,
                GameMode::OneVsOneVsOne,
                GameMode::TwoVsTwo,
            };
            for (GameMode mode : modes) {
                const GameState state = makeModeState(mode);
                const PositionBatch encoded = encodePositionBatch(mode, {state});
                check(encoded.rows.size() == 1,
                      "compact position batch has one row");
                check(encoded.playerCount == static_cast<std::size_t>(state.playerCount()),
                      "compact batch preserves player count");
                check(encoded.rows[0].closed ==
                          (MoveGenerator::isPositionClosed(state) ? 1u : 0u),
                      "compact closed flag matches movegen");

                std::vector<float> values(encoded.playerCount);
                PositionBatchView view{encoded.rows.data(), 1,
                                       values.data(), encoded.playerCount};
                check(backend->evaluatePositions(view),
                      "Metal evaluates the compact position batch");
                for (int player = 0; player < state.playerCount(); ++player) {
                    const double expected =
                        EvaluationEngine::evaluate(mode, state, player).total;
                    check(std::fabs(values[static_cast<std::size_t>(player)] - expected) <= 1e-3,
                          "compact GPU total matches EvaluationEngine");
                }
            }

            const GameState closed = makeClosedState();
            const PositionBatch closedBatch =
                encodePositionBatch(GameMode::OneVsOne, {closed});
            check(closedBatch.rows[0].closed == 1u,
                  "closed compact fixture is marked closed");

            const GameState stuckWithBoneyard = makeStuckWithBoneyardState();
            const PositionBatch boneyardBatch =
                encodePositionBatch(GameMode::OneVsOne, {stuckWithBoneyard});
            check(boneyardBatch.rows[0].closed == 0u,
                  "nonempty boneyard keeps a stuck hand position open");

            std::vector<float> closedValues(2);
            PositionBatchView closedView{closedBatch.rows.data(), 1,
                                         closedValues.data(), 2};
            check(backend->evaluatePositions(closedView),
                  "Metal evaluates a closed compact position");
            for (int player = 0; player < 2; ++player) {
                const double expected =
                    EvaluationEngine::evaluate(GameMode::OneVsOne, closed, player).total;
                check(std::fabs(closedValues[static_cast<std::size_t>(player)] - expected) <= 1e-3,
                      "closed-position total matches EvaluationEngine");
            }

            const PositionRow row{};
            float dummy[2] = {};
            check(!backend->evaluatePositions(PositionBatchView{}),
                  "Metal rejects an empty compact view");
            check(!backend->evaluatePositions(PositionBatchView{nullptr, 1, dummy, 2}),
                  "Metal rejects null compact rows");
            check(!backend->evaluatePositions(PositionBatchView{&row, 1, nullptr, 2}),
                  "Metal rejects a null compact output");
            check(!backend->evaluatePositions(PositionBatchView{&row, 1, dummy, 1}),
                  "Metal rejects an invalid compact player count");
            check(!backend->evaluatePositions(
                      PositionBatchView{&row, backend->capabilities().maxBatchSize + 1, dummy, 2}),
                  "Metal rejects an oversized compact batch");

            const GameState terminal = makeTerminalState();
            const PositionBatch terminalBatch =
                encodePositionBatch(GameMode::OneVsOne, {terminal});
            std::vector<float> terminalValues(2);
            PositionBatchView terminalView{terminalBatch.rows.data(), 1,
                                           terminalValues.data(), 2};
            check(backend->evaluatePositions(terminalView),
                  "Metal evaluates a terminal compact position");
            check(std::fabs(terminalValues[0] - 0.0f) <= 1e-3f,
                  "terminal winner evaluates to zero");
            check(std::fabs(terminalValues[1] - (-5.0f)) <= 1e-3f,
                  "terminal loser is charged its remaining pips");
        }
    }

    section("Accelerator: compact multi-mode scale parity");
    {
        Backend* backend = metalBackend();
        if (backend == nullptr) {
            std::cout << "  [skip] no Metal position pipeline available\n";
        } else {
            constexpr std::size_t positionCount = 4096;
            for (GameMode mode : {GameMode::OneVsOne, GameMode::OneVsOneVsOne,
                                  GameMode::TwoVsTwo}) {
                const GameState base = makeModeState(mode);
                std::vector<GameState> positions(positionCount, base);
                for (std::size_t i = 0; i < positions.size(); ++i) {
                    positions[i].setCurrentPlayerIndex(
                        static_cast<int>(i % static_cast<std::size_t>(base.playerCount())));
                }

                const PositionBatch encoded = encodePositionBatch(mode, positions);
                check(encoded.rows.size() == positionCount,
                      "multi-mode scale batch encodes every position");
                check(encoded.playerCount == static_cast<std::size_t>(base.playerCount()),
                      "multi-mode scale batch preserves player count");

                std::vector<float> gpu(positionCount * encoded.playerCount);
                PositionBatchView view{encoded.rows.data(), positionCount,
                                       gpu.data(), encoded.playerCount};
                check(backend->evaluatePositions(view),
                      "multi-mode scale batch evaluates through Metal");

                std::size_t mismatches = 0;
                double maxDelta = 0.0;
                for (std::size_t i = 0; i < positionCount; ++i) {
                    for (int player = 0; player < base.playerCount(); ++player) {
                        const double expected = EvaluationEngine::evaluate(
                            mode, positions[i], player).total;
                        const double delta = std::fabs(
                            static_cast<double>(gpu[i * encoded.playerCount +
                                                    static_cast<std::size_t>(player)]) -
                            expected);
                        maxDelta = std::max(maxDelta, delta);
                        if (delta > 1e-3) ++mismatches;
                    }
                }
                check(mismatches == 0,
                      "multi-mode scale GPU parity holds (max delta " +
                          std::to_string(maxDelta) + ")");
            }
        }
    }

    section("Accelerator: compact parity edge cases");
    {
        Backend* backend = metalBackend();
        if (backend == nullptr) {
            std::cout << "  [skip] no Metal position pipeline available\n";
        } else {
            auto checkCase = [&](const char* label, GameMode mode, const GameState& state) {
                const PositionBatch encoded = encodePositionBatch(mode, {state});
                check(encoded.rows.size() == 1,
                      std::string(label) + " encodes one compact row");
                std::vector<float> values(encoded.playerCount);
                PositionBatchView view{encoded.rows.data(), 1,
                                       values.data(), encoded.playerCount};
                check(backend->evaluatePositions(view),
                      std::string(label) + " evaluates through Metal");
                for (int player = 0; player < state.playerCount(); ++player) {
                    const double expected =
                        EvaluationEngine::evaluate(mode, state, player).total;
                    check(std::fabs(values[static_cast<std::size_t>(player)] - expected) <= 1e-3,
                          std::string(label) + " matches EvaluationEngine for player " +
                              std::to_string(player));
                }
            };

            checkCase("empty chain", GameMode::OneVsOne, makeEmptyChainState());
            checkCase("equal chain ends", GameMode::OneVsOne, makeEqualEndsState());
            checkCase("one-tile immediate threat", GameMode::OneVsOne, makeThreatState());
        }
    }

    section("Accelerator: compact CPU/GPU throughput");
    {
        Backend* backend = metalBackend();
        if (backend == nullptr) {
            std::cout << "  [skip] no Metal position pipeline available\n";
        } else {
            constexpr std::size_t positionCount = 65536;
            constexpr std::size_t playerCount = 2;
            const std::vector<GameState> positions(positionCount, makeState());

            const auto encodeStart = std::chrono::steady_clock::now();
            const PositionBatch encoded =
                encodePositionBatch(GameMode::OneVsOne, positions);
            const auto encodeEnd = std::chrono::steady_clock::now();
            const double encodeSeconds =
                std::chrono::duration<double>(encodeEnd - encodeStart).count();
            check(encoded.rows.size() == positionCount,
                  "compact benchmark encodes every position");
            check(encodeSeconds > 0.0, "compact host encoding completed");

            volatile double cpuSink = 0.0;
            std::cout << "  [info] encode: " << (positionCount / encodeSeconds)
                      << " positions/sec\n";
            std::cout << "  [info] size   CPU positions/s   Metal positions/s   Metal us/call\n";

            for (std::size_t size : {std::size_t(1024), std::size_t(4096),
                                     std::size_t(16384), positionCount}) {
                std::vector<float> gpu(size * playerCount);
                PositionBatchView view{encoded.rows.data(), size,
                                       gpu.data(), playerCount};

                // Warm the pipeline and grow the persistent buffers before
                // timing. Each sample is a full dispatch + completion.
                bool gpuOk = true;
                for (int warmup = 0; warmup < 4; ++warmup) {
                    gpuOk = gpuOk && backend->evaluatePositions(view);
                }

                std::vector<double> gpuTimes;
                gpuTimes.reserve(32);
                for (int iteration = 0; iteration < 32; ++iteration) {
                    const auto start = std::chrono::steady_clock::now();
                    gpuOk = gpuOk && backend->evaluatePositions(view);
                    const auto end = std::chrono::steady_clock::now();
                    gpuTimes.push_back(
                        std::chrono::duration<double>(end - start).count());
                }
                std::sort(gpuTimes.begin(), gpuTimes.end());
                const double gpuSeconds = gpuTimes[gpuTimes.size() / 2];

                constexpr int cpuIterations = 8;
                const auto cpuStart = std::chrono::steady_clock::now();
                for (int iteration = 0; iteration < cpuIterations; ++iteration) {
                    for (std::size_t position = 0; position < size; ++position) {
                        for (int player = 0; player < static_cast<int>(playerCount); ++player) {
                            cpuSink += EvaluationEngine::evaluate(
                                GameMode::OneVsOne, positions[position], player).total;
                        }
                    }
                }
                const auto cpuEnd = std::chrono::steady_clock::now();
                const double cpuSeconds =
                    std::chrono::duration<double>(cpuEnd - cpuStart).count() / cpuIterations;

                check(gpuOk, "Metal compact benchmark completed");
                check(cpuSink != 0.0, "CPU compact benchmark produced real values");
                check(gpuSeconds > 0.0, "Metal compact timing is positive");

                if (size == positionCount) {
                    for (int player = 0; player < static_cast<int>(playerCount); ++player) {
                        const double expected = EvaluationEngine::evaluate(
                            GameMode::OneVsOne, positions[0], player).total;
                        check(std::fabs(gpu[static_cast<std::size_t>(player)] - expected) <= 1e-3,
                              "max-size compact output still matches CPU");
                    }
                }

                std::cout << "  [info] " << size << "   "
                          << (size / cpuSeconds) << "   "
                          << (size / gpuSeconds) << "   "
                          << (gpuSeconds * 1e6) << "\n";
            }
        }
    }

    if (failureCount() == 0) {
        std::cout << "\nAccelerator: all checks passed\n";
        return 0;
    }
    std::cout << "\nAccelerator: " << failureCount() << " check(s) failed\n";
    return 1;
}
