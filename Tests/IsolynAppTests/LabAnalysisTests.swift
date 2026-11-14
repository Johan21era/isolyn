import SwiftUI
import XCTest
@testable import IsolynApp

@MainActor
final class LabAnalysisTests: XCTestCase {

    final class FakeLauncher: LabLaunching {
        private(set) var launches: [[String]] = []
        private(set) var handlers: [(Int32) -> Void] = []

        func launch(
            root: URL,
            arguments: [String],
            logURL: URL,
            onExit: @escaping (Int32) -> Void
        ) throws -> LabProcessHandle {
            launches.append(arguments)
            handlers.append(onExit)
            return LabServiceTests.FakeHandle()
        }
    }

    private let fixture = """
    [
      {
        "input": "/tmp/run-a/merged.csv",
        "mode": "1v1",
        "games": 400,
        "decisions": 6801,
        "outcomes": {"closed": 88, "domino": 312},
        "config_a": {"depth": 8, "determinizations": 64},
        "config_b": {"depth": 8, "determinizations": 64},
        "participants": [
          {"label": "Player 1", "games": 400, "wins": 217, "win_rate": 0.5425,
           "win_low": 0.4927, "win_high": 0.5915, "average_points": 11.22,
           "average_initial_pips": 40.4},
          {"label": "Player 2", "games": 400, "wins": 183, "win_rate": 0.4575,
           "win_low": 0.4085, "win_high": 0.5073, "average_points": 10.81,
           "average_initial_pips": 40.1}
        ],
        "sides": [
          {"label": "A", "games": 400, "wins": 217, "win_rate": 0.5425,
           "win_low": 0.4927, "win_high": 0.5915, "average_points": 11.22,
           "average_initial_pips": 40.4},
          {"label": "B", "games": 400, "wins": 183, "win_rate": 0.4575,
           "win_low": 0.4085, "win_high": 0.5073, "average_points": 10.81,
           "average_initial_pips": 40.1}
        ],
        "spearman": {"initial_vs_points": -0.0479, "initial_vs_win": 0.0145, "samples": 800},
        "elo": {"a_vs_b": 29.6, "low": -4.5, "high": 63.7, "games": 400, "score_a": 0.5425}
      },
      {
        "input": "/tmp/run-b/shard-0000.csv",
        "mode": "1v1",
        "games": 1,
        "decisions": 30,
        "outcomes": {"domino": 1},
        "config_a": {"depth": 4, "determinizations": 20},
        "config_b": {"depth": 8, "determinizations": 64},
        "participants": [
          {"label": "Player 1", "games": 1, "wins": 1, "win_rate": 1.0,
           "win_low": 0.2, "win_high": 1.0, "average_points": 50.0,
           "average_initial_pips": 35.0}
        ],
        "sides": [],
        "spearman": {"initial_vs_points": null, "initial_vs_win": null, "samples": 0},
        "elo": null
      }
    ]
    """

    func test_analysisJSONDecodesBothShapes() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reports = try decoder.decode([LabAnalysisReport].self, from: Data(fixture.utf8))

        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].games, 400)
        XCTAssertEqual(reports[0].participants.count, 2)
        XCTAssertEqual(reports[0].participants[0].winRate, 0.5425, accuracy: 0.0001)
        XCTAssertTrue(reports[0].isSymmetric)
        XCTAssertEqual(reports[0].elo?.aVsB, 29.6)
        XCTAssertEqual(reports[0].displayName, "merged.csv")

        XCTAssertFalse(reports[1].isSymmetric, "A d4/20 against B d8/64 is not symmetric")
        XCTAssertNil(reports[1].elo)
        XCTAssertNil(reports[1].spearman.initialVsWin)
        XCTAssertEqual(reports[1].displayName, "shard-0000.csv")
    }

    func test_hundredAnalysisPressesLaunchOneProcess() throws {
        let launcher = FakeLauncher()
        let service = LabAnalysisService(
            launcher: launcher,
            root: FileManager.default.temporaryDirectory
        )
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("x.csv")

        for _ in 0..<100 { service.run(inputs: [input]) }

        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertTrue(service.isRunning)
    }

    func test_analysisIsRefusedWithNoInputs() throws {
        let launcher = FakeLauncher()
        let service = LabAnalysisService(launcher: launcher, root: FileManager.default.temporaryDirectory)

        service.run(inputs: [])

        XCTAssertEqual(launcher.launches.count, 0)
        XCTAssertEqual(service.message, "Select at least one finished run.")
    }

    func test_inputsPreferMergedCSVThenShardCSVs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolyn-analysis-\(UUID().uuidString)")
        let runID = "1v1-d8x64-n100-s1"
        let runDirectory = LabPaths.runDirectory(dataRoot: root, runID: runID)
        let shardDirectory = runDirectory.appendingPathComponent("shards", isDirectory: true)
        try FileManager.default.createDirectory(at: shardDirectory, withIntermediateDirectories: true)
        for index in 0..<12 {
            FileManager.default.createFile(
                atPath: shardDirectory.appendingPathComponent(String(format: "shard-%04d.csv", index)).path,
                contents: Data()
            )
        }

        let service = LabAnalysisService(launcher: FakeLauncher(), root: root, dataRoot: root)
        XCTAssertEqual(service.inputs(for: runID).count, 8, "unmerged runs analyze at most eight shards")

        FileManager.default.createFile(
            atPath: runDirectory.appendingPathComponent("merged.csv").path,
            contents: Data()
        )
        XCTAssertEqual(service.inputs(for: runID).map(\.lastPathComponent), ["merged.csv"])
    }

    func test_realAnalysisReadsARealRunEndToEnd() async throws {
        guard let root = LabPaths.repositoryRoot() else {
            throw XCTSkip("repository root not found")
        }
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolyn-e2e-\(UUID().uuidString)")
        let lab = LabService(root: root, dataRoot: store)
        guard lab.harnessBuilt else { throw XCTSkip("self-play harness not built") }

        let config = LabRunConfig(
            games: 2,
            mode: "1v1",
            depth: 2,
            determinizations: 2,
            parallel: 1,
            seed: 424_242
        )
        lab.start(config)
        for _ in 0..<200 where lab.phase != .finished {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertEqual(lab.phase, .finished, "the source run must finish before it can be analyzed")

        let analysis = LabAnalysisService(root: root, dataRoot: store)
        let inputs = analysis.inputs(for: config.runID)
        XCTAssertFalse(inputs.isEmpty)

        analysis.run(inputs: inputs)
        for _ in 0..<200 where analysis.reports.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(analysis.reports.count, inputs.count)
        XCTAssertEqual(analysis.reports.first?.games, 2)
        XCTAssertEqual(analysis.reports.first?.mode, "1v1")
        XCTAssertTrue(analysis.reports.first?.configA.depth == 2)
        XCTAssertTrue(analysis.reports.first?.configB.depth == 2, "the runner must make side B match side A by default")
    }

    func test_analysisTabRendersWithReports() throws {
        let store = FileManager.default.temporaryDirectory
        let lab = LabService(launcher: FakeLauncher(), root: store, dataRoot: store)
        let analysis = LabAnalysisService(launcher: FakeLauncher(), root: store, dataRoot: store)

        let view = LabAnalysisView()
            .environment(AppState())
            .environment(lab)
            .environment(analysis)
            .frame(width: 1080, height: 720)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 720)
        XCTAssertNotNil(renderer.nsImage)
    }
}
