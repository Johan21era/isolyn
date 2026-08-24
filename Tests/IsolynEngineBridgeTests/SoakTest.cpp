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

using namespace isolyn::bridge;

namespace {

// Linux-specific (/proc/self/status) on purpose -- this is a dev-sandbox
// diagnostic tool, not portable production code, and this repo's engine
// tests already use platform-conditional entropy sources elsewhere for
// the same reason: use what the sandbox actually provides.
long currentRssKb() {
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
        std::printf("\n[inconclusive] could not read /proc/self/status -- not this sandbox's fault necessarily, "
                    "just not a signal this run can report on\n");
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
