import SwiftUI
import XCTest
@testable import IsolynApp

@MainActor
final class LabEstimatorTests: XCTestCase {

    func test_estimateMathTurnsRateIntoDurationShardsAndDisk() {
        let estimate = LabWorkloadEstimate(
            rate: 10,
            duration: 5_000_000 / 10,
            shardCount: 1_000,
            outputBytes: 5_000_000 * 1_950,
            probeGames: 64,
            probeSeconds: 6.4,
            measuredAt: Date()
        )

        XCTAssertEqual(estimate.duration, 500_000, accuracy: 0.001)
        XCTAssertEqual(estimate.shardCount, 1_000)
        XCTAssertEqual(estimate.level, .extreme)
        XCTAssertEqual(estimate.durationText, "5.8 days")
        XCTAssertGreaterThan(estimate.gaugeFraction, 0.9)
        XCTAssertLessThanOrEqual(estimate.gaugeFraction, 1.0)
        XCTAssertTrue(estimate.outputText.contains("GB"))
    }

    func test_smallRunsReadAsLight() {
        let estimate = LabWorkloadEstimate(
            rate: 20,
            duration: 200.0 / 20,
            shardCount: 1,
            outputBytes: 200 * 1_950,
            probeGames: 16,
            probeSeconds: 0.8,
            measuredAt: Date()
        )
        XCTAssertEqual(estimate.level, .light)
        XCTAssertEqual(estimate.durationText, "10s")
        XCTAssertLessThan(estimate.gaugeFraction, 0.2)
    }

    func test_repeatedMeasureCallsLaunchOneProbe() throws {
        let launcher = LabServiceTests.FakeLauncher()
        let estimator = LabEstimator(
            launcher: launcher,
            root: FileManager.default.temporaryDirectory
        )
        let config = LabRunConfig(games: 1_000, mode: "1v1", depth: 4, determinizations: 8, parallel: 2, seed: 1)

        for _ in 0..<25 { estimator.measure(config) }

        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertTrue(estimator.isMeasuring)
        let arguments = launcher.launches.first?.0 ?? []
        XCTAssertTrue(arguments.contains("--run-id"))
        XCTAssertTrue(arguments.contains { $0.hasPrefix("probe-") }, "probes must not appear as owner runs")
        XCTAssertTrue(arguments.contains("--restart"))
    }

    func test_configChangeDuringAProbeIsQueuedNotDropped() async throws {
        let launcher = LabServiceTests.FakeLauncher()
        let estimator = LabEstimator(
            launcher: launcher,
            root: FileManager.default.temporaryDirectory
        )
        let first = LabRunConfig(games: 1_000, mode: "1v1", depth: 4, determinizations: 8, parallel: 2, seed: 1)
        let second = LabRunConfig(games: 1_000, mode: "1v1", depth: 6, determinizations: 8, parallel: 2, seed: 1)

        estimator.measure(first)
        estimator.measure(second)
        XCTAssertEqual(launcher.launches.count, 1)

        launcher.handlers.first?(0)
        for _ in 0..<40 {
            await Task.yield()
            if launcher.launches.count == 2 { break }
        }

        XCTAssertEqual(launcher.launches.count, 2, "the config the owner landed on must still be measured")
        XCTAssertNotNil(estimator.estimate)
    }

    func test_realProbeMeasuresThisMachine() async throws {
        guard let root = LabPaths.repositoryRoot(),
              FileManager.default.fileExists(
                atPath: root.appendingPathComponent("tools/selfplay/build/selfplay").path
              ) else {
            throw XCTSkip("repository or harness not available")
        }

        let estimator = LabEstimator(root: root)
        let config = LabRunConfig(
            games: 500,
            mode: "1v1",
            depth: 2,
            determinizations: 2,
            parallel: 2,
            seed: 313_131
        )
        estimator.measure(config)

        for _ in 0..<400 where estimator.estimate == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let estimate = try XCTUnwrap(estimator.estimate, "a real probe should produce an estimate")
        XCTAssertGreaterThan(estimate.rate, 0)
        XCTAssertGreaterThan(estimate.probeGames, 0)
        XCTAssertEqual(estimate.shardCount, 1)
    }

    func test_runsScreenRendersWithTheWorkloadCard() throws {
        let root = FileManager.default.temporaryDirectory
        let service = LabService(launcher: LabServiceTests.FakeLauncher(), root: root)
        let estimator = LabEstimator(launcher: LabServiceTests.FakeLauncher(), root: root)

        let view = LabRunsView()
            .environment(service)
            .environment(estimator)
            .frame(width: 1080, height: 720)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 720)
        XCTAssertNotNil(renderer.nsImage)
    }
}
