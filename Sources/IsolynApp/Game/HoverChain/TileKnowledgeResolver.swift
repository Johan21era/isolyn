import Foundation
import IsolynEngineBridge

/// Resolves the knowledge classification for every member of a number family,
/// using ONLY authoritative snapshot data. This is the adapter/query boundary
/// between the bridge's SnapshotDTO and the UI's hover-chain overlay.
///
/// Precedence (deterministic, no contradictions possible):
///   1. historical (on the chain = played)
///   2. mine (in own hand)
///   3. lockedOff (unplayed, not mine, can't match either end, yard dry)
///   4. predictedOpponent (probability above threshold)
///   5. unknown (none of the above)
///
/// The predictive classification computes exact uniform probability from
/// authoritative counts: P(opponent holds tile) = opponent_hand / total_unseen.
/// This mirrors BeliefState's construction math without exposing C++ internals.
struct TileKnowledgeResolver {

    let snapshot: GameSnapshot
    /// The requesting player index whose perspective this resolver reflects.
    let believerIndex: Int

    // MARK: - Number Family

    /// All 7 dominoes containing the target pip value. Pure set logic —
    /// zero game-state dependency, so safe to call during camera drag.
    static func numberFamily(for pip: Int) -> [(low: Int, high: Int)] {
        guard pip >= 0, pip <= 6 else { return [] }
        return (0...pip).map { (low: $0, high: pip) }
                + ((pip + 1)...6).map { (low: pip, high: $0) }
    }

    // MARK: - Classification

    /// Resolves every number-family member into a HoverChainEntry with its
    /// knowledge classification. Deterministic given the same snapshot.
    func resolveFamily(for targetNumber: Int) -> [HoverChainEntry] {
        let family = Self.numberFamily(for: targetNumber)
        return family.enumerated().map { index, pair in
            let tile = Tile(low: pair.low, high: pair.high)
            let knowledge = classify(tile)
            return HoverChainEntry(id: index, low: pair.low, high: pair.high, knowledge: knowledge)
        }
    }

    // MARK: - Individual Classification (precedence chain)

    private func classify(_ tile: Tile) -> TileKnowledge {
        // 1. Historical — is it on the chain?
        if isPlayed(tile) { return .historical }

        // 2. Mine — is it in my hand?
        if isInMyHand(tile) { return .mine }

        // 3. Locked off — can nobody play this?
        if isLockedOff(tile) { return .lockedOff }

        // 4. Predicted opponent — does probability clear the threshold?
        if let prob = predictedOpponentProbability(tile), prob >= PredictivePolicy.predictionThreshold {
            return .predictedOpponent(probability: prob)
        }

        // 5. Unknown
        return .unknown
    }

    // MARK: - Authoritative queries

    private func isPlayed(_ tile: Tile) -> Bool {
        snapshot.chain.contains(tile)
    }

    private func isInMyHand(_ tile: Tile) -> Bool {
        snapshot.ownHand.contains(tile)
    }

    /// A tile is defensibly locked off when:
    /// - It hasn't been played and isn't mine (checked by precedence)
    /// - Neither of its pips matches either exposed chain end
    /// - The boneyard has nothing drawable (nobody can draw into a match)
    /// Therefore whoever holds it can NEVER place it this round.
    ///
    /// If the chain is empty, nothing can be locked off yet.
    private func isLockedOff(_ tile: Tile) -> Bool {
        guard snapshot.boneyardDrawableCount == 0 else { return false }
        guard !snapshot.chain.isEmpty,
              let leftEnd = snapshot.chainLeftEnd,
              let rightEnd = snapshot.chainRightEnd else { return false }
        return !tile.hasFace(leftEnd) && !tile.hasFace(rightEnd)
    }

    // MARK: - Predictive (uniform probability from authoritative counts)

    /// Computes P(specific opponent holds this tile) using the same
    /// proportional-distribution math as BeliefState's constructor:
    /// each unseen tile is equally likely to be at any unseen location.
    ///
    /// Returns nil if the computation cannot produce meaningful evidence
    /// (e.g. no unseen tiles, or only one opponent in an ambiguous state).
    private func predictedOpponentProbability(_ tile: Tile) -> Double? {
        // Count total unseen (not on chain, not mine, not revealed-locked boneyard)
        var allTiles = Set<Int>()
        for i in 0..<28 { allTiles.insert(i) }
        for t in snapshot.chain { allTiles.remove(t.index()) }
        for t in snapshot.ownHand { allTiles.remove(t.index()) }

        let totalUnseen = allTiles.count
        guard totalUnseen > 0 else { return nil }
        guard allTiles.contains(tile.index()) else { return nil }

        // Sum of opponent hand sizes (excluding mine which we already removed)
        var opponentHandsTotal = 0
        for (p, size) in snapshot.otherHandSizes.enumerated() {
            if p != snapshot.requestingPlayerIndex { opponentHandsTotal += size }
        }
        guard opponentHandsTotal > 0 else { return nil }

        // Uniform probability per opponent: proportional to their share of unseen hands
        // For simplicity in multi-opponent modes, we compute the COMBINED probability
        // that any opponent holds it, then report the max individual probability.
        let combinedProbability = Double(opponentHandsTotal) / Double(totalUnseen)

        // In 1v1 there's one opponent so combined == individual.
        // In 1v1v1/2v2 we'd need per-opponent breakdown; use combined/numOpponents
        // as the uniform estimate for each.
        let numOpponents = snapshot.playerCount - 1
        guard numOpponents > 0 else { return nil }

        return min(combinedProbability, 1.0) / Double(numOpponents)
    }
}


