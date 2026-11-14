import Foundation
import Observation

/// What a run will cost on this machine, measured rather than guessed.
struct LabWorkloadEstimate: Equatable {
    let rate: Double            // games per second
    let duration: TimeInterval  // for the whole run
    let shardCount: Int
    let outputBytes: Double
    let probeGames: Int
    let probeSeconds: Double
    let measuredAt: Date

    enum Level: String {
        case light = "Light"
        case moderate = "Moderate"
        case heavy = "Heavy"
        case extreme = "Extreme"
    }

    var level: Level {
        switch duration {
        case ..<600: return .light        // under 10 minutes
        case ..<7_200: return .moderate   // under 2 hours
        case ..<43_200: return .heavy     // under 12 hours
        default: return .extreme
        }
    }

    /// Position on a logarithmic gauge from one minute to seven days, so a
    /// 10-second smoke run and a 3-day corpus both land somewhere visible.
    var gaugeFraction: Double {
        let minutes = max(1.0 / 60.0, duration / 60.0)
        let low = log10(1.0), high = log10(7.0 * 24.0 * 60.0)
        return min(1.0, max(0.0, (log10(minutes) - low) / (high - low)))
    }

    var durationText: String {
        let seconds = Int(duration.rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 36 { return "\(hours)h \(minutes % 60)m" }
        let days = Double(hours) / 24.0
        return String(format: "%.1f days", days)
    }

    var outputText: String {
        ByteCountFormatter.string(fromByteCount: Int64(outputBytes), countStyle: .file)
    }

    var rateText: String {
        String(format: "%.1f games/s", rate)
    }
}

/// Measures throughput by running a small real workload with the same shape as
/// the requested run: the same number of shard processes, the same depth and
/// samples. A synthetic CPU benchmark would be easier and would lie.
@MainActor
@Observable
final class LabEstimator {
    private(set) var estimate: LabWorkloadEstimate?
    private(set) var isMeasuring = false
    private(set) var message: String?
    private(set) var measuredConfig: LabRunConfig?

    let root: URL?
    let dataRoot: URL
    private let launcher: LabLaunching
    private var probeStart: Date?
    private var probeGames = 0
    private var pending: LabRunConfig?
    private var lastFinished: Date?

    /// Only a handful of games per shard is enough: startup and search warm-up
    /// are included in the measurement, so a slightly longer probe is more
    /// honest than a shorter one.
    private let gamesPerShard = 8

    init(
        launcher: LabLaunching = ProcessLabLauncher(),
        root: URL? = LabPaths.repositoryRoot(),
        dataRoot: URL? = nil
    ) {
        self.launcher = launcher
        self.root = root
        self.dataRoot = dataRoot ?? LabPaths.dataDirectory()
    }

    func measure(_ config: LabRunConfig, force: Bool = false) {
        guard let root, config.games > 0 else { return }

        if isMeasuring {
            pending = config
            return
        }
        if !force,
           let measuredConfig,
           measuredConfig == config,
           let lastFinished,
           Date().timeIntervalSince(lastFinished) < 300 {
            return
        }

        let parallel = max(1, min(config.parallel, 16))
        let games = max(8, parallel * gamesPerShard)
        let probe = LabRunConfig(
            games: games,
            mode: config.mode,
            depth: config.depth,
            determinizations: config.determinizations,
            parallel: parallel,
            seed: config.seed &+ 7_919
        )
        let logURL = dataRoot
            .appendingPathComponent("probes", isDirectory: true)
            .appendingPathComponent("probe-\(parallel)-\(config.depth)-\(config.determinizations).log")

        isMeasuring = true
        message = nil
        probeGames = games
        probeStart = Date()

        // The probe must not masquerade as a run the owner started: it gets its
        // own run id (filtered out of Recent runs) and overwrites itself each time.
        let probeID = "probe-\(config.mode)-d\(config.depth)x\(config.determinizations)-p\(parallel)-s\(config.seed)"

        do {
            _ = try launcher.launch(
                root: root,
                arguments: probe.arguments + ["--run-id", probeID, "--runs-dir", dataRoot.path, "--restart", "--quiet"],
                logURL: logURL
            ) { [weak self] code in
                Task { @MainActor [weak self] in
                    self?.finish(code: code, config: config, games: games)
                }
            }
        } catch {
            isMeasuring = false
            message = "Could not measure this machine: \(error.localizedDescription)"
        }
    }

    private func finish(code: Int32, config: LabRunConfig, games: Int) {
        let elapsed = max(0.001, Date().timeIntervalSince(probeStart ?? Date()))
        isMeasuring = false
        probeStart = nil

        guard code == 0 else {
            message = "The measurement run did not finish (exit \(code))."
            runPending()
            return
        }

        let rate = Double(games) / elapsed
        lastFinished = Date()
        measuredConfig = config
        estimate = LabWorkloadEstimate(
            rate: rate,
            duration: Double(config.games) / rate,
            shardCount: Int(ceil(Double(config.games) / 5_000.0)),
            outputBytes: Double(config.games) * 1_950.0,
            probeGames: games,
            probeSeconds: elapsed,
            measuredAt: Date()
        )
        runPending()
    }

    private func runPending() {
        guard let pending else { return }
        self.pending = nil
        if pending != measuredConfig {
            measure(pending, force: true)
        }
    }
}
