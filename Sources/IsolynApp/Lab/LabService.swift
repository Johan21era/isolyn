import AppKit
import Darwin
import Foundation
import Observation

/// A launched child, abstracted so the service's one-run-at-a-time logic can be
/// tested without spawning anything.
protocol LabProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol LabLaunching {
    func launch(
        root: URL,
        arguments: [String],
        logURL: URL,
        onExit: @escaping (Int32) -> Void
    ) throws -> LabProcessHandle
}

final class ProcessLabLauncher: LabLaunching {
    private final class Handle: LabProcessHandle {
        private let process: Process
        init(_ process: Process) { self.process = process }
        var isRunning: Bool { process.isRunning }
        func terminate() { process.terminate() }
    }

    func launch(
        root: URL,
        arguments: [String],
        logURL: URL,
        onExit: @escaping (Int32) -> Void
    ) throws -> LabProcessHandle {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        try log.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // The shell script sets PYTHONPATH and dispatches to the runner, so the
        // app never needs to know where the Python package lives.
        process.arguments = ["scripts/lab"] + arguments
        process.currentDirectoryURL = root
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        process.terminationHandler = { finished in
            try? log.close()
            onExit(finished.terminationStatus)
        }
        try process.run()
        return Handle(process)
    }
}

/// Owns the single lab child process the app is allowed to have.
///
/// Repeated Start presses are the failure mode this exists to prevent: the
/// guard rejects a second launch while one is active, ignores a repeat of the
/// same configuration inside a short window (double-clicks, key repeat), and the
/// runner's own `run.lock` is the final backstop if another session beat us to
/// it. Nothing here can spawn an unbounded number of processes.
@MainActor
@Observable
final class LabService {
    enum Phase: Equatable {
        case idle
        case launching
        case running
        case finished
        case stopped
        case failed(String)

        var isBusy: Bool { self == .launching || self == .running }
    }

    private(set) var phase: Phase = .idle
    private(set) var config = LabRunConfig()
    private(set) var manifest: LabManifest?
    private(set) var message: String?
    private(set) var logTail: String?
    private(set) var startedAt: Date?

    var draft = LabRunConfig()

    let root: URL?
    private let launcher: LabLaunching
    private var handle: LabProcessHandle?
    private var pollTask: Task<Void, Never>?
    private var lastAttempt: (config: LabRunConfig, date: Date)?

    /// A second Start for the same run inside this window is treated as noise.
    private let repeatWindow: TimeInterval = 2.0

    init(launcher: LabLaunching = ProcessLabLauncher(), root: URL? = LabPaths.repositoryRoot()) {
        self.launcher = launcher
        self.root = root
        self.config = draft
    }

    // MARK: - Derived state

    var isBusy: Bool { phase.isBusy }

    var harnessBuilt: Bool {
        guard let root else { return false }
        return FileManager.default.fileExists(
            atPath: root.appendingPathComponent("tools/selfplay/build/selfplay").path
        )
    }

    var progress: Double { manifest?.fraction ?? 0 }

    var statusTitle: String {
        switch phase {
        case .idle: return "No run started"
        case .launching: return "Starting…"
        case .running: return manifest.map { "\($0.doneShards)/\($0.shards.count) shards" } ?? "Starting…"
        case .finished: return "Complete"
        case .stopped: return "Stopped — progress kept"
        case .failed: return "Needs attention"
        }
    }

    // MARK: - Run control

    func start() { start(draft) }

    func start(_ requested: LabRunConfig) {
        if !isBusy, let last = lastAttempt, last.config == requested,
           Date().timeIntervalSince(last.date) < repeatWindow {
            message = "That run was just started; it is already running."
            return
        }
        if isBusy {
            message = requested.runID == config.runID
                ? "That run is already active."
                : "One run at a time — stop the active run first."
            return
        }
        guard requested.games > 0 else {
            phase = .failed("Choose at least one game.")
            return
        }
        guard LabPaths.isSafeRunID(requested.runID) else {
            phase = .failed("That configuration produces an invalid run id.")
            return
        }
        guard let root else {
            phase = .failed(
                "Repository not found. Launch the app from the Isolyn folder, or set ISOLYN_ROOT."
            )
            return
        }
        guard harnessBuilt else {
            phase = .failed("The self-play harness is not built yet. Run ./tools/selfplay/build.sh.")
            return
        }

        lastAttempt = (requested, Date())
        draft = requested
        config = requested
        manifest = nil
        message = nil
        logTail = nil
        phase = .launching
        startedAt = Date()

        do {
            let logURL = LabPaths.runDirectory(root: root, runID: requested.runID)
                .appendingPathComponent("runner.log")
            handle = try launcher.launch(root: root, arguments: requested.arguments, logURL: logURL) { [weak self] code in
                Task { @MainActor [weak self] in self?.finish(code: code) }
            }
            phase = .running
            refresh()
            startPolling()
        } catch {
            handle = nil
            phase = .failed("Could not start the runner: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isBusy else { return }
        phase = .stopped
        message = "Stopping… unfinished shards are kept."
        if let handle, handle.isRunning {
            handle.terminate()
        } else if let root {
            terminateRecordedRunner(root: root)
        }
    }

    /// A run left behind by an earlier app session: show it, and allow Stop
    /// without ever claiming a handle we do not have.
    func attachToActiveRun() {
        guard !isBusy, let root else { return }
        for candidate in recentRuns() where !candidate.isComplete {
            if let pid = recordedRunnerPID(root: root, runID: candidate.runId), processLooksLikeRunner(pid) {
                config = candidate.runConfig
                draft = config
                manifest = candidate
                phase = .running
                message = "This run is already active (pid \(pid))."
                startPolling()
                return
            }
        }
    }

    func refresh() {
        guard let root else { return }
        guard let decoded = loadManifest(root: root, runID: config.runID) else { return }
        manifest = decoded
        if decoded.isComplete, phase == .running, handle == nil {
            phase = .finished
            stopPolling()
        }
    }

    // MARK: - Other run actions

    func recentRuns(limit: Int = 6) -> [LabManifest] {
        guard let root else { return [] }
        let directory = LabPaths.runsDirectory(root: root)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifests = entries.compactMap { entry -> LabManifest? in
            let url = entry.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(LabManifest.self, from: data)
        }
        return Array(
            manifests
                // Warm-up probes are measurements, not runs the owner asked for.
                .filter { !$0.runId.hasPrefix("probe-") }
                .sorted { ($0.startedAt ?? $0.createdAt) > ($1.startedAt ?? $1.createdAt) }
                .prefix(limit)
        )
    }

    func merge(runID: String) {
        guard !isBusy else {
            message = "Stop the active run before merging."
            return
        }
        guard let root else { return }
        guard LabPaths.isSafeRunID(runID) else { return }
        guard let manifest = loadManifest(root: root, runID: runID), manifest.isComplete else {
            message = "Only a finished run can be merged."
            return
        }
        message = "Merging \(runID)…"
        let logURL = LabPaths.runDirectory(root: root, runID: runID)
            .appendingPathComponent("merge.log")
        do {
            _ = try launcher.launch(root: root, arguments: ["merge", runID], logURL: logURL) { [weak self] code in
                Task { @MainActor [weak self] in
                    self?.message = code == 0 ? "Merged \(runID) into merged.csv." : "Merge failed (exit \(code))."
                }
            }
        } catch {
            message = "Could not merge: \(error.localizedDescription)"
        }
    }

    func reveal(runID: String) {
        guard let root else { return }
        let directory = LabPaths.runDirectory(root: root, runID: runID)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    // MARK: - Private

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func finish(code: Int32) {
        handle = nil
        stopPolling()
        refresh()
        switch phase {
        case .stopped:
            message = "Stopped. Unfinished shards are kept and will resume."
        case .failed:
            break
        default:
            if manifest?.isComplete == true || code == 0 {
                phase = .finished
                message = "Run complete."
            } else if code == 130 || code == 143 {
                phase = .stopped
                message = "Interrupted. Run the same configuration to resume."
            } else {
                logTail = readLogTail(root: root, runID: config.runID)
                phase = .failed("Runner exited with code \(code).")
            }
        }
    }

    private func loadManifest(root: URL, runID: String) -> LabManifest? {
        guard LabPaths.isSafeRunID(runID) else { return nil }
        let url = LabPaths.manifestURL(root: root, runID: runID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(LabManifest.self, from: data)
    }

    private func readLogTail(root: URL?, runID: String) -> String? {
        guard let root else { return nil }
        let url = LabPaths.runDirectory(root: root, runID: runID)
            .appendingPathComponent("runner.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let tail = text.suffix(600)
        return tail.isEmpty ? nil : String(tail)
    }

    private func recordedRunnerPID(root: URL, runID: String) -> pid_t? {
        let url = LabPaths.lockURL(root: root, runID: runID)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return pid > 0 ? pid : nil
    }

    private func processLooksLikeRunner(_ pid: pid_t) -> Bool {
        guard kill(pid, 0) == 0 else { return false }
        return commandName(of: pid)?.lowercased().contains("python") == true
    }

    private func commandName(of pid: pid_t) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "comm=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func terminateRecordedRunner(root: URL) {
        guard let pid = recordedRunnerPID(root: root, runID: config.runID),
              processLooksLikeRunner(pid) else {
            return
        }
        kill(pid, SIGTERM)
    }
}
