import SwiftUI

/// A physical acknowledgment that something came out of the draw pile:
/// face-down dominoes lift off the row's open end and travel to the seat that
/// drew them. This is presentation only; the engine snapshot is already
/// authoritative, so a dropped frame can never alter game state.
struct DrawFlightView: View {
    let event: GameViewModel.DrawEvent
    let from: CGPoint
    let to: CGPoint
    let landsInHand: Bool
    let appearance: DominoAppearance

    var body: some View {
        let flights = min(max(event.count, 1), 3)
        ZStack {
            ForEach(0..<flights, id: \.self) { index in
                FlyingFaceDownTile(
                    appearance: appearance,
                    from: CGPoint(
                        x: from.x + CGFloat(index) * 3,
                        y: from.y - CGFloat(index) * 2
                    ),
                    to: to,
                    landsInHand: landsInHand,
                    delay: Double(index) * 0.06
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct FlyingFaceDownTile: View {
    let appearance: DominoAppearance
    let from: CGPoint
    let to: CGPoint
    let landsInHand: Bool
    let delay: Double

    @State private var progress: CGFloat = 0

    private var dx: CGFloat { to.x - from.x }
    private var dy: CGFloat { to.y - from.y }
    private var lift: CGFloat {
        min(74, max(16, hypot(dx, dy) * 0.11))
    }

    private var easedProgress: CGFloat {
        1 - pow(max(0, 1 - progress), 3)
    }

    private var scale: CGFloat {
        if landsInHand {
            // Begin at the pile's physical size, then grow into the hand.
            return 0.79 + 0.65 * easedProgress
        }
        // Computer draws settle smaller into the acting seat.
        return 0.79 - 0.09 * easedProgress
    }

    var body: some View {
        BoneyardFaceDownTile(appearance: appearance, height: 27)
            .shadow(
                color: .black.opacity(0.28 + 0.18 * sin(progress * CGFloat.pi)),
                radius: 3 + 7 * sin(progress * CGFloat.pi),
                y: 2 + 4 * sin(progress * CGFloat.pi)
            )
            .scaleEffect(scale)
            .rotationEffect(.degrees(Double(progress) * (landsInHand ? 8 : -5)))
            .position(from)
            .offset(
                x: dx * progress,
                y: dy * progress - sin(progress * CGFloat.pi) * lift
            )
            .opacity(progress > 0.88 ? max(0, (1 - progress) / 0.12) : 1)
            .onAppear {
                withAnimation(
                    .timingCurve(0.16, 0.82, 0.22, 1, duration: 0.58)
                        .delay(delay)
                ) {
                    progress = 1
                }
            }
    }
}
