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
}

struct LabShard: Decodable, Identifiable {
    let index: Int
    let games: Int
    let status: String

    var id: Int { index }
}

/// The subset of `<run>/manifest.json` the UI needs. Decoded with
/// `.convertFromSnakeCase`, which is why the property names are camelCase.
struct LabManifest: Decodable {
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
    let config: Config
    let shards: [LabShard]

    var doneShards: Int { shards.filter { $0.status == "done" }.count }
    var failedShards: Int { shards.filter { $0.status == "failed" }.count }
    var totalGames: Int { shards.reduce(0) { $0 + $1.games } }
    var doneGames: Int { shards.filter { $0.status == "done" }.reduce(0) { $0 + $1.games } }
    var isComplete: Bool { !shards.isEmpty && doneShards == shards.count }
    var fraction: Double {
        totalGames > 0 ? Double(doneGames) / Double(totalGames) : 0
    }

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
        guard let startedAt, let start = ISO8601DateFormatter().date(from: startedAt), doneGames > 0 else {
            return nil
        }
        let elapsed = now.timeIntervalSince(start)
        return elapsed > 1 ? Double(doneGames) / elapsed : nil
    }

    func estimatedRemaining(now: Date = Date()) -> TimeInterval? {
        guard let rate = gamesPerSecond(now: now), rate > 0 else { return nil }
        return TimeInterval(totalGames - doneGames) / rate
    }
}

enum LabPaths {
    /// The app is launched from `build/IsolynV2.0.app`, so neither the working
    /// directory nor `Bundle.main` points at the repository. Walk up from the
    /// executable until the runner appears; this also makes `swift test` work,
    /// where the working directory *is* the package root.
    static func repositoryRoot(fileManager: FileManager = .default) -> URL? {
        if let override = ProcessInfo.processInfo.environment["ISOLYN_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isRepository(url, fileManager: fileManager) { return url }
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
    /// `repositoryRoot` so the app-bundle case
    /// (`build/IsolynV2.0.app/Contents/MacOS`) is testable without a real bundle.
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

    static func runsDirectory(root: URL) -> URL {
        root.appendingPathComponent("lab/data/runs", isDirectory: true)
    }

    static func runDirectory(root: URL, runID: String) -> URL {
        runsDirectory(root: root).appendingPathComponent(runID, isDirectory: true)
    }

    static func manifestURL(root: URL, runID: String) -> URL {
        runDirectory(root: root, runID: runID).appendingPathComponent("manifest.json")
    }

    static func lockURL(root: URL, runID: String) -> URL {
        runDirectory(root: root, runID: runID).appendingPathComponent("run.lock")
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
