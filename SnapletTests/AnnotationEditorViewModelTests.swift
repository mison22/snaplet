import AppKit
import XCTest

@testable import Snaplet

/// Tests for `AnnotationEditorViewModel`'s selection, move, delete, and
/// restyle logic. `@MainActor` because the view model is main-actor isolated.
@MainActor
final class AnnotationEditorViewModelTests: XCTestCase {

    private func makeArrow(from start: CGPoint, to end: CGPoint) -> Annotation {
        .arrow(Arrow(start: start, end: end, color: .systemRed, lineWidth: 14))
    }

    func testSelectAnnotationPicksTheOneUnderThePoint() {
        let viewModel = AnnotationEditorViewModel()
        let arrow = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        viewModel.append(arrow)

        viewModel.selectAnnotation(at: CGPoint(x: 50, y: 5))

        XCTAssertEqual(viewModel.selectedAnnotationID, arrow.id)
    }

    func testSelectAnnotationClearsWhenPointHitsNothing() {
        let viewModel = AnnotationEditorViewModel()
        viewModel.append(makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
        viewModel.selectAnnotation(at: CGPoint(x: 50, y: 5))

        viewModel.selectAnnotation(at: CGPoint(x: 500, y: 500))

        XCTAssertNil(viewModel.selectedAnnotationID)
    }

    func testSelectPrefersTopmostAnnotation() {
        let viewModel = AnnotationEditorViewModel()
        let bottom = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let top = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        viewModel.append(bottom)
        viewModel.append(top)

        viewModel.selectAnnotation(at: CGPoint(x: 50, y: 0))

        XCTAssertEqual(viewModel.selectedAnnotationID, top.id)
    }

    func testDeleteSelectedRemovesIt() {
        let viewModel = AnnotationEditorViewModel()
        let arrow = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        viewModel.append(arrow)
        viewModel.selectAnnotation(at: CGPoint(x: 50, y: 0))

        viewModel.deleteSelectedAnnotation()

        XCTAssertTrue(viewModel.annotations.isEmpty)
        XCTAssertNil(viewModel.selectedAnnotationID)
    }

    func testSelectDragMovesTheAnnotationByTheDrag() {
        let viewModel = AnnotationEditorViewModel()
        let arrow = makeArrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        viewModel.append(arrow)
        viewModel.selectAnnotation(at: CGPoint(x: 150, y: 100))

        viewModel.continueSelectDrag(hitHandle: nil, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 160, y: 110))
        viewModel.endSelectDrag()

        guard case .arrow(let moved) = viewModel.annotations.first else { return XCTFail("expected arrow") }
        XCTAssertEqual(moved.start, CGPoint(x: 110, y: 110))
        XCTAssertEqual(moved.end, CGPoint(x: 210, y: 110))
    }

    func testSelectDragResizesWhenStartedOnAHandle() {
        let viewModel = AnnotationEditorViewModel()
        let arrow = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        viewModel.append(arrow)
        viewModel.selectedAnnotationID = arrow.id

        viewModel.continueSelectDrag(hitHandle: .arrowEnd, from: CGPoint(x: 100, y: 0), to: CGPoint(x: 140, y: 40))
        viewModel.endSelectDrag()

        guard case .arrow(let resized) = viewModel.annotations.first else { return XCTFail("expected arrow") }
        XCTAssertEqual(resized.start, CGPoint(x: 0, y: 0), "start stays put during an end-handle resize")
        XCTAssertEqual(resized.end, CGPoint(x: 140, y: 40))
    }

    func testSetColorRecolorsSelection() {
        let viewModel = AnnotationEditorViewModel()
        let arrow = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        viewModel.append(arrow)
        viewModel.selectedAnnotationID = arrow.id

        viewModel.setColor(.systemGreen)

        XCTAssertEqual(viewModel.annotations.first?.color, .systemGreen)
        XCTAssertEqual(viewModel.selectedColor, .systemGreen)
    }

    func testSetLineWidthRestrokesSelectedArrow() {
        let viewModel = AnnotationEditorViewModel()
        let arrow = makeArrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        viewModel.append(arrow)
        viewModel.selectedAnnotationID = arrow.id

        viewModel.setLineWidth(30)

        guard case .arrow(let widened) = viewModel.annotations.first else { return XCTFail("expected arrow") }
        XCTAssertEqual(widened.lineWidth, 30)
    }
}
