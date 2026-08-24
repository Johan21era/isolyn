import SwiftUI
import Observation
import IsolynEngineBridge

/// Manages hover-chain interactive state: which number is targeted,
/// which node is active, whether the overlay is visible/suspended.
@MainActor
@Observable
final class HoverChainController {
    private(set) var activeTarget: Int?
    private(set) var entries: [HoverChainEntry] = []
    private(set) var activeNodeKind: HoverChainNodeKind = .baseUninformed
    private(set) var isVisible = false
    private(set) var isSuspended = false // true during camera drag

    /// Cache key to avoid re-resolution when nothing relevant changed.
    private var lastResolvedVersion: UInt64 = 0
    private var lastResolvedTarget: Int = -1

    func setTarget(_ target: Int?, snapshot: GameSnapshot?) {
        guard !isSuspended else { return }
        guard let target else { dismiss(); return }
        guard target != activeTarget || snapshot?.stateVersion != lastResolvedVersion || !isVisible else { return }

        activeTarget = target
        if let snap = snapshot {
            let resolver = TileKnowledgeResolver(snapshot: snap, believerIndex: snap.requestingPlayerIndex)
            entries = resolver.resolveFamily(for: target)
            lastResolvedVersion = snap.stateVersion
            lastResolvedTarget = target
        }
        isVisible = true
    }

    func rotate() {
        guard isVisible else { return }
        let all = HoverChainNodeKind.allCases
        let next = all[(activeNodeKind.rawValue + 1) % all.count]
        activeNodeKind = next
    }

    func suspend() { isSuspended = true }
    func resume(snapshot: GameSnapshot?, target: Int?) {
        isSuspended = false
        setTarget(target, snapshot: snapshot)
    }

    func dismiss() {
        isVisible = false
        activeTarget = nil
        entries = []
    }

    func invalidate() {
        lastResolvedVersion = 0
        if isVisible { setTarget(activeTarget, snapshot: nil) }
    }

    var builtChain: HoverChain? {
        guard isVisible, let target = activeTarget else { return nil }
        return HoverChain(targetNumber: target, entries: entries,
                          activeNodeKind: activeNodeKind, gameStateVersion: lastResolvedVersion)
    }
}
