import XCTest
@testable import Cramless

/// Where a page settles when it opens on a question's lines.
final class LibraryPageFocusTests: XCTestCase {
    private let frame = CGSize(width: 300, height: 400)

    private func line(x: Double = 0.3, y: Double, w: Double = 0.4, h: Double = 0.02) -> NormRect {
        NormRect(x: x, y: y, w: w, h: h)
    }

    func testNothingToFocusOn() {
        XCTAssertNil(PageFocus.make(boxes: [], frame: frame))
        XCTAssertNil(PageFocus.make(boxes: [NormRect(x: 0.1, y: 0.1, w: 0, h: 0)], frame: frame))
    }

    func testAShortLineInTheMiddleZoomsToTheMostAndStaysCentred() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(x: 0.45, y: 0.49, w: 0.1)], frame: frame))
        XCTAssertEqual(focus.scale, PageFocus.maxScale, accuracy: 0.001)
        XCTAssertEqual(focus.offset.width, 0, accuracy: 0.5)
        XCTAssertEqual(focus.offset.height, 0, accuracy: 0.5)
    }

    func testAWideLineZoomsOnlyAsFarAsItFits() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(x: 0.2, y: 0.5, w: 0.5)], frame: frame))
        // 0.5 wide + 0.04 each side: the line and its padding just fill the width.
        XCTAssertEqual(focus.scale, 1 / 0.58, accuracy: 0.001)
    }

    func testThePageNeverShowsPastItsEdge() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(x: 0.02, y: 0.01, w: 0.1)], frame: frame))
        let maxX = (frame.width * focus.scale - frame.width) / 2
        let maxY = (frame.height * focus.scale - frame.height) / 2
        XCTAssertEqual(focus.offset.width, maxX, accuracy: 0.001, "a line at the left edge pushes the page right, up to the edge")
        XCTAssertEqual(focus.offset.height, maxY, accuracy: 0.001)
    }

    func testALineAcrossThePageDoesNotTwitch() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(x: 0.05, y: 0.5, w: 0.9)], frame: frame))
        XCTAssertEqual(focus.scale, 1)
        XCTAssertEqual(focus.offset, .zero)
        XCTAssertEqual(focus.blocks.count, 1, "still circled")
    }

    func testLinesOneUnderTheOtherAreOneBlock() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(y: 0.40), line(y: 0.43), line(y: 0.46)], frame: frame))
        XCTAssertEqual(focus.blocks.count, 1)
        XCTAssertEqual(focus.blocks[0].minY, 0.40, accuracy: 0.0001)
        XCTAssertEqual(focus.blocks[0].maxY, 0.48, accuracy: 0.0001)
        XCTAssertGreaterThan(focus.scale, 1)
    }

    func testLinesFarApartInOneColumnAreTwoBlocksWithOneZoom() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(y: 0.20), line(y: 0.50)], frame: frame))
        XCTAssertEqual(focus.blocks.count, 2)
        XCTAssertGreaterThan(focus.scale, 1)
    }

    func testAQuoteAcrossColumnsDoesNotZoomAndCirclesEachPart() throws {
        let focus = try XCTUnwrap(PageFocus.make(boxes: [line(x: 0.05, y: 0.80, w: 0.4), line(x: 0.55, y: 0.10, w: 0.4)], frame: frame))
        XCTAssertEqual(focus.scale, 1)
        XCTAssertEqual(focus.offset, .zero)
        XCTAssertEqual(focus.blocks.count, 2)
    }

    func testThePenCircleGoesAroundItsBox() {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 40)
        let bounds = PenCircleShape().path(in: rect).boundingRect
        XCTAssertEqual(bounds.midX, rect.midX, accuracy: 12)
        XCTAssertEqual(bounds.midY, rect.midY, accuracy: 6)
        XCTAssertGreaterThanOrEqual(bounds.width, rect.width * 0.95)
    }
}
