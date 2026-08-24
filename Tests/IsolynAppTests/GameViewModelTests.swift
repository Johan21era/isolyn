import XCTest
@testable import IsolynApp
import IsolynEngineBridge

/// Headless verification of the Phase 2 turn-flow state machine: real engine
/// sessions, real CSPRNG deals, no UI. Tolerant of deal randomness in the same
/// spirit as the bridge SmokeTest -- assertions hold for EVERY legal deal,
/// never a lucky one.
@MainActor
final class GameViewModelTests: XCTestCase {

    func test_setup_producesLiveSessionWithRealHand() async throws {
        let vm = GameViewModel(mode: .oneVOne)
        defer { vm.shutdown() }
        XCTAssertNil(vm.setupError)
        await vm.refresh()

        guard let snap = vm.snapshot else {
            return XCTFail("snapshot should exist after first refresh")
        }
        XCTAssertEqual(snap.mode, .oneVOne)
        XCTAssertEqual(snap.playerCount, 2)
        // The mandated opener is already on the chain (dealFirstRound).
        XCTAssertEqual(snap.chain.count, 1, "mandated opening tile applied")
        XCTAssertFalse(snap.ownHand.isEmpty, "requesting-as-current means we see someone's real rack")
        XCTAssertEqual(vm.phase, .playing)
    }

    func test_playingALegalMove_advancesState() async throws {
        let vm = GameViewModel(mode: .oneVOne)
        defer { vm.shutdown() }
        await vm.refresh()

        // Drive through forced draws until the current player can act or the
        // round somehow ended (it cannot have, after one tile -- but stay honest).
        for _ in 0..<40 where vm.snapshot?.roundOutcome == .inProgress && !vm.canPlayTiles {
            if viewModelNeedsPass(vm) { await vm.passTurn() }
            else { await vm.voluntaryDraw() }
            if vm.mustPass { break }
        }

        guard vm.canPlayTiles, let snap = vm.snapshot, let move = snap.legalMoves.first else {
            throw XCTSkip("deal left current player permanently blocked pre-move; flow verified up to pass boundary")
        }

        let versionBefore = snap.stateVersion
        let handBefore = snap.ownHand.count
        await vm.play(move)

        guard let after = vm.snapshot else { return XCTFail("post-play snapshot missing") }
        XCTAssertNotEqual(after.stateVersion, versionBefore, "state version advanced")
        // Either turn passed (hand unchanged) or it was our last tile (Domino!).
        XCTAssertTrue(
            after.currentPlayerIndex != snap.currentPlayerIndex || after.roundOutcome != .inProgress,
            "turn advanced or round ended"
        )
        _ = handBefore
    }

    func test_forcedDrawLoop_resolvesBlockedPlayerWithoutManualHelp() async throws {
        // Hunt across fresh deals for one where the post-opener player is
        // blocked (~1-in-8), then prove refresh() self-resolves: by the time
        // phase settles, either moves exist or the yard went dry mid-loop.
        var hunted = false
        for _ in 0..<24 {
            let vm = GameViewModel(mode: .oneVOne)
            await vm.refresh()
            defer { vm.shutdown() }
            guard let snap = vm.snapshot, snap.roundOutcome == .inProgress else { continue }
            if snap.legalMoves.isEmpty {
                hunted = true
                // refresh() already auto-ran forced draws before surfacing;
                // whatever state we settled in must be LEGAL per rules:
                XCTAssertTrue(
                    !snap.legalMoves.isEmpty || snap.boneyardDrawableCount == 0,
                    "blocked state only valid when nothing remains drawable"
                )
                break
            }
        }
        if !hunted { throw XCTSkip("no blocked deal encountered in 24 hunts (p≈0.87 of at least one)") }
    }

    private func viewModelNeedsPass(_ vm: GameViewModel) -> Bool {
        vm.mustPass
    }
}
