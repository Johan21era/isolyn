import SwiftUI
import Observation

/// Explicit camera state for the game board's pan navigation.
/// Isolated from game state, hover knowledge, and appearance — a camera drag
/// never triggers engine computation or invalidates analytical caches.
///
/// Coordinate model: world coordinates are logical board positions;
/// viewport coordinates are what SwiftUI renders. `offsetX/Y` is the
/// translation from canonical (zero-offset) framing. Future zoom = a scale
/// multiplier applied before offset; current architecture leaves room for it.
@MainActor
@Observable
final class BoardCamera {

    // MARK: - Translation

    private(set) var offsetX: CGFloat = 0
    private(set) var offsetY: CGFloat = 0

    // MARK: - Drag session

    /// The origin point when the active drag started.
    fileprivate var dragOriginX: CGFloat = 0
    fileprivate var dragOriginY: CGFloat = 0

    /// True between pointer-down and release during an active pan.
    private(set) var isDragging = false

    // MARK: - Velocity / inertia

    /// Last few drag samples for velocity estimation.
    fileprivate var recentSamples: [(time: TimeInterval, x: CGFloat, y: CGFloat)] = []
    private var inertialTask: Task<Void, Never>?

    // MARK: - Bounds

    /// Maximum absolute translation in each direction.
    /// The board cannot be panned beyond ±maxOffset.
    ///
    /// FIX-28 (audit OA-4 / remediation roadmap P2c): these are no longer
    /// anonymous magic numbers -- SnakeChainBoard raises them to cover the
    /// POST-scale residual overflow of unusually long chains, so panning
    /// can always reach the tail. Defaults preserved exactly; bounds are
    /// only ever raised, never shrunk, by layout.
    static let defaultMaxOffsetX: CGFloat = 300
    static let defaultMaxOffsetY: CGFloat = 200
    var maxOffsetX: CGFloat = BoardCamera.defaultMaxOffsetX
    var maxOffsetY: CGFloat = BoardCamera.defaultMaxOffsetY

    /// How aggressively the camera resists at boundaries (0–1).
    var boundaryResistance: Double = 0.3

    // MARK: - Tuning constants (centralized, not scattered)

    static let dragThreshold: CGFloat = 5
    static let maxInertialVelocity: CGFloat = 2500  // pts/sec
    static let dampingFactor: Double = 0.92          // per frame at 60fps
    static let settleThreshold: CGFloat = 0.5       // stop when below this velocity

    // MARK: - Reset

    func reset() {
        inertialTask?.cancel()
        inertialTask = nil
        withAnimation(.easeInOut(duration: 0.4)) {
            offsetX = 0
            offsetY = 0
        }
    }

    // MARK: - Drag lifecycle

    func beginDrag(at location: CGPoint) {
        inertialTask?.cancel()
        inertialTask = nil
        isDragging = true
        dragOriginX = offsetX
        dragOriginY = offsetY
        recentSamples.removeAll()
        recordSample(location)
    }

    func updateDrag(translation: CGSize) {
        guard isDragging else { return }
        var newX = dragOriginX + translation.width
        var newY = dragOriginY + translation.height

        // Boundary resistance: compress movement near edges rather than hard-stop
        if abs(newX) > maxOffsetX {
            let over = abs(newX) - maxOffsetX
            let sign: CGFloat = newX > 0 ? 1 : -1
            newX = sign * (maxOffsetX + over * CGFloat(boundaryResistance))
        }
        if abs(newY) > maxOffsetY {
            let over = abs(newY) - maxOffsetY
            let sign: CGFloat = newY > 0 ? 1 : -1
            newY = sign * (maxOffsetY + over * CGFloat(boundaryResistance))
        }

        offsetX = newX
        offsetY = newY
    }

    func endDrag(lastLocation: CGPoint?) {
        guard isDragging else { return }
        isDragging = false
        if let loc = lastLocation { recordSample(loc) }
        startInertia()
    }

    // MARK: - Private

    private func recordSample(_ location: CGPoint) {
        let now = CACurrentMediaTime()
        recentSamples.append((now, location.x, location.y))
        // Keep last ~6 samples (~100ms of history)
        if recentSamples.count > 6 { recentSamples.removeFirst() }
    }

    /// Estimates velocity (pts/sec) from recent samples and starts decaying animation.
    private func startInertia() {
        guard recentSamples.count >= 2 else { return }
        let first = recentSamples.first!
        let last = recentSamples.last!
        let dt = last.time - first.time
        guard dt > 0.001 else { return }

        var vx = (last.x - first.x) / dt
        var vy = (last.y - first.y) / dt

        // Clamp maximum inertial velocity
        let magnitude = sqrt(vx * vx + vy * vy)
        if magnitude > Self.maxInertialVelocity {
            let scale = Self.maxInertialVelocity / magnitude
            vx *= scale; vy *= scale
        }

        // Start decay loop if velocity is meaningful
        guard sqrt(vx * vx + vy * vy) > Self.settleThreshold else { return }

        inertialTask = Task { [weak self] in
            var velX = vx, velY = vy
            let frameDuration: Double = 1.0 / 60.0
            while !Task.isCancelled {
                guard let self else { return }
                self.offsetX += velX * frameDuration
                self.offsetY += velY * frameDuration

                // Hard clamp to bounds during inertia
                self.offsetX = max(-self.maxOffsetX, min(self.maxOffsetX, self.offsetX))
                self.offsetY = max(-self.maxOffsetY, min(self.maxOffsetY, self.offsetY))

                velX *= Self.dampingFactor
                velY *= Self.dampingFactor

                if sqrt(velX * velX + velY * velY) < Self.settleThreshold { break }
                try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
            }
        }
    }
}
