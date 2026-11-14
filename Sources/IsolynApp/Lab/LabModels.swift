import Foundation

/// One sharded run's configuration, mirroring the flags `scripts/lab run`
/// accepts. `runID` is derived the same way the runner derives it, so pressing
/// Start twice targets the same run directory instead of creating a second one.
struct LabRunConfig: Equatable, Codable {
    var games: Int = 5_000_000
    var mode: String = "1v1"
    var depth: Int = 8
    var determinizations: Int = 64
    var parallel: Int = min(8, ProcessInfo.processInfo.activeProcessorCount)
    var seed: Int = 1

    var runID: String {
        "\(mode)-d\(depth)x\(determinizations)-n\(games)-s\(seed)"
    }

    var arguments: [String] {
        [
            "run",
            "--games", String(games),
            "--mode", mode,
            "--depth", String(depth),
            "--determinizations", String(determinizations),
            "--parallel", String(parallel),
            "--seed", String(seed),
            "--run-id", runID,
        ]
    }

    var searchSummary: String {
        "\(mode) · \(depth) moves · \(determinizations) worlds"
    }
}

enum LabRunSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case largest = "Largest"

    var id: String { rawValue }
}

enum LabRunFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unfinished = "Unfinished"
    case finished = "Finished"

    var id: String { rawValue }
}

struct LabShard: Decodable, Identifiable {
    let index: Int
    let games: Int
    let status: String
    let rows: Int?
    let reason: String?

    var id: Int { index }
}

/// One run's manifest. Parsed once: `startedDate` is decoded here rather than
/// re-parsed by every view that wants to show a rate or an estimate.
struct LabManifest: Decodable, Identifiable {
    struct Config: Decodable {
        let games: Int
        let mode: String
        let depth: Int
        let determinizations: Int
        let seed: Int
    }

    let runId: String
    let createdAt: String
    let startedAt: String?
    let startedDate: Date?
    let config: Config
    let shards: [LabShard]

    var id: String { runId }

    private enum CodingKeys: String, CodingKey {
        case runId, createdAt, startedAt, config, shards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try container.decode(String.self, forKey: .runId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        config = try container.decode(Config.self, forKey: .config)
        shards = try container.decode([LabShard].self, forKey: .shards)
        startedDate = Self.parse(startedAt) ?? Self.parse(createdAt)
    }

    private static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    var doneShards: Int { shards.filter { $0.status == "done" }.count }
    var failedShards: Int { shards.filter { $0.status == "failed" }.count }
    var totalGames: Int { shards.reduce(0) { $0 + $1.games } }
    var doneGames: Int { shards.filter { $0.status == "done" }.reduce(0) { $0 + $1.games } }
    var isComplete: Bool { !shards.isEmpty && doneShards == shards.count }
    var fraction: Double { totalGames > 0 ? Double(doneGames) / Double(totalGames) : 0 }
    var rowCount: Int { shards.compactMap(\.rows).reduce(0, +) }

    var runConfig: LabRunConfig {
        LabRunConfig(
            games: config.games,
            mode: config.mode,
            depth: config.depth,
            determinizations: config.determinizations,
            parallel: min(8, ProcessInfo.processInfo.activeProcessorCount),
            seed: config.seed
        )
    }

    func gamesPerSecond(now: Date = Date()) -> Double? {
        guard let startedDate, doneGames > 0 else { return nil }
        let elapsed = now.timeIntervalSince(startedDate)
        return elapsed > 1 ? Double(doneGames) / elapsed : nil
    }

    func estimatedRemaining(now: Date = Date()) -> TimeInterval? {
        guard let rate = gamesPerSecond(now: now), rate > 0, !isComplete else { return nil }
        return TimeInterval(totalGames - doneGames) / rate
    }

    func estimatedFinish(now: Date = Date()) -> Date? {
        guard let remaining = estimatedRemaining(now: now) else { return nil }
        return now.addingTimeInterval(remaining)
    }

    /// Short, human line: "0/18 batches · 1v1 · 8 moves".
    var summaryLine: String {
        "\(doneGames) of \(totalGames) games · \(config.mode) · \(config.depth) moves · \(config.determinizations) worlds"
    }
}

enum LabPaths {
    /// The app is launched from `build/IsolynV2.0.app`, so neither the working
    /// directory nor `Bundle.main` points at the repository. The staged runtime
    /// in Application Support is preferred; walking up from the executable
    /// remains the fallback for `swift test` and terminal use.
    static func repositoryRoot(fileManager: FileManager = .default) -> URL? {
        if let override = ProcessInfo.processInfo.environment["ISOLYN_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isRepository(url, fileManager: fileManager) { return url }
        }
        if let staged = stagedRuntime(fileManager: fileManager) {
            return staged
        }

        var starts: [URL] = []
        if let executable = Bundle.main.executableURL {
            starts.append(executable.deletingLastPathComponent())
        }
        starts.append(Bundle.main.bundleURL)
        starts.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))

        for start in starts {
            if let found = findRoot(startingAt: start, fileManager: fileManager) { return found }
        }
        return nil
    }

    /// Walks up from an executable's directory. Split out from
    /// `repositoryRoot` so the app-bundle case is testable without a real bundle.
    static func findRoot(startingAt start: URL, fileManager: FileManager = .default) -> URL? {
        var directory = start
        for _ in 0..<8 {
            if isRepository(directory, fileManager: fileManager) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    static func isRepository(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let marker = url.appendingPathComponent("lab/src/isolyn_lab/runner.py")
        return fileManager.fileExists(atPath: marker.path)
    }

    static func applicationSupport(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("IsolynV2.0", isDirectory: true)
    }

    static func stagedRuntime(fileManager: FileManager = .default) -> URL? {
        let staged = applicationSupport(fileManager: fileManager)
            .appendingPathComponent("Lab", isDirectory: true)
        return isRepository(staged, fileManager: fileManager) ? staged : nil
    }

    /// Where the app keeps its run data. Application Support is not a
    /// TCC-protected location, so a rebuilt (re-signed) app keeps working
    /// without asking for permission again.
    static func dataDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["ISOLYN_RUNS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return applicationSupport(fileManager: fileManager)
            .appendingPathComponent("runs", isDirectory: true)
    }

    static func runsDirectory(dataRoot: URL) -> URL { dataRoot }

    static func runDirectory(dataRoot: URL, runID: String) -> URL {
        dataRoot.appendingPathComponent(runID, isDirectory: true)
    }

    static func manifestURL(dataRoot: URL, runID: String) -> URL {
        runDirectory(dataRoot: dataRoot, runID: runID).appendingPathComponent("manifest.json")
    }

    static func lockURL(dataRoot: URL, runID: String) -> URL {
        runDirectory(dataRoot: dataRoot, runID: runID).appendingPathComponent("run.lock")
    }

    /// Run ids become directory names, so anything that could escape the runs
    /// folder (`/`, `..`) is refused rather than passed to the filesystem.
    static func isSafeRunID(_ runID: String) -> Bool {
        guard !runID.isEmpty, runID.count <= 81 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return runID.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !runID.hasPrefix(".")
            && !runID.contains("..")
    }
}
