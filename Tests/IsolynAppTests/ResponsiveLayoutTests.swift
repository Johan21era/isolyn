import XCTest
@testable import IsolynApp

final class ResponsiveLayoutTests: XCTestCase {

    func test_horizontalPadding_tracksTheSupportedWindowRange() {
        XCTAssertEqual(IsolynLayout.horizontalPadding(for: 900), 24)
        XCTAssertEqual(IsolynLayout.horizontalPadding(for: 959), 24)
        XCTAssertEqual(IsolynLayout.horizontalPadding(for: 960), 40)
        XCTAssertEqual(IsolynLayout.horizontalPadding(for: 1279), 40)
        XCTAssertEqual(IsolynLayout.horizontalPadding(for: 1280), 56)
        XCTAssertEqual(IsolynLayout.horizontalPadding(for: 2880), 56)
    }

    func test_contentCaps_areStableAcrossMacBookWidths() {
        XCTAssertEqual(IsolynLayout.maxContentWidth, 1120)
        XCTAssertEqual(IsolynLayout.maxBoardWidth, 1600)
        XCTAssertEqual(IsolynLayout.compactBreakpoint, 1040)
    }

    func test_windowMinimums_matchTheSupportedDesktopLayout() {
        XCTAssertEqual(IsolynLayout.minWindowWidth, 900)
        XCTAssertEqual(IsolynLayout.minWindowHeight, 620)
    }
}
