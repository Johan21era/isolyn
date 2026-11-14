import SwiftUI
import XCTest
@testable import IsolynApp

/// The failure this guards against is a person leaning on the Start button: the
/// app must not spawn a process per press, must not lose track of the run it
/// owns, and must not pretend a stopped run failed.
@MainActor
final class LabServiceTests: XCTestCase {

    // MARK: - Doubles

    final class FakeHandle: LabProcessHandle {
        var isRunning = true
        private(set) var terminated = false
        func terminate() {
            terminated = true
            isRunning = false
        }
    }

    final class FakeLauncher: LabLaunching {
        private(set) var launches: [([String], URL)] = []
        private(set) var handlers: [(Int32) -> Void] = []
        private(set) var lastHandle: FakeHandle?

        func launch(
            root: URL,
            arguments: [String],
            logURL: URL,
            onExit: @escaping (Int32) -> Void
        ) throws -> LabProcessHandle {
            launches.append((arguments, logURL))
            handlers.append(onExit)
            let handle = FakeHandle()
            lastHandle = handle
            return handle
        }
    }

    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolyn-lab-test-\(UUID().uuidString)")
        let runner = root.appendingPathComponent("lab/src/isolyn_lab/runner.py")
        try FileManager.default.createDirectory(
            at: runner.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: runner.path, contents: Data())

        let harness = root.appendingPathComponent("tools/selfplay/build/selfplay")
        try FileManager.default.createDirectory(
            at: harness.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: harness.path, contents: Data())
        return root
    }

    private func config(games: Int = 5_000_000, seed: Int = 1) -> LabRunConfig {
        LabRunConfig(games: games, mode: "1v1", depth: 8, determinizations: 64, parallel: 4, seed: seed)
    }

    // MARK: - Stress

    func test_twoHundredStartPressesLaunchExactlyOneProcess() throws {
        let launcher = FakeLauncher()
        let root = try makeRepository()
        let service = LabService(launcher: launcher, root: root, dataRoot: root)

        for _ in 0..<200 { service.start(config()) }

        XCTAssertEqual(launcher.launches.count, 1, "repeated presses must not spawn more work")
        XCTAssertEqual(service.phase, .running)
        XCTAssertTrue(service.isBusy)
    }

    func test_aDifferentConfigurationWhileRunningIsRejected() throws {
        let launcher = FakeLauncher()
        let root = try makeRepository()
        let service = LabService(launcher: launcher, root: root, dataRoot: root)

        service.start(config(seed: 1))
        for seed in 2...50 { service.start(config(seed: seed)) }

        XCTAssertEqual(launcher.launches.count, 1, "only one run may be active at a time")
        XCTAssertEqual(service.message, "One run at a time — stop the active run first.")
    }

    func test_stopTerminatesTheChildAndAllowsANewRun() throws {
        let launcher = FakeLauncher()
        let root = try makeRepository()
        let service = LabService(launcher: launcher, root: root, dataRoot: root)

        service.start(config(seed: 1))
        service.stop()

        XCTAssertEqual(launcher.lastHandle?.terminated, true, "Stop must signal the runner, not just repaint")
        XCTAssertEqual(service.phase, .stopped)
        XCTAssertFalse(service.isBusy)

        service.start(config(seed: 99))
        XCTAssertEqual(launcher.launches.count, 2)
    }

    func test_pressesDuringTheRepeatWindowAfterAStopDoNotRelaunch() throws {
        let launcher = FakeLauncher()
        let root = try makeRepository()
        let service = LabService(launcher: launcher, root: root, dataRoot: root)

        service.start(config(seed: 7))
        service.stop()
        for _ in 0..<50 { service.start(config(seed: 7)) }

        XCTAssertEqual(launcher.launches.count, 1, "a double-click after Stop must not start a second process")
    }

    // MARK: - Completion and manifests

    func test_exitMarksFinishedWhenEveryShardIsDone() async throws {
        let root = try makeRepository()
        let launcher = FakeLauncher()
        let service = LabService(launcher: launcher, root: root, dataRoot: root)
        let requested = config(games: 5, seed: 3)

        service.start(requested)

        let runDirectory = LabPaths.runDirectory(dataRoot: root, runID: requested.runID)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let manifest = """
        {
          "version": 1,
          "run_id": "\(requested.runID)",
          "created_at": "2026-11-14T10:00:00+00:00",
          "started_at": "2026-11-14T10:00:00+00:00",
          "config": {"games": 5, "mode": "1v1", "depth": 8, "determinizations": 64, "seed": 3},
          "shards": [{"index": 0, "games": 5, "status": "done", "rows": 91}]
        }
        """
        try manifest.write(
                            to: LabPaths.manifestURL(dataRoot: root, runID: requested.runID),
            atomically: true,
            encoding: .utf8
        )

        launcher.handlers.first?(0)
        for _ in 0..<40 {
            await Task.yield()
            if service.phase == .finished { break }
        }

        XCTAssertEqual(service.phase, .finished)
        XCTAssertEqual(service.manifest?.doneGames, 5)
        XCTAssertEqual(service.manifest?.isComplete, true)
    }

    func test_manifestDecodingComputesProgressAndConfig() throws {
        let json = """
        {
          "run_id": "1v1-d8x64-n10000-s1",
          "created_at": "2026-11-14T09:00:00+00:00",
          "started_at": "2026-11-14T09:00:00+00:00",
          "config": {"games": 10000, "mode": "1v1", "depth": 8, "determinizations": 64, "seed": 1},
          "shards": [
            {"index": 0, "games": 5000, "status": "done"},
            {"index": 1, "games": 5000, "status": "pending"}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(LabManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.doneGames, 5000)
        XCTAssertEqual(manifest.totalGames, 10000)
        XCTAssertEqual(manifest.fraction, 0.5, accuracy: 0.0001)
        XCTAssertFalse(manifest.isComplete)
        XCTAssertEqual(manifest.runConfig.runID, "1v1-d8x64-n10000-s1")
    }

    func test_repositoryRootIsFoundFromInsideTheAppBundle() throws {
        let root = try makeRepository()
        let executableDirectory = root
            .appendingPathComponent("build/IsolynV2.0.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)

        let found = LabPaths.findRoot(startingAt: executableDirectory)

        XCTAssertEqual(found?.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path)
    }

    func test_runIDsThatCouldEscapeTheRunsFolderAreRejected() {
        XCTAssertTrue(LabPaths.isSafeRunID("1v1-d8x64-n5000000-s1"))
        XCTAssertFalse(LabPaths.isSafeRunID("../etc/passwd"))
        XCTAssertFalse(LabPaths.isSafeRunID("a/b"))
        XCTAssertFalse(LabPaths.isSafeRunID(".hidden"))
        XCTAssertFalse(LabPaths.isSafeRunID(""))
    }

    // MARK: - Rendering

    func test_labScreenRendersWithoutAClick() throws {
        let launcher = FakeLauncher()
        let root = try makeRepository()
        let model = LabService(launcher: launcher, root: root, dataRoot: root)
        let estimator = LabEstimator(launcher: launcher, root: root, dataRoot: root)
        let view = LabView()
            .environment(AppState())
            .environment(model)
            .environment(LabAnalysisService(launcher: launcher, root: root, dataRoot: root))
            .environment(estimator)
            .frame(width: 1080, height: 720)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 720)

        XCTAssertNotNil(renderer.nsImage, "the Lab screen must render at the default window size")
    }

    // MARK: - Library

    private func writeManifest(
        root: URL,
        id: String,
        started: String,
        games: Int,
        done: Int,
        total: Int
    ) throws {
        let shards = (0..<total).map { index in
            "{\"index\": \(index), \"games\": \(games / total), \"status\": \"\(index < done ? "done" : "pending")\", \"rows\": 10}"
        }.joined(separator: ",")
        let json = """
        {
          "version": 1,
          "run_id": "\(id)",
          "created_at": "\(started)",
          "started_at": "\(started)",
          "config": {"games": \(games), "mode": "1v1", "depth": 2, "determinizations": 4, "seed": 1},
          "shards": [\(shards)]
        }
        """
        let directory = LabPaths.runDirectory(dataRoot: root, runID: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json.write(
            to: LabPaths.manifestURL(dataRoot: root, runID: id),
            atomically: true,
            encoding: .utf8
        )
    }

    func test_libraryFiltersSearchesAndOrdersRuns() throws {
        let root = try makeRepository()
        let service = LabService(launcher: FakeLauncher(), root: root, dataRoot: root)
        try writeManifest(
            root: root,
            id: "1v1-d2x4-n10-s1",
            started: "2026-11-14T09:00:00+00:00",
            games: 10, done: 1, total: 2
        )
        try writeManifest(
            root: root,
            id: "1v1v1-d2x4-n20-s2",
            started: "2026-11-14T10:00:00+00:00",
            games: 20, done: 2, total: 2
        )

        service.refreshLibrary(force: true)

        XCTAssertEqual(
            service.library.map(\.runId),
            ["1v1v1-d2x4-n20-s2", "1v1-d2x4-n10-s1"],
            "newest run first"
        )
        XCTAssertEqual(service.runs(filter: .finished).map(\.runId), ["1v1v1-d2x4-n20-s2"])
        XCTAssertEqual(service.runs(filter: .unfinished).map(\.runId), ["1v1-d2x4-n10-s1"])
        XCTAssertEqual(service.runs(query: "1v1v1").count, 1)
        XCTAssertTrue(service.runs(query: "nothing-matches").isEmpty)
    }

    func test_manifestPredictsAFinishTimeFromItsOwnPace() throws {
        let started = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-20))
        let json = """
        {
          "run_id": "1v1-d2x4-n2000-s1",
          "created_at": "\(started)",
          "started_at": "\(started)",
          "config": {"games": 2000, "mode": "1v1", "depth": 2, "determinizations": 4, "seed": 1},
          "shards": [
            {"index": 0, "games": 1000, "status": "done", "rows": 10},
            {"index": 1, "games": 1000, "status": "pending"}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(LabManifest.self, from: Data(json.utf8))

        XCTAssertNotNil(manifest.startedDate, "the start time must be parsed once, not per view")
        XCTAssertEqual(manifest.fraction, 0.5, accuracy: 0.0001)
        let rate = try XCTUnwrap(manifest.gamesPerSecond())
        XCTAssertEqual(rate, 50, accuracy: 5, "1000 games in ~20 s")
        let finish = try XCTUnwrap(manifest.estimatedFinish())
        XCTAssertGreaterThan(finish, Date())
        XCTAssertLessThan(finish.timeIntervalSinceNow, 60)
    }

    // MARK: - Real process

    func test_realRunnerCompletesASmokeRun() async throws {
        guard let root = LabPaths.repositoryRoot() else {
            throw XCTSkip("repository root not found")
        }
        let launcher = ProcessLabLauncher()
        let service = LabService(launcher: launcher, root: root, dataRoot: root)
        guard service.harnessBuilt else {
            throw XCTSkip("self-play harness not built")
        }

        let requested = LabRunConfig(
            games: 5,
            mode: "1v1",
            depth: 2,
            determinizations: 2,
            parallel: 1,
            seed: 987_654
        )
        service.start(requested)

        var finished = false
        for _ in 0..<240 where !finished {
            try await Task.sleep(nanoseconds: 250_000_000)
            finished = service.phase == .finished
        }

        XCTAssertTrue(finished, "a 5-game smoke run should finish; phase was \(service.phase)")
        XCTAssertEqual(service.manifest?.doneGames, 5)
        XCTAssertTrue(service.message?.contains("complete") == true)
    }
}
