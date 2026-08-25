// Soak test: thousands of realistic session lifecycles (create, play
// several moves, run one analysis, close) back to back in one long-lived
// process, checking that memory usage stabilizes rather than growing
// without bound. Complements FuzzBridge.cpp (adversarial inputs, short
// bursts) and SmokeTest.cpp (correctness, one or two sessions) -- this
// one is specifically about "does repeated NORMAL use leak," which
// neither of those is really shaped to catch on its own.
#include "IsolynBridge.hpp"
#include <cstdio>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

using namespace isolyn::bridge;

namespace {

// Platform RSS reader. FIX-27 (audit OA-1): this was Linux-only
// (/proc/self/status) by design back when a Linux sandbox was the only
// machine that ever ran it -- but macOS is the SHIPPING platform and the
// only one CI runs on, so "couldn't measure" was silently green here on
// every single run. Now: Mach task introspection on Apple, /proc on
// Linux, and a LOUD inconclusive everywhere else (see main()'s banner)
// -- never a quiet pass pretending to have measured anything.
long currentRssKb() {
#if defined(__APPLE__)
    mach_task_basic_info_data_t info{};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (::task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                    reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS) {
        return -1;
    }
    return static_cast<long>(info.resident_size / 1024);
#elif defined(__linux__)
    std::ifstream f("/proc/self/status");
    std::string line;
    while (std::getline(f, line)) {
        if (line.rfind("VmRSS:", 0) == 0) {
            std::istringstream iss(line.substr(6));
            long kb = 0;
            iss >> kb;
            return kb;
        }
    }
    return -1;
#else
    return -1;
#endif
}

void runOneRealisticCycle(int cycleIndex) {
    GameModeDTO mode = (cycleIndex % 3 == 0) ? GameModeDTO::OneVsOne
                       : (cycleIndex % 3 == 1) ? GameModeDTO::OneVsOneVsOne
                                                : GameModeDTO::TwoVsTwo;
    SessionHandle s = bridge_session_create_first_round(mode);
    if (s == kInvalidSessionHandle) return;

    for (int move = 0; move < 40; ++move) {
        SnapshotDTO snap = bridge_get_snapshot(s, 0);
        if (snap.status != BridgeStatus::Ok || snap.roundOutcome != RoundOutcomeDTO::InProgress) break;

        int current = snap.currentPlayerIndex;
        SnapshotDTO currentSnap = bridge_get_snapshot(s, current);
        if (currentSnap.legalMovesForRequestingPlayer.count == 0) {
            bridge_resolve_forced_draw(s, currentSnap.stateVersion);
            continue;
        }

        // Every few moves, exercise the full analysis path too -- the
        // realistic "player opens the analysis panel" case, not just raw
        // command throughput.
        if (move % 5 == 0) {
            AnalysisHandle a = bridge_analysis_snapshot_create(s, current);
            if (a != kInvalidAnalysisHandle) {
                bridge_analysis_run(a, 2, 3, static_cast<uint64_t>(cycleIndex * 1000 + move));
                bridge_analysis_snapshot_destroy(a);
            }
        }

        MoveDTO chosen = currentSnap.legalMovesForRequestingPlayer.moves[0];
        bridge_submit_move(s, currentSnap.stateVersion, chosen);
    }

    bridge_session_close(s);
}

} // namespace

int main(int argc, char** argv) {
    int cycles = (argc > 1) ? std::atoi(argv[1]) : 10000;
    std::printf("Running %d full session lifecycle cycles...\n", cycles);

    long rssBefore = currentRssKb();
    long rssAfterWarmup = -1;

    for (int i = 0; i < cycles; ++i) {
        runOneRealisticCycle(i);
        if (i == 200) {
            // Let the allocator's own steady-state (arena growth, thread
            // caches, etc.) settle before measuring the "baseline" --
            // otherwise ordinary allocator warmup looks identical to a
            // leak in the first few hundred cycles.
            rssAfterWarmup = currentRssKb();
        }
        if (i > 0 && i % 2000 == 0) {
            std::printf("  cycle %d/%d, VmRSS=%ld KB\n", i, cycles, currentRssKb());
        }
    }

    long rssAfter = currentRssKb();
    std::printf("\nVmRSS before any cycles: %ld KB\n", rssBefore);
    std::printf("VmRSS after warmup (cycle 200): %ld KB\n", rssAfterWarmup);
    std::printf("VmRSS after all %d cycles: %ld KB\n", cycles, rssAfter);

    if (rssAfterWarmup <= 0 || rssAfter <= 0) {
        // FIX-27 (audit OA-1): an unmeasurable run used to exit 0 with one
        // quiet line -- indistinguishable from a pass in a scrolled log.
        // Still exits 0 (never false-fail an exotic environment), but now
        // it SCREAMS. On Linux and macOS -- the only two platforms this
        // project has ever run on -- inconclusive should simply never
        // happen again; if it does, something platform-shaped changed.
        std::printf("\n*************************************************************\n");
        std::printf("*** WARNING: RSS MEASUREMENT UNAVAILABLE ON THIS PLATFORM ***\n");
        std::printf("*** The leak signal is ABSENT from this run. This soak    ***\n");
        std::printf("*** test verified NOTHING. Investigate before trusting.   ***\n");
        std::printf("*************************************************************\n");
        return 0;
    }

    long growthKb = rssAfter - rssAfterWarmup;
    double growthPerCycleBytes = (static_cast<double>(growthKb) * 1024.0) / static_cast<double>(cycles - 200);
    std::printf("Growth from warmup to end: %ld KB over %d cycles (%.1f bytes/cycle)\n",
                growthKb, cycles - 200, growthPerCycleBytes);

    // Generous threshold on purpose: this is a coarse, single-process,
    // allocator-noise-sensitive signal, not a substitute for ASan's leak
    // detector (which already ran clean on the shorter, more targeted
    // suites) -- this check exists to catch something ASan's shorter runs
    // could plausibly miss: a slow leak too small to show up in dozens of
    // cycles but real over thousands.
    bool ok = growthPerCycleBytes < 500.0;
    std::printf("\n%s\n", ok ? "[pass] memory growth per cycle is small and consistent with allocator noise, not a leak"
                              : "[FAIL] memory growth per cycle exceeds the noise threshold -- investigate");
    return ok ? 0 : 1;
}
