import SwiftUI
import IsolynEngineBridge

/// The played chain, oriented for display. Per-tile orientation is DERIVED
/// here by walking from the known left end -- exactly the derivation the
/// engine documents (orientation is never stored state), so the visual always
/// agrees with `Chain`'s own truth: adjacent displayed pips match, doubles sit
/// perpendicular.
struct ChainView: View {
    let snapshot: GameSnapshot

    /// One display-ready tile: explicit left/right pips plus double flag.
    private struct DisplayTile: Identifiable {
        let id: Int          // index along the chain -- stable & unique
        let left: Int
        let right: Int
        let isDouble: Bool
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(displayTiles) { tile in
                        TileView(
                            displayingLeft: tile.left, right: tile.right,
                            isDouble: tile.isDouble
                        )
                        .id(tile.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .onAppear { scrollToLatest(proxy) }
            .onChange(of: snapshot.chain.count) { _ in scrollToLatest(proxy) }
        }
        .frame(minHeight: 76)
    }

    private var displayTiles: [DisplayTile] {
        var result: [DisplayTile] = []
        guard let leftEnd = snapshot.chainLeftEnd else { return result }

        var touching = leftEnd
        for (index, tile) in snapshot.chain.enumerated() {
            // Every chain tile touches its neighbour by construction; if a
            // malformed snapshot ever disagreed, fall back to canonical order
            // rather than lying about pips.
            guard tile.hasFace(touching) else {
                result.append(DisplayTile(id: index, left: tile.low, right: tile.high,
                                          isDouble: tile.isDoubleTile))
                continue
            }
            let other = tile.otherFace(touching)
            result.append(DisplayTile(id: index, left: touching, right: other,
                                      isDouble: tile.isDoubleTile))
            touching = other
        }
        return result
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = snapshot.chain.last else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(snapshot.chain.count - 1, anchor: .trailing)
        }
        _ = last
    }
}

private extension Tile {
    var isDoubleTile: Bool { low == high }
}
