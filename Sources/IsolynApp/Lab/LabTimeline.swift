import Foundation
import Observation

/// Holds the test log so the page stays a pure render of it. Separating the
/// scan from the view also lets a test or a preview populate the log without a
/// running app or a timer.
@MainActor
@Observable
final class LabTimelineModel {
    private(set) var entries: [LabTimelineEntry] = []
    private(set) var loaded = false

    nonisolated init() {}

    func load(dataRoot: URL, checkout: URL?) {
        entries = LabTimelineStore.entries(dataRoot: dataRoot, checkout: checkout)
        loaded = true
    }
}

/// What produced one entry in the test log.
enum LabTimelineKind: String, CaseIterable, Identifiable {
    case run
    case probe
    case cloud
    case bench
    case analysis

    var id: String { rawValue }

    var plural: String {
        switch self {
        case .run: return "Runs"
        case .probe: return "Probes"
        case .cloud: return "Cloud"
        case .bench: return "Bench"
        case .analysis: return "Analyses"
        }
    }

    /// Three letters, so a column of them scans vertically without reading.
    var tag: String {
        switch self {
        case .run: return "RUN"
        case .probe: return "PRB"
        case .cloud: return "CLD"
        case .bench: return "BNC"
        case .analysis: return "ANL"
        }
    }
}

enum LabTimelineStatus: String {
    case finished
    case running
    case paused
    case failed
    /// A measurement that has no lifecycle — a bench or an analysis either
    /// exists on disk or it does not.
    case recorded

    var label: String { rawValue }

    var tone: LabStatusPill.Tone {
        switch self {
        case .finished, .recorded: return .finished
        case .running: return .active
        case .paused: return .paused
        case .failed: return .failed
        }
    }
}

/// One test, normalised from whichever on-disk shape produced it.
struct LabTimelineEntry: Identifiable, Equatable {
    struct Fact: Equatable {
        let label: String
        let value: String
    }

    let id: String
    let date: Date?
    let kind: LabTimelineKind
    let title: String
    let subtitle: String
    let facts: [Fact]
    let status: LabTimelineStatus
    let folder: URL?
    /// A bench is dated by its folder name, which names a day but not a minute.
    /// Showing a fabricated clock time would be worse than showing none.
    var hasTime: Bool = true

    /// Search matches the id, the plain sentence and every fact value, so a
    /// search for "64" finds the worlds-per-move runs as well as the run names.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        if title.lowercased().contains(needle) { return true }
        if subtitle.lowercased().contains(needle) { return true }
        return facts.contains { fact in
            fact.label.lowercased().contains(needle)
                || fact.value.lowercased().contains(needle)
        }
    }

    func isKind(_ kind: LabTimelineKind?) -> Bool {
        kind == nil || self.kind == kind
    }
}

/// Reads the test record from disk.
///
/// Two stores exist and both matter: `~/Library/Application Support/…/runs`
/// holds what the app launched, and the checkout's `lab/data` holds what the
/// terminal and the scripts launched. The page shows the union, deduplicated by
/// run id, so "all our tests" is literally all of them.
///
/// Nothing here reads a shard CSV. A manifest is a few hundred bytes; scanning
/// the whole history costs one directory pass and a handful of small JSON
/// reads, which is why the page can refresh on a timer without a spinner.
enum LabTimelineStore {
    static func entries(dataRoot: URL, checkout: URL?) -> [LabTimelineEntry] {
        var found: [LabTimelineEntry] = []
        var seen = Set<String>()

        func add(_ entry: LabTimelineEntry) {
            guard seen.insert(entry.id).inserted else { return }
            found.append(entry)
        }

        // The app's own store.
        scanRuns(in: dataRoot, into: add)
        scanCloud(in: dataRoot.appendingPathComponent("cloud", isDirectory: true), into: add)

        // The checkout's evidence, when the app can see it.
        if let checkout {
            let labData = checkout.appendingPathComponent("lab/data", isDirectory: true)
            scanRuns(in: labData.appendingPathComponent("runs", isDirectory: true), into: add)
            scanBench(in: labData.appendingPathComponent("bench", isDirectory: true), into: add)
            scanAnalyses(in: labData.appendingPathComponent("analyses", isDirectory: true), into: add)
        }

        return found.sorted { left, right in
            switch (left.date, right.date) {
            case let (lhs?, rhs?): return lhs > rhs
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return left.title < right.title
            }
        }
    }

    // MARK: Local runs and probes

    private static func scanRuns(in root: URL, into add: (LabTimelineEntry) -> Void) {
        for directory in subdirectories(of: root) {
            let name = directory.lastPathComponent
            guard name != "cloud", name != "probes" else { continue }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let manifest = decode(Manifest.self, at: manifestURL) else { continue }

            let runID = manifest.runID ?? name
            let config = manifest.config
            let shards = manifest.shards ?? []
            let totalGames = shards.isEmpty
                ? (config?.games ?? 0)
                : shards.reduce(0) { $0 + ($1.games ?? 0) }
            let rows = shards.compactMap(\.rows).reduce(0, +)
            let done = shards.filter { $0.status == "done" }.count
            let failed = shards.filter { $0.status == "failed" }.count
            let running = shards.contains { $0.status == "running" }

            let status: LabTimelineStatus
            if failed > 0 {
                status = .failed
            } else if !shards.isEmpty, done == shards.count {
                status = .finished
            } else if running {
                status = .running
            } else {
                status = .paused
            }

            let kind: LabTimelineKind = runID.hasPrefix("probe-") ? .probe : .run
            let mode = config?.mode ?? "1v1"
            let depth = config?.depth ?? 0
            let worlds = config?.determinizations ?? 0

            var facts: [LabTimelineEntry.Fact] = [
                .init(label: "Games", value: totalGames.formatted()),
            ]
            if rows > 0 {
                facts.append(.init(label: "Decisions", value: rows.formatted()))
            }
            if depth > 0 {
                facts.append(.init(label: "Search", value: "\(depth) × \(worlds)"))
            }
            if let seed = config?.seed {
                facts.append(.init(label: "Seed", value: seed.formatted()))
            }
            if failed > 0 {
                facts.append(.init(label: "Failed", value: "\(failed) of \(shards.count)"))
            }

            let subtitle = kind == .probe
                ? "Timing probe · depth \(depth) · \(worlds) hidden worlds per move"
                : "\(mode) · plans \(depth) moves ahead · weighs \(worlds) hidden hands per move"

            add(
                LabTimelineEntry(
                    id: "run:\(runID)",
                    date: parse(manifest.startedAt) ?? parse(manifest.createdAt) ?? modified(directory),
                    kind: kind,
                    title: runID,
                    subtitle: subtitle,
                    facts: facts,
                    status: status,
                    folder: directory
                )
            )
        }
    }

    // MARK: Cloud sessions

    private static func scanCloud(in root: URL, into add: (LabTimelineEntry) -> Void) {
        for directory in subdirectories(of: root) {
            let runID = directory.lastPathComponent
            let plan = decode(Plan.self, at: directory.appendingPathComponent("plan.json"))
            guard plan != nil || fileExists(directory.appendingPathComponent("sessions", isDirectory: true))
            else { continue }

            let sessions = cloudSessions(in: directory)
            let completed = sessions.filter { $0.status == "complete" }
            let failed = sessions.filter { ($0.error ?? "").isEmpty == false }

            let status: LabTimelineStatus
            if !failed.isEmpty {
                status = .failed
            } else if !sessions.isEmpty, completed.count == sessions.count {
                status = .finished
            } else if sessions.isEmpty {
                status = .paused
            } else {
                status = .running
            }

            let games = completed.isEmpty
                ? (plan?.games ?? 0)
                : completed.reduce(0) { $0 + ($1.totalGames ?? 0) }
            let rows = completed.compactMap(\.totalRows).reduce(0, +)
            let seconds = completed.compactMap(\.durationSeconds).reduce(0, +)

            var facts: [LabTimelineEntry.Fact] = [
                .init(label: "Rounds", value: games.formatted()),
            ]
            if rows > 0 {
                facts.append(.init(label: "Decisions", value: rows.formatted()))
            }
            if seconds > 0 {
                facts.append(.init(label: "Wall", value: duration(seconds)))
            }
            facts.append(.init(label: "Sessions", value: "\(plan?.sessions?.count ?? sessions.count)"))

            let date = completed.compactMap { parse($0.finishedAt) }.max()
                ?? sessions.compactMap { parse($0.createdAt) }.max()
                ?? modified(directory)

            add(
                LabTimelineEntry(
                    id: "cloud:\(runID)",
                    date: date,
                    kind: .cloud,
                    title: runID,
                    subtitle: "Ran on Kaggle · \(status == .finished ? "finished and fetched" : status.label)",
                    facts: facts,
                    status: status,
                    folder: directory
                )
            )
        }
    }

    private static func cloudSessions(in directory: URL) -> [CloudSession] {
        let sessionsRoot = directory.appendingPathComponent("sessions", isDirectory: true)
        return subdirectories(of: sessionsRoot).compactMap {
            decode(CloudSession.self, at: $0.appendingPathComponent("session.json"))
        }
    }

    // MARK: Benchmarks

    private static func scanBench(in root: URL, into add: (LabTimelineEntry) -> Void) {
        for directory in subdirectories(of: root) {
            let name = directory.lastPathComponent
            let config = decode(BenchConfig.self, at: directory.appendingPathComponent("config.json"))
            guard config != nil || fileExists(directory.appendingPathComponent("summary.csv")) else { continue }

            let tiers = config?.tiers ?? []
            var facts: [LabTimelineEntry.Fact] = [
                .init(label: "Tiers", value: "\(tiers.count)"),
            ]
            if let perTier = config?.gamesPerTier {
                facts.append(.init(label: "Per tier", value: perTier.formatted()))
            }
            if let shards = config?.shards {
                facts.append(.init(label: "Shards", value: "\(shards)"))
            }
            if let label = config?.label {
                facts.append(.init(label: "Arm", value: label))
            }

            add(
                LabTimelineEntry(
                    id: "bench:\(name)",
                    date: dateFromPrefix(name) ?? modified(directory),
                    kind: .bench,
                    title: prettyBenchName(name),
                    subtitle: "Throughput ladder · every tier played end to end",
                    facts: facts,
                    status: .recorded,
                    folder: directory,
                    hasTime: false
                )
            )
        }
    }

    // MARK: Calibration analyses

    private static func scanAnalyses(in root: URL, into add: (LabTimelineEntry) -> Void) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for file in files where file.pathExtension == "log" {
            guard let analyses = decode([Analysis].self, at: file), let first = analyses.first else { continue }

            let games = analyses.reduce(0) { $0 + ($1.games ?? 0) }
            let decisions = analyses.reduce(0) { $0 + ($1.decisions ?? 0) }
            let source = first.input.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unrecorded input"

            add(
                LabTimelineEntry(
                    id: "analysis:\(file.lastPathComponent)",
                    date: modified(file),
                    kind: .analysis,
                    title: source,
                    subtitle: "Calibration report · \(analyses.count) input\(analyses.count == 1 ? "" : "s")",
                    facts: [
                        .init(label: "Games", value: games.formatted()),
                        .init(label: "Decisions", value: decisions.formatted()),
                        .init(label: "Mode", value: first.mode ?? "—"),
                    ],
                    status: .recorded,
                    folder: file
                )
            )
        }
    }

    // MARK: Decoding shapes

    /// Every field is optional on purpose: a manifest written by an older
    /// harness must still appear in the log rather than vanish from it.
    private struct Manifest: Decodable {
        struct Config: Decodable {
            let games: Int?
            let mode: String?
            let depth: Int?
            let determinizations: Int?
            let seed: Int?
        }

        struct Shard: Decodable {
            let games: Int?
            let status: String?
            let rows: Int?
        }

        let runID: String?
        let createdAt: String?
        let startedAt: String?
        let config: Config?
        let shards: [Shard]?
    }

    private struct Plan: Decodable {
        struct Session: Decodable {
            let id: String?
            let games: Int?
        }

        let games: Int?
        let sessions: [Session]?
    }

    private struct CloudSession: Decodable {
        let status: String?
        let totalGames: Int?
        let totalRows: Int?
        let durationSeconds: Double?
        let createdAt: String?
        let finishedAt: String?
        let error: String?
    }

    private struct BenchConfig: Decodable {
        struct Tier: Decodable {
            let tier: String?
        }

        let label: String?
        let gamesPerTier: Int?
        let shards: Int?
        let tiers: [Tier]?
    }

    private struct Analysis: Decodable {
        let input: String?
        let mode: String?
        let games: Int?
        let decisions: Int?
    }

    // MARK: Helpers

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(T.self, from: data)
    }

    private static func subdirectories(of root: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    /// `2026-11-15-tt-baseline` → a date, and the rest becomes the title.
    private static func dateFromPrefix(_ name: String) -> Date? {
        let parts = name.split(separator: "-", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (2000...2100).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    private static func prettyBenchName(_ name: String) -> String {
        let parts = name.split(separator: "-", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return name }
        return String(parts[3]).replacingOccurrences(of: "-", with: " ")
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0f s", seconds) }
        if seconds < 3_600 { return String(format: "%.1f min", seconds / 60) }
        return String(format: "%.1f h", seconds / 3_600)
    }
}
