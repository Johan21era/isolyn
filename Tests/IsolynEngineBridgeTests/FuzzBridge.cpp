// libFuzzer harness for the bridge's public API surface. Interprets the
// raw fuzzer-controlled byte stream as a sequence of bridge operations
// with adversarial arguments -- out-of-range enums, negative/huge player
// indices, tile pips outside [0,6], stale/future state versions, huge
// analysis configs, handles that were never returned by this bridge at
// all -- exactly the "assume the UI can produce nonsense" scenario this
// bridge's own design docs are built around. The only thing this checks
// is: can ANY byte sequence crash it, leak memory, or trip a sanitizer?
// It is deliberately NOT checking game-logic correctness (SmokeTest.cpp
// and the engine's own test suite do that) -- a fuzz target that also
// tries to assert domain correctness on top of pure garbage input mostly
// just produces uninteresting, expected "InvalidRequest" rejections
// dressed up as findings.
//
// Build with -fsanitize=fuzzer,address,undefined for this to be worth
// running at all -- see scripts/ci/fuzz_bridge.sh.
#include "IsolynBridge.hpp"
#include <fuzzer/FuzzedDataProvider.h>
#include <cstdint>
#include <vector>

using namespace isolyn::bridge;

namespace {

GameModeDTO consumeMode(FuzzedDataProvider& fdp) {
    // Deliberately includes out-of-range raw values sometimes, not just
    // the 3 real enumerators -- an int32_t crossing from Swift is not
    // guaranteed to be one of the named cases just because the type says
    // GameModeDTO.
    return static_cast<GameModeDTO>(fdp.ConsumeIntegralInRange<int32_t>(-2, 5));
}

ChainSideDTO consumeSide(FuzzedDataProvider& fdp) {
    return static_cast<ChainSideDTO>(fdp.ConsumeIntegralInRange<int32_t>(-2, 5));
}

TileDTO consumeTile(FuzzedDataProvider& fdp) {
    // Wide range on purpose: valid pips are [0,6], this deliberately also
    // hits negatives, >6, and INT8_MIN/MAX territory.
    int8_t low = fdp.ConsumeIntegralInRange<int8_t>(-10, 20);
    int8_t high = fdp.ConsumeIntegralInRange<int8_t>(-10, 20);
    return TileDTO{low, high};
}

MoveDTO consumeMove(FuzzedDataProvider& fdp) {
    return MoveDTO{consumeTile(fdp), consumeSide(fdp)};
}

int32_t consumePlayerIndex(FuzzedDataProvider& fdp) {
    return fdp.ConsumeIntegralInRange<int32_t>(-5, 10);
}

uint64_t consumeVersion(FuzzedDataProvider& fdp) {
    // Sometimes a plausible small version, sometimes a wildly wrong one
    // (including 0, and near UINT64_MAX).
    if (fdp.ConsumeBool()) {
        return fdp.ConsumeIntegralInRange<uint64_t>(0, 20);
    }
    return fdp.ConsumeIntegral<uint64_t>();
}

SessionHandle consumeSessionHandleGuess(FuzzedDataProvider& fdp, const std::vector<SessionHandle>& live) {
    // Sometimes reuse a real live handle (the interesting, valid case),
    // sometimes an entirely fabricated one (the adversarial case: a
    // handle value that was never returned by this bridge at all,
    // including 0 and huge/negative-looking values).
    if (!live.empty() && fdp.ConsumeBool()) {
        return live[fdp.ConsumeIntegralInRange<size_t>(0, live.size() - 1)];
    }
    return fdp.ConsumeIntegral<uint64_t>();
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    FuzzedDataProvider fdp(data, size);
    std::vector<SessionHandle> sessions;
    std::vector<AnalysisHandle> analyses;

    // Bound total operations per input so one fuzzer input can't itself
    // become an unbounded-runtime hang independent of any real bug --
    // libFuzzer's own timeout would eventually flag that as a "crash"
    // too, but bounding here keeps each input's cost predictable.
    int opBudget = 200;

    while (fdp.remaining_bytes() > 0 && opBudget-- > 0) {
        uint8_t op = fdp.ConsumeIntegral<uint8_t>() % 13;
        switch (op) {
            case 0: {
                SessionHandle s = bridge_session_create_first_round(consumeMode(fdp));
                if (s != kInvalidSessionHandle) sessions.push_back(s);
                break;
            }
            case 1: {
                GameModeDTO mode = consumeMode(fdp);
                int32_t starter = consumePlayerIndex(fdp);
                SessionHandle s = bridge_session_create_subsequent_round(mode, starter);
                if (s != kInvalidSessionHandle) sessions.push_back(s);
                break;
            }
            case 2: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                bridge_session_close(s);
                break;
            }
            case 3: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                int32_t player = consumePlayerIndex(fdp);
                SnapshotDTO snap = bridge_get_snapshot(s, player);
                (void)snap;
                break;
            }
            case 4: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                uint64_t version = consumeVersion(fdp);
                MoveDTO move = consumeMove(fdp);
                CommandResultDTO r = bridge_submit_move(s, version, move);
                (void)r;
                break;
            }
            case 5: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                uint64_t version = consumeVersion(fdp);
                CommandResultDTO r = bridge_voluntary_draw(s, version);
                (void)r;
                break;
            }
            case 6: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                uint64_t version = consumeVersion(fdp);
                CommandResultDTO r = bridge_resolve_forced_draw(s, version);
                (void)r;
                break;
            }
            case 7: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                uint64_t version = consumeVersion(fdp);
                CommandResultDTO r = bridge_end_turn_with_no_play(s, version);
                (void)r;
                break;
            }
            case 8: {
                SessionHandle s = consumeSessionHandleGuess(fdp, sessions);
                int32_t believer = consumePlayerIndex(fdp);
                AnalysisHandle a = bridge_analysis_snapshot_create(s, believer);
                if (a != kInvalidAnalysisHandle) analyses.push_back(a);
                break;
            }
            case 9: {
                AnalysisHandle a = analyses.empty() ? fdp.ConsumeIntegral<uint64_t>()
                                                     : analyses[fdp.ConsumeIntegralInRange<size_t>(0, analyses.size() - 1)];
                // Depth/determinization deliberately include 0, negative,
                // and huge values -- keep huge ones small enough that a
                // genuinely-valid combination can't itself make one fuzz
                // iteration pathologically slow.
                int32_t depth = fdp.ConsumeIntegralInRange<int32_t>(-3, 5);
                int32_t detCount = fdp.ConsumeIntegralInRange<int32_t>(-3, 8);
                uint64_t seed = fdp.ConsumeIntegral<uint64_t>();
                AnalysisResultDTO r = bridge_analysis_run(a, depth, detCount, seed);
                (void)r;
                break;
            }
            case 10: {
                AnalysisHandle a = analyses.empty() ? fdp.ConsumeIntegral<uint64_t>()
                                                     : analyses[fdp.ConsumeIntegralInRange<size_t>(0, analyses.size() - 1)];
                bridge_analysis_request_cancel(a);
                break;
            }
            case 11: {
                AnalysisHandle a = analyses.empty() ? fdp.ConsumeIntegral<uint64_t>()
                                                     : analyses[fdp.ConsumeIntegralInRange<size_t>(0, analyses.size() - 1)];
                bridge_analysis_snapshot_destroy(a);
                break;
            }
            case 12: {
                // Entirely fabricated handles on BOTH tables, every time
                // -- specifically targets "a handle that never existed
                // and never will" rather than "a real handle, misused."
                bridge_session_close(fdp.ConsumeIntegral<uint64_t>());
                bridge_analysis_snapshot_destroy(fdp.ConsumeIntegral<uint64_t>());
                break;
            }
        }
    }

    // Clean up whatever's left so repeated libFuzzer iterations (which
    // reuse the same process) don't accumulate unbounded live sessions
    // across inputs -- that would be a fuzz-harness artifact, not a real
    // bridge leak, and would eventually make the corpus run slow for a
    // reason unrelated to what's being tested.
    for (AnalysisHandle a : analyses) bridge_analysis_snapshot_destroy(a);
    for (SessionHandle s : sessions) bridge_session_close(s);

    return 0;
}
