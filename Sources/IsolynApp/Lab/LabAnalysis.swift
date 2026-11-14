import Foundation
import Observation

struct LabSearchConfig: Decodable {
    let depth: Int
    let determinizations: Int
}

struct LabParticipantReport: Decodable, Identifiable {
    let label: String
    let games: Int
    let wins: Int
    let winRate: Double
    let winLow: Double
    let winHigh: Double
    let averagePoints: Double
    let averageInitialPips: Double

    var id: String { label }
}

struct LabEloReport: Decodable {
    let aVsB: Double?
    let low: Double?
    let high: Double?
    let games: Int
    let scoreA: Double
}

struct LabSpearmanReport: Decodable {
    let initialVsPoints: Double?
    let initialVsWin: Double?
    let samples: Int
}

/// One calibration report, decoded from `isolyn-lab evaluate --json`.
struct LabAnalysisReport: Decodable, Identifiable {
    let input: String?
    let mode: String
    let games: Int
    let decisions: Int
    let outcomes: [String: Int]
    let configA: LabSearchConfig
    let configB: LabSearchConfig
    let participants: [LabParticipantReport]
    let sides: [LabParticipantReport]
    let spearman: LabSpearmanReport
    let elo: LabEloReport?

    var id: String { input ?? "\(mode)-\(games)-\(decisions)" }

    var displayName: String {
        guard let input, !input.isEmpty else { return mode }
        return (input as NSString).lastPathComponent
    }

    var isSymmetric: Bool {
        configA.depth == configB.depth
            && configA.determinizations == configB.determinizations
    }

    var outcomeSummary: String {
        outcomes
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " · ")
    }
}

/// Runs several calibration analyses in one child process.
///
/// The analysis is read-only: it reads finished CSVs and never touches a run in
/// progress. Overlapping requests are refused for the same reason run launches
/// are — a repeated press should not queue a second process.
@MainActor
@Observable
final class LabAnalysisService {
    private(set) var isRunning = false
    private(set) var reports: [LabAnalysisReport] = []
    private(set) var message: String?
    private(set) var lastError: String?

    let root: URL?
    let dataRoot: URL
    private let launcher: LabLaunching
    private var handle: LabProcessHandle?
    private var lastInputs: [String] = []
    private var lastStarted: Date?
    /// Listing a run directory per row per redraw is wasted work. The cache is
    /// keyed on the directory's modification stamp, so a merge or a new shard
    /// invalidates it immediately instead of after a timeout.
    private var inputCache: [String: (urls: [URL], stamp: Date?)] = [:]
    private let repeatWindow: TimeInterval = 1.5

    /// A command line has limits and a report per shard stops being useful long
    /// before this; 20 is the point where the screen stays readable.
    let maxInputs = 20

    init(
        launcher: LabLaunching = ProcessLabLauncher(),
        root: URL? = LabPaths.repositoryRoot(),
        dataRoot: URL? = nil
    ) {
        self.launcher = launcher
        self.root = root
        self.dataRoot = dataRoot ?? LabPaths.dataDirectory()
    }

    /// A finished run's `merged.csv` if it has one, otherwise up to eight of its
    /// shard CSVs. Unmerged shards are legitimate separate analyses — each file
    /// carries its own game ids.
    func inputs(for runID: String) -> [URL] {
        let stamp = directoryStamp(for: runID)
        if let hit = inputCache[runID], hit.stamp == stamp {
            return hit.urls
        }
        let urls = readInputs(for: runID)
        inputCache[runID] = (urls, stamp)
        return urls
    }

    private func directoryStamp(for runID: String) -> Date? {
        guard LabPaths.isSafeRunID(runID) else { return nil }
        let directory = LabPaths.runDirectory(dataRoot: dataRoot, runID: runID)
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        return attributes?[.modificationDate] as? Date
    }

    private func readInputs(for runID: String) -> [URL] {
        guard LabPaths.isSafeRunID(runID) else { return [] }
        let directory = LabPaths.runDirectory(dataRoot: dataRoot, runID: runID)
        let merged = directory.appendingPathComponent("merged.csv")
        if FileManager.default.fileExists(atPath: merged.path) { return [merged] }

        let shards = directory.appendingPathComponent("shards", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: shards,
            includingPropertiesForKeys: nil
        )) ?? []
        let csv = files
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return Array(csv.prefix(8))
    }

    func run(inputs: [URL]) {
        guard !isRunning else {
            message = "An analysis is already running."
            return
        }
        guard let root else {
            message = "Repository not found."
            return
        }

        var unique: [URL] = []
        var seen = Set<String>()
        for url in inputs where seen.insert(url.path).inserted { unique.append(url) }
        guard !unique.isEmpty else {
            message = "Select at least one finished run."
            return
        }
        let capped = Array(unique.prefix(maxInputs))
        let paths = capped.map(\.path)

        if let lastStarted, lastInputs == paths,
           Date().timeIntervalSince(lastStarted) < repeatWindow {
            message = "That analysis was just started."
            return
        }

        let logURL = dataRoot
            .appendingPathComponent("analyses", isDirectory: true)
            .appendingPathComponent("analysis-\(Int(Date().timeIntervalSince1970)).log")
        let arguments = ["evaluate", "--json"]
            + capped.flatMap { ["--input", $0.path] }

        lastStarted = Date()
        lastInputs = paths
        isRunning = true
        message = "Analyzing \(capped.count) input\(capped.count == 1 ? "" : "s")…"
        lastError = nil

        do {
            handle = try launcher.launch(root: root, arguments: arguments, logURL: logURL) { [weak self] code in
                Task { @MainActor [weak self] in self?.finish(code: code, logURL: logURL) }
            }
        } catch {
            isRunning = false
            message = "Could not start the analysis: \(error.localizedDescription)"
        }
    }

    private func finish(code: Int32, logURL: URL) {
        isRunning = false
        handle = nil
        guard code == 0 else {
            lastError = readTail(logURL)
            message = "Analysis failed (exit \(code))."
            return
        }
        guard let data = try? Data(contentsOf: logURL) else {
            message = "No analysis output was written."
            return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            reports = try decoder.decode([LabAnalysisReport].self, from: data)
            message = "\(reports.count) report\(reports.count == 1 ? "" : "s") ready."
        } catch {
            lastError = readTail(logURL)
            message = "Analysis output could not be read."
        }
    }

    private func readTail(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let tail = text.suffix(400)
        return tail.isEmpty ? nil : String(tail)
    }
}
