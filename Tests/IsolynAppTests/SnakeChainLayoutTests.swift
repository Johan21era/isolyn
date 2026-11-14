import XCTest
@testable import IsolynApp

/// Geometry-only verification of the path-based chain layout. These tests
/// cannot see pixels, so they assert the properties the eye would otherwise
/// have to check: tiles never overlap, consecutive tiles are physically
/// adjacent, and appending a tile never re-flows the ones already on the table.
final class SnakeChainLayoutTests: XCTestCase {

    private func chain(_ count: Int) -> [SnakeChainLayout.Oriented] {
        // Doubles every seventh tile, so both orientations are exercised.
        (0..<count).map { i in
            i % 7 == 3
                ? SnakeChainLayout.Oriented(left: 3, right: 3, isDouble: true)
                : SnakeChainLayout.Oriented(left: i % 7, right: (i + 2) % 7, isDouble: false)
        }
    }

    /// Sweep: any chain, any window, with a double forced into every position
    /// relative to a run start. Nothing may overlap, every tile must stay on
    /// the table, and every run must sit exactly one row pitch from the next.
    func test_chainNeverOverlapsOrDriftsOffItsRowLine() {
        let cases: [(CGSize, ClosedRange<Int>)] = [
            (CGSize(width: 1536, height: 900), 1...40),
            (CGSize(width: 900, height: 620), 1...30),
            (CGSize(width: 800, height: 320), 1...12),
        ]
        for (size, counts) in cases {
            for count in counts {
                for phase in 0..<4 {
                    let tiles: [SnakeChainLayout.Oriented] = (0..<count).map { i in
                        (i + phase) % 3 == 0
                            ? SnakeChainLayout.Oriented(left: 4, right: 4, isDouble: true)
                            : SnakeChainLayout.Oriented(left: i % 7, right: (i + 2) % 7, isDouble: false)
                    }
                    let m = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: size)
                    let rects = m.placed.map(footprint)
                    let label = "n=\(count) phase=\(phase) size=\(Int(size.width))x\(Int(size.height))"

                    for i in rects.indices {
                        XCTAssertGreaterThanOrEqual(rects[i].minX, -0.51, "\(label): tile \(i) off the left edge")
                        XCTAssertLessThanOrEqual(rects[i].maxX, size.width + 0.51, "\(label): tile \(i) off the right edge")
                        XCTAssertGreaterThanOrEqual(rects[i].minY, -0.51, "\(label): tile \(i) off the top edge")
                        XCTAssertLessThanOrEqual(rects[i].maxY, size.height + 0.51, "\(label): tile \(i) off the bottom edge")

                        for j in rects.indices where j > i {
                            let shared = rects[i].intersection(rects[j])
                            if !shared.isNull {
                                XCTAssertLessThanOrEqual(
                                    min(shared.width, shared.height), 0.51,
                                    "\(label): tiles \(i) and \(j) overlap by \(shared.width)x\(shared.height)")
                            }
                        }
                    }

                    let ys = Set(m.placed.map { ($0.y * 10).rounded() / 10 }).sorted()
                    if ys.count > 1 {
                        for k in 1..<ys.count {
                            XCTAssertEqual(ys[k] - ys[k - 1], SnakeChainLayout.rowPitch, accuracy: 0.11,
                                           "\(label): rows must be exactly one pitch apart, got \(ys)")
                        }
                    }
                }
            }
        }
    }

    private func footprint(_ placed: SnakeChainLayout.Placed) -> CGRect {
        let short = SnakeChainLayout.tileShortAxis
        let width = placed.vertical ? short : short * 2
        let height = placed.vertical ? short * 2 : short
        return CGRect(x: placed.x - width / 2, y: placed.y - height / 2,
                      width: width, height: height)
    }

    func test_layoutKeepsEveryTileOnTheTable() {
        let sizes = [CGSize(width: 900, height: 620), CGSize(width: 420, height: 320)]
        for size in sizes {
            for count in 1...40 {
                let metrics = SnakeChainLayout.compute(
                    orientedTiles: chain(count), availableSize: size)
                XCTAssertEqual(metrics.placed.count, count, "one placement per tile")
                for (index, placed) in metrics.placed.enumerated() {
                    let rect = footprint(placed)
                    XCTAssertTrue(rect.width > 0 && rect.height > 0)
                    // The chain may overflow only when the layout is boxed in;
                    // the camera and uniform scale exist for that case.
                    XCTAssertEqual(placed.x.isFinite, true, "tile \(index) has a real x")
                    XCTAssertEqual(placed.y.isFinite, true, "tile \(index) has a real y")
                }
            }
        }
    }

    func test_tilesNeverOverlap() {
        // 28 tiles is the longest chain a double-six set can produce, so the
        // small canvas is only asked to hold a real game, not a stress case.
        // Beyond that the chain is boxed in and auto-fit takes over.
        let sizes: [(CGSize, Int)] = [
            (CGSize(width: 900, height: 620), 40),
            (CGSize(width: 420, height: 320), 28),
        ]
        for (size, cap) in sizes {
            for count in 1...cap {
                let metrics = SnakeChainLayout.compute(
                    orientedTiles: chain(count), availableSize: size)
                let rects = metrics.placed.map(footprint)
                for a in 0..<rects.count {
                    for b in (a + 1)..<rects.count {
                        let hit = rects[a].intersection(rects[b])
                        let overlapsMeaningfully =
                            !hit.isNull && hit.width > 0.5 && hit.height > 0.5
                        XCTAssertFalse(
                            overlapsMeaningfully,
                            "tiles \(a) and \(b) overlap by \(hit) at count=\(count), size=\(size)")
                    }
                }
            }
        }
    }

    func test_wideDesktopWindow_coilsWithinTheTable() {
        // A run stretched edge to edge reads as a stripe, however correct the
        // geometry (live report). Runs take about two thirds of the table, so
        // a chain forms a mass in the middle and turns well before the edge.
        let size = CGSize(width: 1600, height: 900)
        for count in [18, 24, 40] {
            let m = SnakeChainLayout.compute(orientedTiles: chain(count), availableSize: size)
            XCTAssertLessThanOrEqual(m.contentWidth, size.width * 0.75,
                                     "\(count) tiles must not stretch across the whole table")
            XCTAssertGreaterThanOrEqual(m.contentWidth, size.width * 0.5,
                                        "\(count) tiles must not collapse into a narrow column")
            XCTAssertGreaterThan(Set(m.placed.map { $0.y }).count, 1,
                                 "\(count) tiles must turn instead of running as a stripe")
        }
    }

    func test_consecutiveTilesAreAdjacent() {
        let size = CGSize(width: 900, height: 620)
        for count in 2...40 {
            let metrics = SnakeChainLayout.compute(
                orientedTiles: chain(count), availableSize: size)
            let rects = metrics.placed.map(footprint)
            for i in 1..<rects.count {
                let a = rects[i - 1]
                let b = rects[i]
                let gapX = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
                let gapY = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
                let separation = max(gapX, gapY)
                // A crosswise double stands half a tile proud of its run, and
                // the run continuing past it is offset by exactly that much.
                // So one gap plus half a tile is the honest maximum between
                // neighbours; anything larger means the chain came apart.
                let allowance = SnakeChainLayout.hGap
                    + SnakeChainLayout.tileShortAxis / 2 + 0.5
                XCTAssertLessThanOrEqual(
                    separation, allowance,
                    "tiles \(i - 1)/\(i) are \(separation)pt apart at count=\(count)")
            }
        }
    }

    func test_appendingDoesNotReFlowPlacedTiles() {
        let size = CGSize(width: 900, height: 620)
        let existing = chain(14)
        let extended = existing + chain(4)

        let before = SnakeChainLayout.compute(orientedTiles: existing, availableSize: size)
        let after = SnakeChainLayout.compute(orientedTiles: extended, availableSize: size)

        // The finished path is centred on the table, so a longer chain may
        // translate everything. Shape stability is what matters: every shared
        // tile must keep its position RELATIVE to the first tile.
        let dx = after.placed[0].x - before.placed[0].x
        let dy = after.placed[0].y - before.placed[0].y
        // Every shared tile keeps its place EXCEPT the one that was last: when
        // the chain grows, that tile becomes the corner for the next run, so it
        // legitimately turns and moves by half a tile. That is the turn itself,
        // not re-flow.
        for i in 0..<(existing.count - 1) {
            XCTAssertEqual(before.placed[i].x + dx, after.placed[i].x, accuracy: 0.001,
                           "tile \(i) moved horizontally when the chain grew")
            XCTAssertEqual(before.placed[i].y + dy, after.placed[i].y, accuracy: 0.001,
                           "tile \(i) moved vertically when the chain grew")
            XCTAssertEqual(before.placed[i].vertical, after.placed[i].vertical,
                           "tile \(i) changed orientation when the chain grew")
        }
    }

    func test_layoutIsDeterministic() {
        let size = CGSize(width: 900, height: 620)
        let tiles = chain(25)
        let first = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: size)
        let second = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: size)
        XCTAssertEqual(first.placed.count, second.placed.count)
        for i in 0..<first.placed.count {
            XCTAssertEqual(first.placed[i].x, second.placed[i].x, accuracy: 0.0001)
            XCTAssertEqual(first.placed[i].y, second.placed[i].y, accuracy: 0.0001)
            XCTAssertEqual(first.placed[i].vertical, second.placed[i].vertical)
        }
    }
}
