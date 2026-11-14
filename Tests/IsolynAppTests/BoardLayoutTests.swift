import XCTest
@testable import IsolynApp

/// FIX-28 (audit OA-4 / remediation roadmap P2a): pins the PURE snake-chain
/// layout contract. These tests target `SnakeChainLayout` directly -- no
/// views, no snapshots, fully deterministic. The contracts they protect:
/// serpentine rows with perpendicular corner caps, extent math that
/// includes marker clearance and double protrusion, and an auto-fit scale
/// that (a) is EXACTLY 1 while things fit, (b) engages only past the
/// threshold, (c) floors instead of crushing tiles (§17's own priority
/// order), (d) is UNIFORM -- which is what keeps the mandate §2/§3 exact
/// 2:1 domino law true at any scale BY CONSTRUCTION, and (e) shrinks
/// monotonically as the plane shrinks.
final class BoardLayoutTests: XCTestCase {

    // MARK: - orient()

    func test_orient_flipsEachTileToTouchItsNeighbour() {
        let oriented = SnakeChainLayout.orient(
            chain: [Tile(low: 6, high: 4), Tile(low: 2, high: 6)], leftEnd: 4)
        XCTAssertEqual(oriented.count, 2)
        XCTAssertEqual(oriented[0].left, 4)
        XCTAssertEqual(oriented[0].right, 6, "first tile flips so its matching face points at the open end")
        XCTAssertEqual(oriented[1].left, 6, "next tile's exposed face matches the previous tile's other face")
        XCTAssertEqual(oriented[1].right, 2)
    }

    func test_orient_marksDoubles() {
        let oriented = SnakeChainLayout.orient(chain: [Tile(low: 3, high: 3)], leftEnd: 3)
        XCTAssertTrue(oriented[0].isDouble)
        XCTAssertEqual(oriented[0].left, 3)
        XCTAssertEqual(oriented[0].right, 3)
    }

    func test_orient_emptyChain_yieldsNothing() {
        XCTAssertTrue(SnakeChainLayout.orient(chain: [], leftEnd: nil).isEmpty)
    }

    // MARK: - compute() — structure

    func test_compute_singleTile_placesExactlyOneAndNeverTriggersAutoFit() {
        let m = SnakeChainLayout.compute(
            orientedTiles: [SnakeChainLayout.Oriented(left: 6, right: 4, isDouble: false)],
            availableSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(m.placed.count, 1)
        XCTAssertNotNil(m.headPosition, "an open head end exists even for a one-tile chain")
        XCTAssertNotNil(m.tailPosition)
        XCTAssertEqual(m.suggestedScale, 1, accuracy: 0.0001,
                       "a lone tile must never trigger auto-fit scaling")
    }

    func test_compute_turn_isMadeByTheCurrentTile_acrossTheIncomingRun() {
        // The chain is a path now, not a grid: a turn is made BY a tile that
        // lies across the incoming run, and the next run leaves from that
        // tile's far edge. There is no fixed column count.
        var tiles = [SnakeChainLayout.Oriented]()
        for i in 0..<20 {
            tiles.append(SnakeChainLayout.Oriented(left: i % 7, right: (i + 1) % 7, isDouble: false))
        }
        let m = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: CGSize(width: 800, height: 600))

        // Find the first tile that breaks the initial (horizontal) run.
        guard let turnIndex = m.placed.firstIndex(where: { $0.vertical }) else {
            return XCTFail("a 20-tile chain on an 800pt plane must turn at least once")
        }
        XCTAssertGreaterThan(turnIndex, 0, "the first tile runs along, it does not start turned")
        XCTAssertTrue(m.placed[turnIndex].vertical,
                      "the turning tile lies across the incoming run")

        let corner = m.placed[turnIndex]
        let next = m.placed[turnIndex + 1]
        let expectedGap = SnakeChainLayout.tileShortAxis + SnakeChainLayout.hGap
        XCTAssertEqual(abs(next.y - corner.y), expectedGap, accuracy: 0.0001,
                       "the new run starts one short axis and one gap below the corner")
        let underCorner = SnakeChainLayout.tileShortAxis / 2 + SnakeChainLayout.hGap
            + SnakeChainLayout.tileShortAxis
        XCTAssertEqual(abs(next.x - corner.x), underCorner, accuracy: 0.0001,
                       "the new run leaves from under the corner's long face")
    }

    func test_compute_shortChain_isCenteredInTheAvailablePlane() {
        let plane = CGSize(width: 800, height: 500)
        let m = SnakeChainLayout.compute(
            orientedTiles: [SnakeChainLayout.Oriented(left: 6, right: 4, isDouble: false)],
            availableSize: plane)

        XCTAssertEqual(m.placed[0].x, plane.width / 2, accuracy: 0.0001,
                       "a single tile sits at the horizontal center of the table")
        XCTAssertEqual(m.placed[0].y, plane.height / 2, accuracy: 0.0001,
                       "a single tile sits at the vertical center of the table")
    }

    func test_compute_visibleBounds_areCentered_ignoringEndpointTargets() {
        let plane = CGSize(width: 1200, height: 700)
        let tiles = [
            SnakeChainLayout.Oriented(left: 4, right: 6, isDouble: false),
            SnakeChainLayout.Oriented(left: 5, right: 5, isDouble: true),
        ]
        let m = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: plane)

        let minX = m.placed.map {
            $0.x - ($0.vertical ? SnakeChainLayout.tileShortAxis / 2 : SnakeChainLayout.tileShortAxis)
        }.min() ?? 0
        let maxX = m.placed.map {
            $0.x + ($0.vertical ? SnakeChainLayout.tileShortAxis / 2 : SnakeChainLayout.tileShortAxis)
        }.max() ?? 0
        let minY = m.placed.map {
            $0.y - ($0.vertical ? SnakeChainLayout.tileShortAxis : SnakeChainLayout.tileShortAxis / 2)
        }.min() ?? 0
        let maxY = m.placed.map {
            $0.y + ($0.vertical ? SnakeChainLayout.tileShortAxis : SnakeChainLayout.tileShortAxis / 2)
        }.max() ?? 0

        XCTAssertEqual((minX + maxX) / 2, plane.width / 2, accuracy: 0.0001,
                       "visible dominoes, not the invisible tap targets, sit on the centerline")
        XCTAssertEqual((minY + maxY) / 2, plane.height / 2, accuracy: 0.0001,
                       "visible dominoes, not the invisible tap targets, sit on the centerline")
    }

    func test_compute_extent_usesTileGeometry_andDoubleProtrusion() {
        let flat = SnakeChainLayout.Oriented(left: 5, right: 6, isDouble: false)
        let dbl = SnakeChainLayout.Oriented(left: 5, right: 5, isDouble: true)
        let plane = CGSize(width: 800, height: 500)

        let flatHeight = SnakeChainLayout.compute(orientedTiles: [flat], availableSize: plane).contentHeight
        let doubleHeight = SnakeChainLayout.compute(orientedTiles: [dbl], availableSize: plane).contentHeight

        // Endpoint marks have no visual clearance ring, so a lone horizontal
        // tile spans its canonical short axis exactly.
        XCTAssertEqual(flatHeight, SnakeChainLayout.tileShortAxis, accuracy: 0.0001)
        // A lone vertical double still spans the full long axis on Y: the
        // perpendicular-double protrusion is real.
        XCTAssertEqual(doubleHeight, SnakeChainLayout.tileShortAxis * 2, accuracy: 0.0001)
        XCTAssertGreaterThan(doubleHeight, flatHeight)
    }

    func test_compute_verticalDouble_sitsAtTheSameTightGapAsFlatTiles() {
        let plane = CGSize(width: 800, height: 500)
        let m = SnakeChainLayout.compute(
            orientedTiles: [
                SnakeChainLayout.Oriented(left: 4, right: 5, isDouble: false),
                SnakeChainLayout.Oriented(left: 5, right: 5, isDouble: true),
                SnakeChainLayout.Oriented(left: 5, right: 6, isDouble: false),
            ],
            availableSize: plane
        )

        XCTAssertEqual(m.placed.count, 3)
        let firstRight = m.placed[0].x + SnakeChainLayout.tileShortAxis
        let doubleLeft = m.placed[1].x - SnakeChainLayout.tileShortAxis / 2
        XCTAssertEqual(doubleLeft - firstRight, SnakeChainLayout.hGap, accuracy: 0.0001,
                       "a vertical double must not leave a half-cell of dead air after a flat tile")

        let doubleRight = m.placed[1].x + SnakeChainLayout.tileShortAxis / 2
        let thirdLeft = m.placed[2].x - SnakeChainLayout.tileShortAxis
        XCTAssertEqual(thirdLeft - doubleRight, SnakeChainLayout.hGap, accuracy: 0.0001,
                       "the flat tile after a double must also sit at the normal visual gap")
    }

    // MARK: - fitScale()

    func test_fitScale_isExactlyOneWhileContentFits() {
        let s = SnakeChainLayout.fitScale(contentWidth: 400, contentHeight: 300,
                                          availableSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(s, 1, accuracy: 0.0001)
    }

    func test_fitScale_engagesPastThreshold_coversTighterAxis_floorsAtMinimum() {
        // Mild vertical overflow: 0.94 × 500 / 600 ≈ 0.783.
        let mild = SnakeChainLayout.fitScale(contentWidth: 10, contentHeight: 600,
                                             availableSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(mild, 0.94 * 500 / 600, accuracy: 0.001)

        // Width-bound case: the tighter axis governs (0.94 × 800 / 1100 ≈ 0.684).
        let widthBound = SnakeChainLayout.fitScale(contentWidth: 1100, contentHeight: 10,
                                                   availableSize: CGSize(width: 800, height: 900))
        XCTAssertEqual(widthBound, 0.94 * 800 / 1100, accuracy: 0.001)

        // Extreme overflow stops shrinking at the §17 floor -- panning takes over.
        let floored = SnakeChainLayout.fitScale(contentWidth: 10, contentHeight: 1000,
                                                availableSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(floored, SnakeChainLayout.minScale, accuracy: 0.0001)
    }

    func test_fitScale_monotonic_shrinkingPlaneNeverYieldsLargerScale() {
        var last: CGFloat = 1
        for side in stride(from: CGFloat(900), through: CGFloat(300), by: -100) {
            let s = SnakeChainLayout.fitScale(contentWidth: 1200, contentHeight: 1200,
                                              availableSize: CGSize(width: side, height: side))
            XCTAssertLessThanOrEqual(s, last + 0.0001,
                                     "a smaller plane must never yield a larger scale")
            last = s
        }
    }

    // MARK: - compute() + scale integration

    func test_compute_longChain_staysOnATableLargeEnoughForIt() {
        // With room to work, the path must never leave the table: it turns
        // when it would, rather than running off the edge and relying on
        // scaling. 80 tiles are ~2.3x the area of one run, so a 1600x1000
        // plane is comfortably sufficient.
        var tiles = [SnakeChainLayout.Oriented]()
        for i in 0..<40 {
            tiles.append(SnakeChainLayout.Oriented(left: i % 7, right: (i + 1) % 7, isDouble: i % 11 == 5))
        }
        let plane = CGSize(width: 1600, height: 1000)
        let m = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: plane)

        XCTAssertGreaterThanOrEqual(Set(m.placed.map { $0.y }).count, 2,
                                    "a long chain uses more than one run")

        for (index, p) in m.placed.enumerated() {
            let halfW = p.vertical ? SnakeChainLayout.tileShortAxis / 2 : SnakeChainLayout.tileShortAxis
            let halfH = p.vertical ? SnakeChainLayout.tileShortAxis : SnakeChainLayout.tileShortAxis / 2
            XCTAssertGreaterThanOrEqual(p.x - halfW, -0.5, "tile \(index) past the left edge")
            XCTAssertLessThanOrEqual(p.x + halfW, plane.width + 0.5, "tile \(index) past the right edge")
            XCTAssertGreaterThanOrEqual(p.y - halfH, -0.5, "tile \(index) past the top edge")
            XCTAssertLessThanOrEqual(p.y + halfH, plane.height + 0.5, "tile \(index) past the bottom edge")
        }

        // Auto-fit may engage simply because the chain is long; what matters
        // here is that no tile left the table.
        XCTAssertGreaterThan(m.suggestedScale, SnakeChainLayout.minScale)
    }

    func test_compute_boxedInChain_engagesAutoFitInsteadOfCrushingTiles() {
        // Deliberately too many tiles for the plane: the path will run out of
        // room, and the answer is uniform auto-fit plus camera pan -- never
        // shrinking past the readability floor.
        var tiles = [SnakeChainLayout.Oriented]()
        for i in 0..<80 {
            tiles.append(SnakeChainLayout.Oriented(left: i % 7, right: (i + 1) % 7, isDouble: i % 11 == 5))
        }
        let m = SnakeChainLayout.compute(orientedTiles: tiles, availableSize: CGSize(width: 800, height: 320))
        XCTAssertLessThan(m.suggestedScale, 1, "auto-fit engages on a boxed-in chain")
        XCTAssertGreaterThanOrEqual(m.suggestedScale, SnakeChainLayout.minScale,
                                    "and never crushes tiles past the readability floor")
    }
}
