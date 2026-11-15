import XCTest
@testable import IsolynApp
import IsolynEngineBridge

@MainActor
final class AIOpponentTests: XCTestCase {

    func test_difficulty_profiles_come_from_the_engine_mapping() {
        let casual = AIProfile(level: .casual)
        XCTAssertEqual(casual.strength, 100)
        XCTAssertEqual(casual.maxDepthPlies, 2)
        XCTAssertEqual(casual.determinizationCount, 8)

        let club = AIProfile(level: .club)
        XCTAssertEqual(club.strength, 900)
        XCTAssertEqual(club.maxDepthPlies, 3)
        XCTAssertEqual(club.determinizationCount, 16)

        let elite = AIProfile(level: .elite)
        XCTAssertEqual(elite.strength, 1600)
        XCTAssertEqual(elite.maxDepthPlies, 4)
        XCTAssertEqual(elite.determinizationCount, 24)

        let expert = AIProfile(level: .expert)
        XCTAssertEqual(expert.strength, 2300)
        XCTAssertEqual(expert.maxDepthPlies, 5)
        XCTAssertEqual(expert.determinizationCount, 40)

        let master = AIProfile(level: .master)
        XCTAssertEqual(master.strength, 3000)
        XCTAssertEqual(master.maxDepthPlies, 8)
        XCTAssertEqual(master.determinizationCount, 64)

        let legendary = AIProfile(level: .legendary)
        XCTAssertEqual(legendary.strength, 5000)
        XCTAssertEqual(legendary.maxDepthPlies, 24)
        XCTAssertEqual(legendary.determinizationCount, 80)

        let mythical = AIProfile(level: .mythical)
        XCTAssertEqual(mythical.strength, 10000)
        XCTAssertEqual(mythical.maxDepthPlies, 48)
        XCTAssertEqual(mythical.determinizationCount, 160)

        XCTAssertEqual(
            AILevel.allCases.map(\.title),
            ["Casual", "Club", "Elite", "Expert", "Master", "Legendary", "Mythical"],
            "the menu must present the tiers weakest to strongest"
        )
        XCTAssertEqual(
            AILevel.allCases.map(\.rawValue),
            [100, 900, 1600, 2300, 3000, 5000, 10000],
            "the tier labels must follow the monotonic strength ladder"
        )
        XCTAssertEqual(
            AILevel.allCases.map(\.thinkingTimeMs),
            [3_000, 3_000, 3_000, 3_000, 3_000, 15_000, 15_000],
            "both deeper tiers get the requested 15-second wall-clock budget"
        )
    }

    func test_computer_seat_mapping_respects_two_v_two_partnerships() {
        XCTAssertTrue(MatchFormat.oneVOne.isComputerSeat(1, for: .computer))
        XCTAssertFalse(MatchFormat.oneVOne.isComputerSeat(0, for: .computer))

        XCTAssertFalse(MatchFormat.twoVTwo.isComputerSeat(0, for: .computer))
        XCTAssertTrue(MatchFormat.twoVTwo.isComputerSeat(1, for: .computer))
        XCTAssertTrue(MatchFormat.twoVTwo.isComputerSeat(2, for: .computer),
                      "the human's partner must not stall the single-human match")
        XCTAssertTrue(MatchFormat.twoVTwo.isComputerSeat(3, for: .computer))
    }

    func test_short_race_target_is_accepted_only_for_one_v_one() throws {
        let short = try MatchCoordinator(mode: .oneVOne, targetScore: 101)
        XCTAssertEqual(short.targetScore, 101)
        short.close()

        XCTAssertThrowsError(try MatchCoordinator(mode: .oneVOneVOne, targetScore: 101))
        XCTAssertThrowsError(try MatchCoordinator(mode: .twoVTwo, targetScore: 101))
    }

    func test_computer_plays_its_own_turn_without_human_input() async throws {
        // The opener is dealt randomly, so hunt for a deal where the computer
        // acts immediately after the mandated opening tile. The assertion is
        // the same for every such deal: the human never submits a move, yet
        // the state version advances and play reaches the human seat (or the
        // round ends).
        for _ in 0..<16 {
            let vm = GameViewModel(mode: .oneVOne, opponent: .computer, aiLevel: .casual)
            await vm.refresh()

            guard let before = vm.snapshot else {
                vm.shutdown()
                return XCTFail("initial snapshot missing")
            }
            guard before.currentPlayerIndex == 1 else {
                vm.shutdown()
                continue
            }

            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if let now = vm.snapshot,
                   now.stateVersion != before.stateVersion || now.roundOutcome != .inProgress {
                    vm.shutdown()
                    return
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            vm.shutdown()
            return XCTFail("computer did not complete its turn within the deadline")
        }

        throw XCTSkip("all 16 deals let the human act immediately after the opener")
    }

    func test_computer_plays_two_v_two_partner_turn_without_stalling() async throws {
        for _ in 0..<16 {
            let vm = GameViewModel(mode: .twoVTwo, opponent: .computer, aiLevel: .casual)
            await vm.refresh()

            guard let before = vm.snapshot else {
                vm.shutdown()
                return XCTFail("initial snapshot missing")
            }
            guard before.currentPlayerIndex != 0 else {
                vm.shutdown()
                continue
            }

            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if let now = vm.snapshot,
                   now.stateVersion != before.stateVersion || now.roundOutcome != .inProgress {
                    vm.shutdown()
                    return
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            vm.shutdown()
            return XCTFail("2v2 computer turn did not complete within the deadline")
        }

        throw XCTSkip("all 16 2v2 deals let the human act immediately after the opener")
    }
}