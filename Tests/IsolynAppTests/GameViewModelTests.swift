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

    func test_blockedPlayer_isNotDrawnAutomatically() async throws {
        // Drawing is mandatory, not automatic. A blocked player must still hold
        // the same hand after a refresh: the app may not spend their draws for
        // them. The Draw control is what resolves the block, one tile at a time.
        // (This test previously asserted the opposite -- that refresh() silently
        // self-resolved blocked turns -- which is the behaviour the owner's live
        // testing rejected.)
        for _ in 0..<24 {
            let vm = GameViewModel(mode: .oneVOne)
            await vm.refresh()
            defer { vm.shutdown() }
            guard let snap = vm.snapshot, snap.roundOutcome == .inProgress else { continue }
            guard vm.isMyTurn,
                  snap.legalMoves.isEmpty,
                  snap.boneyardDrawableCount > 0 else { continue }

            let handBefore = snap.ownHand.count
            await vm.refresh()
            guard let after = vm.snapshot else { return XCTFail("snapshot missing after refresh") }
            XCTAssertEqual(after.ownHand.count, handBefore,
                           "refresh() must not draw tiles on the player's behalf")
            XCTAssertTrue(vm.canVoluntaryDraw,
                          "a blocked player must be offered the draw instead")
            XCTAssertFalse(vm.mustPass,
                           "passing is only legal once the yard is dry")

            await vm.voluntaryDraw()
            guard let drawn = vm.snapshot else { return XCTFail("post-draw snapshot missing") }
            XCTAssertEqual(drawn.ownHand.count, handBefore + 1,
                           "the player's own draw must add exactly one tile")
            return
        }
        throw XCTSkip("no blocked-with-tiles deal encountered in 24 hunts")
    }

    func test_voluntaryDraw_publishesDrawEventForTheFlight() async throws {
        for _ in 0..<24 {
            let vm = GameViewModel(mode: .oneVOne)
            await vm.refresh()
            guard vm.isMyTurn, vm.canVoluntaryDraw, let before = vm.snapshot else {
                vm.shutdown()
                continue
            }

            await vm.voluntaryDraw()
            guard let after = vm.snapshot else {
                vm.shutdown()
                return XCTFail("post-draw snapshot missing")
            }
            XCTAssertEqual(after.ownHand.count, before.ownHand.count + 1)

            let event = try XCTUnwrap(vm.drawEvent, "a real draw must publish a flight event")
            XCTAssertEqual(event.seat, after.requestingPlayerIndex)
            XCTAssertEqual(event.count, 1)
            XCTAssertEqual(event.tiles, after.ownHand.filter { !before.ownHand.contains($0) })
            vm.shutdown()
            return
        }
        throw XCTSkip("no drawable opening deal encountered in 24 hunts")
    }

    private func viewModelNeedsPass(_ vm: GameViewModel) -> Bool {
        vm.mustPass
    }
}
