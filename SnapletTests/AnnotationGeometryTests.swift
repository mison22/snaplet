import AppKit
import XCTest

@testable import Snaplet

/// Tests for the pure geometry on `Annotation`, `Arrow`, and friends that
/// backs selection, moving, and resizing in the editor.
final class AnnotationGeometryTests: XCTestCase {

    // MARK: - Arrow.distance(to:)

    func testArrowDistanceOnSegmentIsZero() {
        let arrow = Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0), color: .systemRed)
        XCTAssertEqual(arrow.distance(to: CGPoint(x: 5, y: 0)), 0, accuracy: 0.0001)
    }

    func testArrowDistancePerpendicular() {
        let arrow = Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0), color: .systemRed)
        XCTAssertEqual(arrow.distance(to: CGPoint(x: 5, y: 4)), 4, accuracy: 0.0001)
    }

    func testArrowDistanceClampsBeyondEndpoints() {
        let arrow = Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0), color: .systemRed)
        // Past the start, the nearest point is the start itself.
        XCTAssertEqual(arrow.distance(to: CGPoint(x: -3, y: 0)), 3, accuracy: 0.0001)
    }

    func testArrowDistanceHandlesZeroLength() {
        let arrow = Arrow(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5), color: .systemRed)
        XCTAssertEqual(arrow.distance(to: CGPoint(x: 8, y: 9)), 5, accuracy: 0.0001)
    }

    // MARK: - hitTest

    func testArrowHitTestNearLineHits() {
        let arrow = Annotation.arrow(Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), color: .systemRed))
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 50, y: 8)))
    }

    func testArrowHitTestFarFromLineMisses() {
        let arrow = Annotation.arrow(Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), color: .systemRed))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 50, y: 200)))
    }

    func testBubbleHitTestInsideBodyHits() {
        let bubble = Annotation.bubble(SpeechBubble(
            bodyRect: CGRect(x: 10, y: 10, width: 100, height: 60),
            tailTarget: CGPoint(x: 0, y: 100), text: "hi", color: .systemBlue))
        XCTAssertTrue(bubble.hitTest(CGPoint(x: 50, y: 40)))
        XCTAssertFalse(bubble.hitTest(CGPoint(x: 500, y: 500)))
    }

    // MARK: - translated(by:)

    func testTranslateArrowShiftsBothEndpoints() {
        let arrow = Annotation.arrow(Arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 30, y: 40), color: .systemRed))
        guard case .arrow(let moved) = arrow.translated(by: CGSize(width: 5, height: -5)) else {
            return XCTFail("expected arrow")
        }
        XCTAssertEqual(moved.start, CGPoint(x: 15, y: 15))
        XCTAssertEqual(moved.end, CGPoint(x: 35, y: 35))
    }

    func testTranslateBubbleShiftsBodyAndTail() {
        let bubble = Annotation.bubble(SpeechBubble(
            bodyRect: CGRect(x: 10, y: 10, width: 40, height: 30),
            tailTarget: CGPoint(x: 5, y: 60), text: "x", color: .systemBlue))
        guard case .bubble(let moved) = bubble.translated(by: CGSize(width: 10, height: 20)) else {
            return XCTFail("expected bubble")
        }
        XCTAssertEqual(moved.bodyRect.origin, CGPoint(x: 20, y: 30))
        XCTAssertEqual(moved.tailTarget, CGPoint(x: 15, y: 80))
    }

    // MARK: - resized(handle:to:)

    func testResizeArrowEndMovesOnlyEnd() {
        let arrow = Annotation.arrow(Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), color: .systemRed))
        guard case .arrow(let resized) = arrow.resized(handle: .arrowEnd, to: CGPoint(x: 99, y: 88)) else {
            return XCTFail("expected arrow")
        }
        XCTAssertEqual(resized.start, CGPoint(x: 0, y: 0))
        XCTAssertEqual(resized.end, CGPoint(x: 99, y: 88))
    }

    func testResizeBubbleCornerKeepsOppositeCornerFixed() {
        let original = CGRect(x: 10, y: 10, width: 100, height: 80)
        let bubble = Annotation.bubble(SpeechBubble(
            bodyRect: original, tailTarget: CGPoint(x: 0, y: 200), text: "x", color: .systemBlue))
        guard case .bubble(let resized) = bubble.resized(handle: .bubbleCorner(.bottomRight), to: CGPoint(x: 210, y: 190)) else {
            return XCTFail("expected bubble")
        }
        // Top-left (the opposite corner) stays put; the dragged corner defines the new extent.
        XCTAssertEqual(resized.bodyRect.minX, 10, accuracy: 0.0001)
        XCTAssertEqual(resized.bodyRect.minY, 10, accuracy: 0.0001)
        XCTAssertEqual(resized.bodyRect.maxX, 210, accuracy: 0.0001)
        XCTAssertEqual(resized.bodyRect.maxY, 190, accuracy: 0.0001)
    }

    func testResizeBubbleClampsToMinimumSize() {
        let original = CGRect(x: 10, y: 10, width: 100, height: 80)
        let bubble = Annotation.bubble(SpeechBubble(
            bodyRect: original, tailTarget: CGPoint(x: 0, y: 200), text: "x", color: .systemBlue))
        // Drag the bottom-right corner onto the top-left; size must not collapse to zero.
        guard case .bubble(let resized) = bubble.resized(handle: .bubbleCorner(.bottomRight), to: CGPoint(x: 10, y: 10)) else {
            return XCTFail("expected bubble")
        }
        XCTAssertGreaterThan(resized.bodyRect.width, 0)
        XCTAssertGreaterThan(resized.bodyRect.height, 0)
    }

    func testResizeTextCornerScalesFontWithDistance() {
        let text = Annotation.text(TextBox(origin: CGPoint(x: 0, y: 0), text: "Hello", color: .black, fontSize: 20))
        let farCorner = CGPoint(x: 400, y: 200)
        let nearCorner = CGPoint(x: 20, y: 10)
        guard case .text(let bigger) = text.resized(handle: .textCorner, to: farCorner),
              case .text(let smaller) = text.resized(handle: .textCorner, to: nearCorner) else {
            return XCTFail("expected text")
        }
        XCTAssertGreaterThan(bigger.fontSize, smaller.fontSize)
    }

    // MARK: - color / lineWidth mutation

    func testWithColorRecolorsEachKind() {
        let arrow = Annotation.arrow(Arrow(start: .zero, end: CGPoint(x: 1, y: 1), color: .systemRed))
        XCTAssertEqual(arrow.withColor(.systemGreen).color, .systemGreen)
    }

    func testWithLineWidthOnlyAffectsArrows() {
        let text = Annotation.text(TextBox(origin: .zero, text: "x", color: .black))
        // Non-arrows are returned unchanged; this simply must not crash or alter identity.
        XCTAssertEqual(text.withLineWidth(40).id, text.id)

        let arrow = Annotation.arrow(Arrow(start: .zero, end: CGPoint(x: 1, y: 1), color: .systemRed, lineWidth: 4))
        guard case .arrow(let widened) = arrow.withLineWidth(40) else { return XCTFail("expected arrow") }
        XCTAssertEqual(widened.lineWidth, 40)
    }
}
