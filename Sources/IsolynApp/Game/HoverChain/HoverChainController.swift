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
    private(set) var activeNodeKind: HoverChainNodeKind = .complete
    private(set) var isVisible = false
    private(set) var isSuspended = false // true during camera drag

    /// Pending hover-out dismissal (FIX-26 / roadmap N-3). The overlay
    /// used to have NO exit path: once an end-zone was hovered the panel
    /// stuck forever, because every dismiss site was commented out on
    /// the theory that "the overlay has its own exit logic" -- which was
    /// never built. Now: leaving both zone and overlay schedules a
    /// grace-period dismissal; re-entering either cancels it; playing a
    /// tile or the explicit close button dismisses immediately.
    @ObservationIgnored private var dismissalTask: Task<Void, Never>?

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

    /// Schedules dismissal after a short grace period (default 250ms) --
    /// long enough that moving from an end-zone across the small gap
    /// onto the overlay doesn't blink the panel away.
    func scheduleDismissal(afterNanoseconds: UInt64 = 250_000_000) {
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: afterNanoseconds)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Pointer came back over the zone or the overlay -- keep it open.
    func cancelScheduledDismissal() {
        dismissalTask?.cancel()
        dismissalTask = nil
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
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
