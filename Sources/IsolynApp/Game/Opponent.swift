import Foundation
import IsolynEngineBridge

/// Who controls the other seats in a match. The human always sits at player 0.
/// In 2v2 the partner seat (2) must also be computer-controlled in this
/// single-human mode; otherwise the round stalls whenever the partner is due
/// to act, since the UI is always requested from player 0's perspective.
enum OpponentMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case human = "Hot Seat"
    case computer = "Computer"

    var id: String { rawValue }
}

/// Public strength labels, ordered weakest to strongest. The actual
/// depth/determinization numbers come from the C++ DifficultyModel through the
/// bridge -- this enum is presentation only, so the app cannot drift from the
/// engine's calibrated tier mapping.
///
/// Order: Casual < Club < Elite < Expert < Master < Legendary < Mythical.
enum AILevel: Int, CaseIterable, Identifiable, Sendable {
    case casual = 100
    case club = 900
    case elite = 1600
    case expert = 2300
    case master = 3000
    case legendary = 5000
    case mythical = 10000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .casual: return "Casual"
        case .club: return "Club"
        case .elite: return "Elite"
        case .expert: return "Expert"
        case .master: return "Master"
        case .legendary: return "Legendary"
        case .mythical: return "Mythical"
        }
    }

    /// The deeper tiers need a longer wall-clock budget because their depth is
    /// a ceiling, not a guaranteed completed depth. These values are product
    /// latency choices, not strength claims.
    var thinkingTimeMs: Int32 {
        switch self {
        case .legendary, .mythical: return 15_000
        default: return 3_000
        }
    }
}

struct AIProfile: Equatable, Sendable {
    let strength: Int
    let maxDepthPlies: Int32
    let determinizationCount: Int32

    init(level: AILevel) {
        let dto = isolyn.bridge.bridge_difficulty_profile(Int32(level.rawValue))
        strength = Int(dto.strength)
        maxDepthPlies = dto.maxDepthPlies
        determinizationCount = dto.determinizationCount
    }
}

extension MatchFormat {
    /// Player 0 is always human. 2v2 partners sit opposite (0/2 and 1/3), so
    /// the computer controls seats 1, 2 and 3 -- including the human's partner.
    func isComputerSeat(_ seat: Int, for opponent: OpponentMode) -> Bool {
        guard opponent == .computer else { return false }
        switch self {
        case .oneVOne:
            return seat == 1
        case .oneVOneVOne:
            return seat != 0
        case .twoVTwo:
            return seat != 0
        }
    }
}