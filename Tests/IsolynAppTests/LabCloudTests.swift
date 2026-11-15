import XCTest
@testable import IsolynApp

@MainActor
final class LabCloudTests: XCTestCase {

    final class FakeHandle: LabProcessHandle {
        var isRunning = true
        func terminate() { isRunning = false }
    }

    final class FakeLauncher: LabLaunching {
        private(set) var launches: [([String], URL, [String: String])] = []
        private(set) var handlers: [(Int32) -> Void] = []
        var statusOutput = "KernelWorkerStatus.COMPLETE"

        func launch(
            root: URL,
            arguments: [String],
            logURL: URL,
            onExit: @escaping (Int32) -> Void
        ) throws -> LabProcessHandle {
            try launch(
                root: root,
                arguments: arguments,
                logURL: logURL,
                environment: [:],
                onExit: onExit
            )
        }

        func launch(
            root: URL,
            arguments: [String],
            logURL: URL,
            environment: [String: String],
            onExit: @escaping (Int32) -> Void
        ) throws -> LabProcessHandle {
            launches.append((arguments, logURL, environment))
            if arguments.contains("status") {
                try? statusOutput.write(to: logURL, atomically: true, encoding: .utf8)
            }
            handlers.append(onExit)
            return FakeHandle()
        }

        func completeNext() {
            let handler = handlers.removeFirst()
            handler(0)
        }
    }

    private func makeRoot(clean: Bool = true) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolyn-cloud-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source: [String: Any] = [
            "schema": 1,
            "source_commit": String(repeating: "a", count: 40),
            "code_sha256": String(repeating: "b", count: 64),
            "clean": clean,
            "files": [],
            "staged_at": "2026-11-15T00:00:00+00:00",
        ]
        let data = try JSONSerialization.data(withJSONObject: source)
        try data.write(to: root.appendingPathComponent("source.json"))
        return root
    }

    private func writePushedRun(root: URL, runID: String) throws {
        let run = root.appendingPathComponent("cloud-data/cloud/\(runID)")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        let plan: [String: Any] = [
            "schema": 1,
            "run_id": runID,
            "games": 10_000,
            "session_games": 10_000,
            "source_commit": String(repeating: "a", count: 40),
            "code_sha256": String(repeating: "b", count: 64),
            "dataset_ref": "tester/isolyn-code",
            "kernel_prefix": "isolyn-lab",
            "shards": [["index": 0, "games": 10_000]],
            "sessions": [["id": "0000", "games": 10_000]],
        ]
        let ledger: [String: Any] = [
            "schema": 1,
            "sessions": ["0000": ["pushed_at": "now", "kernel_id": "tester/isolyn-lab-0000"]],
        ]
        try JSONSerialization.data(withJSONObject: plan).write(to: run.appendingPathComponent("plan.json"))
        try JSONSerialization.data(withJSONObject: ledger).write(to: run.appendingPathComponent("ledger.json"))
    }

    func test_start_plans_prepares_and_uploads_the_fixed_10000_game_session() async throws {
        let root = try makeRoot()
        let launcher = FakeLauncher()
        let service = LabCloudService(
            launcher: launcher,
            root: root,
            dataRoot: root.appendingPathComponent("cloud-data")
        )
        service.owner = "tester"

        service.start()
        XCTAssertEqual(launcher.launches.count, 1)
        let planArguments = launcher.launches[0].0
        XCTAssertTrue(planArguments.joined(separator: " ").contains("--games 10000"))
        XCTAssertTrue(planArguments.joined(separator: " ").contains("--session-games 10000"))
        XCTAssertTrue(planArguments.joined(separator: " ").contains("--owner tester"))
        XCTAssertEqual(launcher.launches[0].2["ISOLYN_CLOUD_DIR"],
                       root.appendingPathComponent("cloud-data/cloud").path)

        launcher.completeNext()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(launcher.launches.count, 2)
        XCTAssertEqual(Array(launcher.launches[1].0.prefix(2)), ["cloud", "prepare"])

        launcher.completeNext()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(launcher.launches.count, 3)
        XCTAssertEqual(Array(launcher.launches[2].0.prefix(2)), ["cloud", "push"])
        XCTAssertTrue(launcher.launches[2].0.contains("--yes"))
        launcher.completeNext()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.phase, .waiting)
    }

    func test_status_check_only_reveals_collect_after_kaggle_is_complete() async throws {
        let root = try makeRoot()
        let launcher = FakeLauncher()
        let service = LabCloudService(
            launcher: launcher,
            root: root,
            dataRoot: root.appendingPathComponent("cloud-data")
        )
        service.owner = "tester"
        try writePushedRun(root: root, runID: service.runID)
        service.refresh()

        XCTAssertTrue(service.hasPushed)
        XCTAssertFalse(service.canCollect, "Collect must not be available before a status check")

        service.checkStatus()
        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(Array(launcher.launches[0].0.prefix(2)), ["cloud", "status"])
        launcher.completeNext()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(service.remoteComplete)
        XCTAssertEqual(service.remoteStatus, "complete")
        XCTAssertTrue(service.canCollect)
        XCTAssertEqual(service.phase, .waiting)
    }

    func test_a_dirty_staged_source_cannot_start_a_cloud_upload() throws {
        let root = try makeRoot(clean: false)
        let launcher = FakeLauncher()
        let service = LabCloudService(
            launcher: launcher,
            root: root,
            dataRoot: root.appendingPathComponent("cloud-data")
        )
        service.owner = "tester"

        service.start()

        XCTAssertTrue(launcher.launches.isEmpty)
        guard case .failed(let reason) = service.phase else {
            return XCTFail("a dirty source must fail visibly")
        }
        XCTAssertTrue(reason.contains("dirty"))
    }
}
