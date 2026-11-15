import AppKit
import Foundation
import Observation

/// The provenance file written by `run.sh` when it stages the cloud source.
/// The app displays it; the Python driver re-checks the digest before planning
/// or preparing an upload.
struct LabCloudSource: Decodable {
    struct File: Decodable {
        let path: String
        let bytes: Int
        let sha256: String
    }

    let sourceCommit: String?
    let clean: Bool
    let codeSha256: String
    let files: [File]
    let stagedAt: String?

    var commitShort: String {
        guard let sourceCommit, !sourceCommit.isEmpty else { return "no commit" }
        return String(sourceCommit.prefix(12))
    }
}

struct LabCloudPlan: Decodable {
    struct Session: Decodable {
        let id: String
        let games: Int
    }

    struct Shard: Decodable {
        let index: Int
        let games: Int
    }

    let runId: String
    let games: Int
    let sessionGames: Int
    let sourceCommit: String
    let codeSha256: String
    let sessions: [Session]
    let shards: [Shard]
}

struct LabCloudLedger: Decodable {
    struct Entry: Decodable {
        let pushedAt: String?
        let fetchedAt: String?
        let verifiedAt: String?
        let datasetUploadedAt: String?
    }

    let sessions: [String: Entry]
}

/// Owns the app's one cloud child process and the fixed first-run calibration
/// sequence: plan → prepare → upload → collect. The Kaggle token is never read
/// by the app; the installed `kaggle` CLI reads its normal per-user config.
@MainActor
@Observable
final class LabCloudService {
    enum Phase: Equatable {
        case idle
        case planning
        case preparing
        case uploading
        case waiting
        case collecting
        case finished
        case stopped
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .planning, .preparing, .uploading, .collecting: return true
            case .idle, .waiting, .finished, .stopped, .failed: return false
            }
        }
    }

    private enum Step {
        case plan
        case prepare
        case push
        case collect

        var title: String {
            switch self {
            case .plan: return "Planning"
            case .prepare: return "Preparing the private snapshot"
            case .push: return "Uploading to Kaggle"
            case .collect: return "Fetching and verifying"
            }
        }

        var logName: String {
            switch self {
            case .plan: return "cloud-plan.log"
            case .prepare: return "cloud-prepare.log"
            case .push: return "cloud-push.log"
            case .collect: return "cloud-collect.log"
            }
        }
    }

    private static let ownerKey = "isolyn.cloud.owner"

    /// The acceptance run is deliberately fixed. It is one session, not a
    /// five-million-game corpus, so a first external failure is cheap to
    /// diagnose and cannot be mistaken for a full training run.
    let games = 10_000
    let gamesPerShard = 2_500
    let sessionGames = 10_000
    let runID = "cloud-1v1-d8x64-n10000-s1"

    private(set) var phase: Phase = .idle
    private(set) var source: LabCloudSource?
    private(set) var plan: LabCloudPlan?
    private(set) var ledger: LabCloudLedger?
    private(set) var assembled = false
    private(set) var message: String?
    private(set) var logTail: String?
    private(set) var lastLogURL: URL?

    var owner: String {
        didSet {
            UserDefaults.standard.set(owner, forKey: Self.ownerKey)
        }
    }

    let root: URL?
    let dataRoot: URL
    let cloudRoot: URL
    private let launcher: LabLaunching
    private var handle: LabProcessHandle?
    private var token: UUID?

    init(
        launcher: LabLaunching = ProcessLabLauncher(),
        root: URL? = LabPaths.repositoryRoot(),
        dataRoot: URL? = nil
    ) {
        self.launcher = launcher
        self.root = root
        self.dataRoot = dataRoot ?? LabPaths.dataDirectory()
        self.cloudRoot = LabPaths.cloudDirectory(dataRoot: self.dataRoot)
        self.owner = UserDefaults.standard.string(forKey: Self.ownerKey) ?? ""
        refresh()
    }

    // MARK: - Derived state

    var isBusy: Bool { phase.isBusy }

    var sourceReady: Bool {
        source?.clean == true && source?.sourceCommit?.count == 40
    }

    var canStart: Bool {
        !isBusy && !assembled && sourceReady
            && !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCollect: Bool {
        !isBusy && hasPushed && !assembled
    }

    var hasPushed: Bool {
        guard let plan, let ledger, let session = plan.sessions.first else { return false }
        return ledger.sessions[session.id]?.pushedAt != nil
    }

    var isPrepared: Bool {
        guard let plan, let session = plan.sessions.first else { return false }
        let dataset = runDirectory.appendingPathComponent("dataset/dataset-metadata.json")
        let kernel = runDirectory.appendingPathComponent("kernels/\(session.id)/kernel-metadata.json")
        return FileManager.default.fileExists(atPath: dataset.path)
            && FileManager.default.fileExists(atPath: kernel.path)
    }

    var planMatchesSource: Bool {
        guard let plan, let source else { return false }
        return plan.sourceCommit == source.sourceCommit
            && plan.codeSha256 == source.codeSha256
    }

    var hasVerified: Bool {
        guard let plan, let ledger, let session = plan.sessions.first else { return false }
        return ledger.sessions[session.id]?.verifiedAt != nil
    }

    var runDirectory: URL {
        cloudRoot.appendingPathComponent(runID, isDirectory: true)
    }

    var statusTitle: String {
        switch phase {
        case .idle: return "No cloud run yet"
        case .planning: return "Planning the 10,000-game run…"
        case .preparing: return "Preparing the private snapshot…"
        case .uploading: return "Uploading the private snapshot…"
        case .waiting: return hasPushed ? "Uploaded — waiting for Kaggle" : "Nothing uploaded"
        case .collecting: return "Fetching and verifying the result…"
        case .finished: return "Verified and assembled"
        case .stopped: return "Stopped"
        case .failed: return "Needs attention"
        }
    }

    var sourceSummary: String {
        guard let source else { return "No staged source bundle. Run ./run.sh to stage one." }
        return "\(source.files.count) allowlisted files · commit \(source.commitShort) · \(source.clean ? "clean" : "DIRTY")"
    }

    var planSummary: String {
        if let plan {
            return "\(plan.games.formatted()) games · \(plan.shards.count) shards · \(plan.sessions.count) session"
        }
        return "\(games.formatted()) games · \(gamesPerShard.formatted())-game shards · one session"
    }

    var resultSummary: String {
        if assembled {
            return "The verified CSV is in the cloud run folder, beside its SHA-256 summary."
        }
        if hasVerified {
            return "The downloaded session is verified. Press Collect to fetch and assemble anything still outstanding."
        }
        if hasPushed {
            return "Kaggle has the notebook. Come back after it finishes and press Collect results."
        }
        return "Nothing is uploaded until you confirm the private upload."
    }

    // MARK: - Actions

    /// Called only after the view's explicit upload confirmation.
    func start() {
        guard !isBusy else {
            message = "One cloud action at a time."
            return
        }
        guard !assembled else {
            message = "This calibration run is already assembled."
            return
        }
        guard let root else {
            phase = .failed("The staged Lab runtime was not found. Run ./run.sh first.")
            return
        }
        refresh()
        guard let source else {
            phase = .failed("No source bundle was staged. Run ./run.sh from the checkout.")
            return
        }
        guard source.clean else {
            phase = .failed("The staged source is dirty. Commit the checkout and run ./run.sh again.")
            return
        }
        guard source.sourceCommit?.count == 40 else {
            phase = .failed("The staged source has no commit. Rebuild ./run.sh from a Git checkout.")
            return
        }
        guard !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed("Enter your Kaggle owner name first.")
            return
        }

        if hasPushed {
            phase = .waiting
            message = "This calibration run is already uploaded. Press Collect results when Kaggle finishes."
            return
        }
        if isPrepared, planMatchesSource {
            // A previous push may have failed after prepare. The prepared
            // snapshot is still the planned, verified source; retry the
            // external upload instead of refusing to overwrite the dataset.
            message = nil
            phase = .uploading
            launch(.push, root: root)
            return
        }

        message = nil
        logTail = nil
        lastLogURL = nil
        phase = .planning
        launch(.plan, root: root)
    }

    /// Fetch, verify, and assemble only after Kaggle reports completion.
    func collect() {
        guard !isBusy else { return }
        guard hasPushed else {
            message = "Upload the calibration run before collecting it."
            return
        }
        guard !assembled else {
            message = "This run is already assembled."
            return
        }
        guard let root else { return }
        message = nil
        logTail = nil
        phase = .collecting
        launch(.collect, root: root)
    }

    func refresh() {
        guard let root else { return }
        source = decode(LabCloudSource.self, at: root.appendingPathComponent("source.json"))
        plan = decode(LabCloudPlan.self, at: runDirectory.appendingPathComponent("plan.json"))
        ledger = decode(LabCloudLedger.self, at: runDirectory.appendingPathComponent("ledger.json"))
        assembled = FileManager.default.fileExists(
            atPath: runDirectory.appendingPathComponent("assembled.csv").path
        )
        if assembled, phase == .waiting {
            phase = .finished
            message = "The verified CSV is ready."
        }
    }

    func openLog() {
        let url = lastLogURL
            ?? runDirectory.appendingPathComponent(Step.plan.logName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            message = "No cloud log exists yet."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([runDirectory])
    }

    // MARK: - Child process

    private func arguments(for step: Step) -> [String] {
        switch step {
        case .plan:
            return [
                "cloud", "plan",
                "--games", String(games),
                "--games-per-shard", String(gamesPerShard),
                "--session-games", String(sessionGames),
                "--parallel", "4",
                "--workers", "1",
                "--mode", "1v1",
                "--depth", "8",
                "--determinizations", "64",
                "--seed", "1",
                "--run-id", runID,
                "--owner", owner.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
        case .prepare:
            return ["cloud", "prepare", runID]
        case .push:
            // `--yes` is the app's explicit confirmation gate. The code never
            // gets here without the owner pressing the upload button first.
            return ["cloud", "push", runID, "--session", "0000", "--yes"]
        case .collect:
            return ["cloud", "collect", runID, "--session", "0000"]
        }
    }

    private func launch(_ step: Step, root: URL) {
        let logURL = runDirectory.appendingPathComponent(step.logName)
        do {
            try FileManager.default.createDirectory(
                at: runDirectory,
                withIntermediateDirectories: true
            )
            let token = UUID()
            self.token = token
            self.lastLogURL = logURL
            handle = try launcher.launch(
                root: root,
                arguments: arguments(for: step),
                logURL: logURL,
                environment: ["ISOLYN_CLOUD_DIR": cloudRoot.path]
            ) { [weak self] code in
                Task { @MainActor [weak self] in
                    self?.finish(step: step, code: code, token: token)
                }
            }
        } catch {
            handle = nil
            token = nil
            phase = .failed("Could not start the cloud command: \(error.localizedDescription)")
        }
    }

    private func finish(step: Step, code: Int32, token: UUID) {
        guard token == self.token else { return }
        handle = nil
        self.token = nil
        refresh()
        guard code == 0 else {
            logTail = readLogTail()
            phase = .failed("\(step.title) failed (exit \(code)).")
            return
        }

        switch step {
        case .plan:
            phase = .preparing
            if let root { launch(.prepare, root: root) }
        case .prepare:
            phase = .uploading
            if let root { launch(.push, root: root) }
        case .push:
            phase = .waiting
            message = "Uploaded privately. Kaggle is running the CPU-only notebook; press Collect results when it finishes."
            refresh()
        case .collect:
            phase = .finished
            message = "Verified and assembled the 10,000-game result."
            refresh()
        }
    }

    private func readLogTail() -> String? {
        guard let url = lastLogURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let tail = text.suffix(1_200)
        return tail.isEmpty ? nil : String(tail)
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(type, from: data)
    }
}
