import Foundation
import IsolynEngineBridge

// FIX-19a (audit F-08): every @unknown default below previously fell
// back SILENTLY -- a future C++ enum evolution would have presented a
// finished round as .inProgress (or mislabeled a mode) with zero trace.
// Each fallback now emits an os_log fault so divergence between the C++
// bridge surface and this Swift mapping is observable in Console the
// moment it happens, instead of being discovered as mysterious gameplay
// weirdness months later.
import os

private let bridgeDTOLogger = Logger(subsystem: "com.isolyn.app", category: "bridge-dto")

// MARK: - Cxx interop notes (read this first if anything below fails to build)
//
// This file and EngineSession.swift have NEVER been compiled -- no
// session that has worked on this codebase has ever had a Swift
// toolchain available (see docs/history/legacy-handoff.md §5). Everything on the C++ side
// (Sources/IsolynEngineBridge/IsolynBridge.cpp) has been compiled,
// hand-tested, fuzzed for 75000+ real executions, and run clean under
// AddressSanitizer/UndefinedBehaviorSanitizer/ThreadSanitizer completely
// independently of Swift -- see docs/engineering/BRIDGE_TESTING.md. What's genuinely
// unverified is specifically the Swift/Cxx-interop BOUNDARY below, which
// has two known-uncertain spots:
//
// 1. NAMESPACE ACCESS. isolyn::bridge::bridge_session_create_first_round
//    is written below as `isolyn.bridge.bridge_session_create_first_round`.
//    If Xcode reports `isolyn` or `bridge` as unknown, try dropping the
//    qualification (SPM's Cxx interop sometimes flattens C++ namespace
//    members into module scope for simple cases) or Cmd+Click the
//    `import IsolynEngineBridge` line to see the exact synthesized
//    interface. Every call site in this file and EngineSession.swift
//    uses the identical `isolyn.bridge.` prefix, so this is a
//    find-and-replace away from being fixed either way, not a
//    scattered problem.
//
// 2. FIXED C ARRAYS IMPORT AS TUPLES. TileDTO tiles[28] in a C++ struct
//    imports into Swift as a 28-element homogeneous tuple, not an Array
//    -- a well-documented Cxx interop behavior, not a guess. Rather than
//    write out 28 `.0, .1, .2...` tuple accessors by hand (fragile,
//    unreadable, and this bridge has several different fixed-size
//    arrays), every conversion below goes through withTupleAsArray,
//    which reinterprets the tuple's memory directly via
//    withUnsafePointer + withMemoryRebound, inferring the tuple's actual
//    type from the call site rather than ever naming it explicitly --
//    deliberately, since the exact synthesized tuple type name is itself
//    a Cxx-interop implementation detail this file has no way to
//    verify without a compiler. This works because a homogeneous
//    N-tuple and a C array of N elements are guaranteed to have
//    identical memory layout.

/// Reinterprets a fixed-size tuple (as Cxx interop imports a C array) as
/// a contiguous buffer of `count` elements, without depending on tuple
/// accessor syntax or naming the tuple's type. `capacity` must match the
/// tuple's actual arity.
func withTupleAsArray<Tuple, Element>(
    _ tuple: inout Tuple, capacity: Int, count: Int, as: Element.Type
) -> [Element] {
    guard count > 0 else { return [] }
    let clampedCount = min(count, capacity)
    return withUnsafePointer(to: &tuple) { rawPtr in
        rawPtr.withMemoryRebound(to: Element.self, capacity: capacity) { buffer in
            Array(UnsafeBufferPointer(start: buffer, count: clampedCount))
        }
    }
}

// MARK: - Mode mapping

extension MatchFormat {
    var bridgeMode: isolyn.bridge.GameModeDTO {
        switch self {
        case .oneVOne: return .OneVsOne
        case .oneVOneVOne: return .OneVsOneVsOne
        case .twoVTwo: return .TwoVsTwo
        }
    }

    /// Score slots, not players: 2v2 tracks one score per TEAM.
    var participantCount: Int {
        switch self {
        case .oneVOne: return 2
        case .oneVOneVOne: return 3
        case .twoVTwo: return 2
        }
    }
}

// MARK: - Tile / Move

/// One domino tile. `low <= high` is NOT enforced here on purpose --
/// the bridge's own TileDTO doesn't normalize orientation (see
/// IsolynBridge.hpp), so this type doesn't invent a guarantee the C++
/// side doesn't actually provide.
struct Tile: Sendable, Equatable, Hashable {
    let low: Int
    let high: Int

    /// Internal init for constructing tiles from resolved values
    /// (hover-chain resolver, tests). Does NOT bypass bridge validation —
    /// those paths construct from DTOs which are already validated.
    init(low: Int, high: Int) {
        self.low = low
        self.high = high
    }

    /// Points a hand is worth at scoring (RULEBOOK.md R-19): the sum of its
    /// pips, except that the double blank is worth ten when it is the only
    /// tile left and contributes nothing alongside other tiles. Mirrors C++
    /// RulesEngine::handPoints.
    static func handPoints(_ tiles: [Tile]) -> Int {
        if tiles.count == 1, let only = tiles.first, only.low == 0, only.high == 0 {
            return 10
        }
        return tiles.reduce(0) { $0 + $1.low + $1.high }
    }

    func hasFace(_ pip: Int) -> Bool { low == pip || high == pip }
    func otherFace(_ pip: Int) -> Int { low == pip ? high : low }
    /// Canonical dense index in [0, 27] matching C++ DominoTile::index().
    func index() -> Int { high * (high + 1) / 2 + low }

    fileprivate init(dto: isolyn.bridge.TileDTO) {
        low = Int(dto.low)
        high = Int(dto.high)
    }

    /// Internal bridge-facing initializer for the R-17 private-pair DTO.
    /// The DTO is already validated by the bridge; this does not add a
    /// second, conflicting validation layer.
    init(bridgeDto: isolyn.bridge.TileDTO) {
        self.init(dto: bridgeDto)
    }

    fileprivate var dto: isolyn.bridge.TileDTO {
        // Default-construct then assign fields, matching Move.dto below,
        // rather than assuming a labeled memberwise initializer with
        // these exact parameter names is what Cxx interop synthesizes
        // for this struct -- one less thing to guess at without a
        // compiler to check it against.
        var t = isolyn.bridge.TileDTO()
        t.low = Int8(low)
        t.high = Int8(high)
        return t
    }
}

enum ChainSide: Sendable, Hashable {
    case left
    case right

    fileprivate init(dto: isolyn.bridge.ChainSideDTO) {
        self = (dto == .Left) ? .left : .right
    }

    fileprivate var dto: isolyn.bridge.ChainSideDTO {
        self == .left ? .Left : .Right
    }
}

struct Move: Sendable, Equatable, Hashable {
    let tile: Tile
    let side: ChainSide

    init(tile: Tile, side: ChainSide) {
        self.tile = tile
        self.side = side
    }

    fileprivate init(dto: isolyn.bridge.MoveDTO) {
        tile = Tile(dto: dto.tile)
        side = ChainSide(dto: dto.side)
    }

    /// Not fileprivate like the other DTO conversions in this file --
    /// EngineSession.swift (a different file, same module) needs this
    /// directly to build a MoveDTO for bridge_submit_move.
    var dto: isolyn.bridge.MoveDTO {
        var m = isolyn.bridge.MoveDTO()
        m.tile = tile.dto
        m.side = side.dto
        return m
    }
}

// MARK: - Round outcome

enum RoundOutcome: Sendable, Equatable {
    case inProgress
    case dominoVictory(decidingPlayerIndex: Int)
    case closed(decidingPlayerIndex: Int)

    fileprivate init(dto: isolyn.bridge.RoundOutcomeDTO, decidingPlayerIndex: Int32) {
        switch dto {
        case .InProgress: self = .inProgress
        case .DominoVictory: self = .dominoVictory(decidingPlayerIndex: Int(decidingPlayerIndex))
        case .Closed: self = .closed(decidingPlayerIndex: Int(decidingPlayerIndex))
        @unknown default:
            bridgeDTOLogger.fault("Unknown RoundOutcomeDTO raw value from bridge -- treating as inProgress; Swift/C++ enum surfaces have diverged")
            self = .inProgress
        }
    }
}

// MARK: - Snapshot

/// A player-scoped view of a session at one point in time. During play only
/// the requesting player's OWN hand is visible; other players' hands are
/// sizes only, matching SnapshotDTO exactly (see IsolynBridge.hpp's
/// "Snapshot model" comment for why this is enforced on the C++ side). At
/// round end, `revealedHands` carries the actual remaining tiles for every
/// player -- the bridge's explicit reveal-on-end path.
struct GameSnapshot: Sendable {
    let stateVersion: UInt64
    let mode: MatchFormat
    let playerCount: Int
    let requestingPlayerIndex: Int
    let currentPlayerIndex: Int
    let ownHand: [Tile]
    /// Index p is this player's hand SIZE, or 0 at requestingPlayerIndex
    /// (see ownHand instead). Never tile identities for anyone else.
    let otherHandSizes: [Int]
    let chain: [Tile]
    let chainLeftEnd: Int?
    let chainRightEnd: Int?
    let boneyardDrawableCount: Int
    /// Always empty: R-17 keeps the locked pair private, and the bridge no
    /// longer reveals it when the draw pile empties. The field remains for
    /// the future private-look path (a player holding one tile may look).
    let boneyardLockedTiles: [Tile]
    /// Reveal-on-end: per-player remaining pip values, ALL ZERO while the
    /// round is live -- mirrors SnapshotDTO's reveal semantics exactly.
    let finalHandValues: [Int]
    /// Reveal-on-end: actual remaining tiles per player, populated only when
    /// the round has finished. Empty while play is live.
    let revealedHands: [[Tile]]
    let roundOutcome: RoundOutcome
    /// Populated only when currentPlayerIndex == requestingPlayerIndex --
    /// empty otherwise, matching SnapshotDTO (there's no legitimate
    /// reason to compute legal moves for a hand the requester can't see).
    let legalMoves: [Move]

    fileprivate init?(dto: isolyn.bridge.SnapshotDTO) {
        guard dto.status == .Ok else { return nil }
        var mutableDto = dto
        stateVersion = dto.stateVersion
        mode = {
            switch dto.mode {
            case .OneVsOne: return .oneVOne
            case .OneVsOneVsOne: return .oneVOneVOne
            case .TwoVsTwo: return .twoVTwo
            @unknown default:
                bridgeDTOLogger.fault("Unknown GameModeDTO raw value from bridge -- defaulting to oneVOne; Swift/C++ enum surfaces have diverged")
                return .oneVOne
            }
        }()
        playerCount = Int(dto.playerCount)
        requestingPlayerIndex = Int(dto.requestingPlayerIndex)
        currentPlayerIndex = Int(dto.currentPlayerIndex)

        let ownHandTiles: [isolyn.bridge.TileDTO] = withTupleAsArray(
            &mutableDto.ownHand, capacity: Int(isolyn.bridge.kTotalTileCount),
            count: Int(dto.ownHandCount), as: isolyn.bridge.TileDTO.self)
        ownHand = ownHandTiles.map { Tile(dto: $0) }

        otherHandSizes = withTupleAsArray(
            &mutableDto.otherHandSizes, capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(isolyn.bridge.kMaxPlayers), as: Int32.self
        ).map { Int($0) }

        var mutableChain = dto.chain
        let chainTiles: [isolyn.bridge.TileDTO] = withTupleAsArray(
            &mutableChain.tiles, capacity: Int(isolyn.bridge.kTotalTileCount),
            count: Int(dto.chain.count), as: isolyn.bridge.TileDTO.self)
        chain = chainTiles.map { Tile(dto: $0) }
        chainLeftEnd = dto.chain.count > 0 ? Int(dto.chain.leftEnd) : nil
        chainRightEnd = dto.chain.count > 0 ? Int(dto.chain.rightEnd) : nil

        boneyardDrawableCount = Int(dto.boneyardDrawableCount)

        var mutableLocked = dto
        let lockedTiles: [isolyn.bridge.TileDTO] = withTupleAsArray(
            &mutableLocked.boneyardLockedTiles, capacity: 2,
            count: Int(dto.boneyardLockedCount), as: isolyn.bridge.TileDTO.self)
        boneyardLockedTiles = lockedTiles.map { Tile(dto: $0) }

        var mutableReveal = dto
        finalHandValues = withTupleAsArray(
            &mutableReveal.finalHandValues,
            capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(isolyn.bridge.kMaxPlayers),
            as: Int32.self
        ).map { Int($0) }

        let revealCounts = withTupleAsArray(
            &mutableReveal.finalHandCounts,
            capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(isolyn.bridge.kMaxPlayers),
            as: Int32.self
        ).map { Int($0) }
        let revealFlat: [isolyn.bridge.TileDTO] = withTupleAsArray(
            &mutableReveal.finalRevealedTiles,
            capacity: Int(isolyn.bridge.kMaxPlayers * isolyn.bridge.kTotalTileCount),
            count: Int(isolyn.bridge.kMaxPlayers * isolyn.bridge.kTotalTileCount),
            as: isolyn.bridge.TileDTO.self
        )
        var hands: [[Tile]] = Array(repeating: [], count: Int(isolyn.bridge.kMaxPlayers))
        for p in 0..<Int(isolyn.bridge.kMaxPlayers) {
            let count = revealCounts[p]
            guard count > 0 else { continue }
            let start = p * Int(isolyn.bridge.kTotalTileCount)
            let end = min(start + count, revealFlat.count)
            guard start < end else { continue }
            hands[p] = revealFlat[start..<end].map { Tile(dto: $0) }
        }
        revealedHands = hands

        roundOutcome = RoundOutcome(dto: dto.roundOutcome, decidingPlayerIndex: dto.decidingPlayerIndex)

        var mutableLegal = dto.legalMovesForRequestingPlayer
        let legalMoveDtos: [isolyn.bridge.MoveDTO] = withTupleAsArray(
            &mutableLegal.moves, capacity: Int(isolyn.bridge.kMaxLegalMoves),
            count: Int(dto.legalMovesForRequestingPlayer.count), as: isolyn.bridge.MoveDTO.self)
        legalMoves = legalMoveDtos.map { Move(dto: $0) }
    }

    /// Not fileprivate like the init above -- EngineSession.swift (a
    /// different file, same module) calls this directly.
    static func fromDtoOrThrow(_ dto: isolyn.bridge.SnapshotDTO) throws -> GameSnapshot {
        guard let snap = GameSnapshot(dto: dto) else {
            throw BridgeError(status: dto.status, diagnostic: "")
        }
        return snap
    }
}

// MARK: - Test construction seam (FIX-28 / remediation roadmap P2d)

extension GameSnapshot {
    /// Headless-test construction seam (audit OA-4, remediation roadmap
    /// P2d). Why this exists, stated plainly: SnapshotDTO's fixed C arrays
    /// import into Swift as TUPLES, which cannot be filled element-by-
    /// element programmatically, and `init?(dto:)` being declared in the
    /// struct's primary body suppresses the memberwise initializer -- so
    /// WITHOUT this, no headless test anywhere can fabricate a controlled
    /// GameSnapshot (real sessions deal real CSPRNG hands; resolver/layout
    /// math tests need CONTROLLED hands). This is the one sanctioned
    /// escape hatch: internal (reachable under @testable), never for
    /// production paths -- production code obtains snapshots exclusively
    /// through EngineSession.snapshot(for:) so hidden-information
    /// enforcement stays bridge-side and structural, exactly as before.
    ///
    /// Contract mirrors buildSnapshot's C++ guarantees: otherHandSizes and
    /// finalHandValues passed as-is (tests pass playerCount-sized arrays;
    /// nothing padded or invented here), chainLeftEnd/chainRightEnd nil
    /// iff chain is empty.
    init(stateVersion: UInt64,
         mode: MatchFormat,
         playerCount: Int,
         requestingPlayerIndex: Int,
         currentPlayerIndex: Int,
         ownHand: [Tile],
         otherHandSizes: [Int],
         chain: [Tile],
         chainLeftEnd: Int?,
         chainRightEnd: Int?,
         boneyardDrawableCount: Int,
         boneyardLockedTiles: [Tile] = [],
         finalHandValues: [Int],
         roundOutcome: RoundOutcome,
         legalMoves: [Move],
         revealedHands: [[Tile]] = []) {
        self.stateVersion = stateVersion
        self.mode = mode
        self.playerCount = playerCount
        self.requestingPlayerIndex = requestingPlayerIndex
        self.currentPlayerIndex = currentPlayerIndex
        self.ownHand = ownHand
        self.otherHandSizes = otherHandSizes
        self.chain = chain
        self.chainLeftEnd = chainLeftEnd
        self.chainRightEnd = chainRightEnd
        self.boneyardDrawableCount = boneyardDrawableCount
        self.boneyardLockedTiles = boneyardLockedTiles
        self.finalHandValues = finalHandValues
        self.revealedHands = revealedHands
        self.roundOutcome = roundOutcome
        self.legalMoves = legalMoves
    }
}

// MARK: - Match orchestration

/// The running state of a multi-round match after one completed round was
/// recorded. Scores are per PARTICIPANT (players for 1v1/1v1v1, teams for 2v2)
/// -- the same semantics ScoreSystem itself uses.
struct MatchOutcome: Sendable, Equatable {
    let participantCount: Int
    /// The set that the recorded round belonged to. Scores reset when the
    /// next set begins; this value is the set the round was played in.
    let scoresPerParticipant: [Int]
    /// Completed sets per participant (teams for 2v2).
    let setWinsPerParticipant: [Int]
    let setNumber: Int
    let setsToWin: Int
    /// True once a participant has reached the chosen set count (3 or 4).
    let matchEnded: Bool
    /// Valid only when matchEnded; nil otherwise.
    let winnerParticipantIndex: Int?
    /// Valid only when setEnded; nil otherwise.
    let setWinnerParticipantIndex: Int?
    /// True when this round reached the 151 threshold and ended its set.
    let setEnded: Bool
    /// True when the next round must be a fresh set (double-six ritual).
    let nextRoundStartsSet: Bool
    /// Who opens the NEXT round; -1 when a new set's ritual decides instead.
    let nextRoundStarterIndex: Int
    /// R-22: how many seats are still alive in the current set (1v1v1 only;
    /// every seat is active in the other modes).
    let activeParticipantCount: Int
    let activePerParticipant: [Bool]
    let eliminatedPerParticipant: [Bool]
    /// The participant who crossed 151 this round, when one did.
    let lastEliminatedParticipantIndex: Int?
    /// True when the next round is the carried-points 1v1 between survivors.
    let nextRoundIsSurvivor: Bool

    static func fromDtoOrThrow(_ dto: isolyn.bridge.MatchResultDTO) throws -> MatchOutcome {
        guard dto.status == .Ok else {
            throw BridgeError(status: dto.status, diagnostic: "match record failed")
        }
        var mutableDto = dto
        let scores: [Int32] = withTupleAsArray(
            &mutableDto.scoresPerParticipant,
            capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(dto.participantCount),
            as: Int32.self
        ).map { $0 }
        var mutableWinsDto = dto
        let setWins: [Int32] = withTupleAsArray(
            &mutableWinsDto.setWinsPerParticipant,
            capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(dto.participantCount),
            as: Int32.self
        ).map { $0 }
        var mutableActiveDto = dto
        let active: [Int32] = withTupleAsArray(
            &mutableActiveDto.activePerParticipant,
            capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(dto.participantCount),
            as: Int32.self
        )
        let eliminated: [Int32] = withTupleAsArray(
            &mutableActiveDto.eliminatedPerParticipant,
            capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(dto.participantCount),
            as: Int32.self
        )
        return MatchOutcome(
            participantCount: Int(dto.participantCount),
            scoresPerParticipant: scores.map { Int($0) },
            setWinsPerParticipant: setWins.map { Int($0) },
            setNumber: Int(dto.setNumber),
            setsToWin: Int(dto.setsToWin),
            matchEnded: dto.matchEnded,
            winnerParticipantIndex: dto.matchEnded ? Int(dto.winnerParticipantIndex) : nil,
            setWinnerParticipantIndex: dto.setEnded ? Int(dto.setWinnerParticipantIndex) : nil,
            setEnded: dto.setEnded,
            nextRoundStartsSet: dto.nextRoundStartsSet,
            nextRoundStarterIndex: Int(dto.nextRoundStarterIndex),
            activeParticipantCount: Int(dto.activeParticipantCount),
            activePerParticipant: active.map { $0 != 0 },
            eliminatedPerParticipant: eliminated.map { $0 != 0 },
            lastEliminatedParticipantIndex: dto.lastEliminatedParticipantIndex >= 0
                ? Int(dto.lastEliminatedParticipantIndex) : nil,
            nextRoundIsSurvivor: dto.nextRoundIsSurvivor
        )
    }
}

// MARK: - Errors

enum BridgeError: Error, Sendable, Equatable {
    case invalidRequest
    case invalidMove
    case roundAlreadyOver
    case sessionClosed
    case staleRequest
    case notYourTurn
    case noLegalMove
    case boneyardEmpty
    case engineFailure(diagnostic: String)
    case bridgeFailure(diagnostic: String)

    init(status: isolyn.bridge.BridgeStatus, diagnostic: String) {
        switch status {
        case .InvalidRequest: self = .invalidRequest
        case .InvalidMove: self = .invalidMove
        case .SessionClosed: self = .sessionClosed
        case .StaleRequest: self = .staleRequest
        case .NotYourTurn: self = .notYourTurn
        case .NoLegalMove: self = .noLegalMove
        case .BoneyardEmpty: self = .boneyardEmpty
        case .RoundAlreadyOver: self = .roundAlreadyOver
        case .ModeMismatch:
            // A caller bug, not a user-facing condition: the app never records a
            // round into a match of a different mode. Keep it visible as an
            // internal failure rather than silently accepting the result.
            self = .bridgeFailure(diagnostic: "session mode does not match match mode")
        case .EngineFailure: self = .engineFailure(diagnostic: diagnostic)
        case .BridgeFailure: self = .bridgeFailure(diagnostic: diagnostic)
        case .Ok:
            self = .bridgeFailure(diagnostic: "BridgeError constructed from a BridgeStatus.Ok result -- caller bug in this Swift layer, not a real bridge failure")
        @unknown default:
            bridgeDTOLogger.fault("Unrecognized BridgeStatus from bridge -- surfacing as generic bridgeFailure; Swift/C++ enum surfaces have diverged")
            self = .bridgeFailure(diagnostic: "unrecognized BridgeStatus")
        }
    }
}

// MARK: - Command / analysis outcomes

/// The result of any successful mutating command. Swift call sites throw
/// BridgeError instead of getting this back wrapped in a Result --
/// CommandResultDTO.status already IS a Result in everything but name,
/// so there's no reason to make every caller match on both that and a
/// separate Swift error type.
struct CommandOutcome: Sendable {
    let newStateVersion: UInt64
    let roundOutcome: RoundOutcome

    fileprivate init(dto: isolyn.bridge.CommandResultDTO) {
        newStateVersion = dto.newStateVersion
        roundOutcome = RoundOutcome(dto: dto.roundOutcome, decidingPlayerIndex: dto.decidingPlayerIndex)
    }

    /// Not fileprivate like the init above -- EngineSession.swift (a
    /// different file, same module) calls this directly.
    static func fromDtoOrThrow(_ dto: isolyn.bridge.CommandResultDTO) throws -> CommandOutcome {
        guard dto.status == .Ok else {
            var mutableDto = dto
            let bytes: [Int8] = withTupleAsArray(&mutableDto.diagnosticMessage, capacity: 128, count: 128, as: Int8.self)
            let terminatorIndex = bytes.firstIndex(of: 0) ?? bytes.count
            let diagnostic = String(decoding: bytes[..<terminatorIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            throw BridgeError(status: dto.status, diagnostic: diagnostic)
        }
        return CommandOutcome(dto: dto)
    }
}

/// Only ever throws for .engineFailure/.bridgeFailure in practice -- see
/// EngineSession.requestAnalysis's own comment for why every other
/// BridgeStatus isn't reachable here (this type is only ever constructed
/// from a snapshot handle EngineSession itself already validated).
struct AnalysisOutcome: Sendable {
    let stateVersionAnalyzed: UInt64
    /// False if cancellation cut this short -- see
    /// SearchEngine::chooseBestMove's cancelRequested contract
    /// (Sources/IsolynEngine/include/SearchEngine.hpp). samplesCompleted
    /// == 0 means treat this as "no real analysis happened," not a
    /// lower-confidence-but-real recommendation -- don't display it.
    let completed: Bool
    let samplesCompleted: Int
    let samplesConfigured: Int
    let recommendedMove: Move
    /// True when the engine chose a voluntary draw. `recommendedMove` is then
    /// only a legal placeholder and must not be submitted: apply a draw, which
    /// does not consume the turn, and re-read the snapshot.
    let isDraw: Bool
    /// One entry per player, EvaluationEngine score.
    let expectedValuePerPlayer: [Double]

    fileprivate init(dto: isolyn.bridge.AnalysisResultDTO) {
        stateVersionAnalyzed = dto.stateVersionAnalyzed
        completed = dto.completed
        samplesCompleted = Int(dto.samplesCompleted)
        samplesConfigured = Int(dto.samplesConfigured)
        recommendedMove = Move(dto: dto.recommendedMove)
        isDraw = dto.isDraw
        var mutableDto = dto
        expectedValuePerPlayer = withTupleAsArray(
            &mutableDto.expectedValuePerPlayer, capacity: Int(isolyn.bridge.kMaxPlayers),
            count: Int(dto.playerCount), as: Double.self)
    }

    /// Not fileprivate like the init above -- EngineSession.swift (a
    /// different file, same module) calls this directly.
    static func fromDtoOrThrow(_ dto: isolyn.bridge.AnalysisResultDTO) throws -> AnalysisOutcome {
        guard dto.status == .Ok else {
            throw BridgeError(status: dto.status, diagnostic: "analysis failed")
        }
        return AnalysisOutcome(dto: dto)
    }
}
