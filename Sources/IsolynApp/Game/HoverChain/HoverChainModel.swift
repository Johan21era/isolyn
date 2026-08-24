import Foundation
import IsolynEngineBridge

// MARK: - Tile Knowledge Classification

/// One resolved knowledge state per physical domino.
/// Exactly one classification applies per tile — precedence enforced in
/// `TileKnowledgeResolver.resolve()`. Never two contradictory states.
enum TileKnowledge: Equatable, Hashable, Sendable {
    /// Known to have been played (on the chain). Authoritative fact.
    case historical
    /// Authoritatively in my hand. Authoritative fact.
    case mine
    /// Not played, not mine, no inference possible. Honest absence of certainty.
    case unknown
    /// Inferred locked/unavailable — defensible state calculation says nobody
    /// can play this tile this round.
    case lockedOff
    /// Engine/belief system predicts opponent possession above threshold.
    /// NOT certain. Visually distinct from known facts.
    case predictedOpponent(probability: Double)
}

// MARK: - Hover Chain Node Kind

/// The six progressive analytical views of one number family.
enum HoverChainNodeKind: Int, CaseIterable, Sendable {
    case baseUninformed = 0
    case historicalInformed = 1
    case presentInformed = 2
    case lockedOff = 3
    case predictive = 4
    case complete = 5

    var label: String {
        switch self {
        case .baseUninformed: return "Base"
        case .historicalInformed: return "Historical"
        case .presentInformed: return "Present"
        case .lockedOff: return "Locked"
        case .predictive: return "Predictive"
        case .complete: return "Complete"
        }
    }

    var description: String {
        switch self {
        case .baseUninformed: return "Full number family — no ownership or history shown."
        case .historicalInformed: return "Which family members have been played."
        case .presentInformed: return "Current location of unplayed members."
        case .lockedOff: return "Members inferred locked-off under known conditions."
        case .predictive: return "Engine predicts opponent ownership where confident."
        case .complete: return "All classifications fused into one resolved picture."
        }
    }
}

// MARK: - Per-Domino Display Entry

/// One row in the hover chain overlay: the tile plus its classification
/// for the currently active node.
struct HoverChainEntry: Identifiable, Equatable, Sendable {
    let id: Int // stable index within the number family
    let low: Int
    let high: Int
    let knowledge: TileKnowledge

    var label: String { "\(high)-\(low)" }

    var isDouble: Bool { low == high }
}

// MARK: - Hover Chain Model

/// The full hover-chain state for one target number.
struct HoverChain: Sendable {
    let targetNumber: Int
    let entries: [HoverChainEntry]
    let activeNodeKind: HoverChainNodeKind
    let gameStateVersion: UInt64

    /// Returns a filtered/annotated copy of entries appropriate for the given node kind.
    static func resolve(
        entries: [HoverChainEntry],
        for kind: HoverChainNodeKind,
        targetNumber: Int,
        stateVersion: UInt64
    ) -> HoverChain {
        // The entries already carry their resolved knowledge classification;
        // each node kind controls WHICH classifications are visible/emphasized.
        HoverChain(
            targetNumber: targetNumber,
            entries: entries,
            activeNodeKind: kind,
            gameStateVersion: stateVersion
        )
    }
}

/// Centralized predictive threshold policy — never hardcode in views.
struct PredictivePolicy: Sendable {
    /// Minimum probability before a tile is classified as predicted opponent.
    static let predictionThreshold: Double = 0.35
    /// Below this, the tile stays unknown even after prediction runs.
    static let minimumEvidenceThreshold: Double = 0.15
}
