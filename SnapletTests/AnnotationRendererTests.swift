import AppKit
import CoreGraphics
import XCTest

@testable import Snaplet

/// Tests for `AnnotationRenderer.flatten`, using a small synthetic white
/// bitmap as the base image so results are deterministic and fast.
final class AnnotationRendererTests: XCTestCase {

    private static let baseSize = 64

    /// Builds a `baseSize` x `baseSize` fully opaque white `CGImage`.
    private func makeWhiteBaseImage() -> CGImage {
        let size = Self.baseSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        return context.makeImage()!
    }

    /// Reads the RGBA bytes of `image` back into a flat pixel buffer so
    /// individual pixels can be sampled and asserted on.
    private func pixelData(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func pixel(_ buffer: [UInt8], x: Int, y: Int, width: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = (y * width + x) * 4
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
    }

    func testEmptyAnnotationsPreservesDimensionsAndContent() {
        let base = makeWhiteBaseImage()

        let flattened = AnnotationRenderer.flatten(base: base, annotations: [])

        XCTAssertNotNil(flattened)
        XCTAssertEqual(flattened?.width, base.width)
        XCTAssertEqual(flattened?.height, base.height)

        let buffer = pixelData(of: flattened!)
        let sample = pixel(buffer, x: Self.baseSize / 2, y: Self.baseSize / 2, width: Self.baseSize)
        XCTAssertEqual(sample.r, 255)
        XCTAssertEqual(sample.g, 255)
        XCTAssertEqual(sample.b, 255)
    }

    func testEachAnnotationKindRendersWithoutCrashingAndPreservesDimensions() {
        let base = makeWhiteBaseImage()
        let size = CGFloat(Self.baseSize)

        let arrow = Annotation.arrow(
            Arrow(start: CGPoint(x: 4, y: 4), end: CGPoint(x: size - 4, y: size - 4), color: .systemRed)
        )
        let text = Annotation.text(
            TextBox(origin: CGPoint(x: 4, y: 4), text: "Hi", color: .black, fontSize: 12)
        )
        let bubble = Annotation.bubble(
            SpeechBubble(
                bodyRect: CGRect(x: 8, y: 8, width: 32, height: 20),
                tailTarget: CGPoint(x: size - 8, y: size - 8),
                text: "Yo",
                color: .systemBlue,
                fontSize: 10
            )
        )

        let flattened = AnnotationRenderer.flatten(base: base, annotations: [arrow, text, bubble])

        XCTAssertNotNil(flattened)
        XCTAssertEqual(flattened?.width, base.width)
        XCTAssertEqual(flattened?.height, base.height)
    }

    /// Builds a `baseSize` x `baseSize` image whose top half is red and
    /// bottom half is blue, so a vertical flip in `flatten` is detectable
    /// (a symmetric base -- like the white one the other tests use -- looks
    /// identical flipped, which let an upside-down-save bug through before).
    private func makeTopRedBottomBlueBaseImage() -> CGImage {
        let size = Self.baseSize
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // `pixelData(of:)` reports row 0 as the visual top, so paint the top
        // half red using that same convention: draw red into the buffer's
        // first rows by drawing in the context's default space and relying on
        // the shared read-back for a consistent notion of "top".
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(NSColor.red.cgColor)
        // In the context's default (bottom-left) space, the top half is the
        // upper Y range.
        context.fill(CGRect(x: 0, y: size / 2, width: size, height: size / 2))

        return context.makeImage()!
    }

    func testFlattenPreservesVerticalOrientation() {
        let base = makeTopRedBottomBlueBaseImage()
        let size = Self.baseSize

        // Sanity: confirm the base reads top=red, bottom=blue through the
        // shared read-back, so the assertion below is meaningful.
        let baseBuffer = pixelData(of: base)
        let baseTop = pixel(baseBuffer, x: size / 2, y: 2, width: size)
        let baseBottom = pixel(baseBuffer, x: size / 2, y: size - 3, width: size)
        XCTAssertGreaterThan(baseTop.r, baseTop.b, "base top should read red")
        XCTAssertGreaterThan(baseBottom.b, baseBottom.r, "base bottom should read blue")

        let flattened = AnnotationRenderer.flatten(base: base, annotations: [])
        XCTAssertNotNil(flattened)

        let buffer = pixelData(of: flattened!)
        let top = pixel(buffer, x: size / 2, y: 2, width: size)
        let bottom = pixel(buffer, x: size / 2, y: size - 3, width: size)

        XCTAssertGreaterThan(top.r, top.b, "flattened top should stay red (not vertically flipped)")
        XCTAssertGreaterThan(bottom.b, bottom.r, "flattened bottom should stay blue (not vertically flipped)")
    }

    func testArrowChangesPixelAlongItsPath() {
        let base = makeWhiteBaseImage()
        let size = Self.baseSize

        let arrow = Annotation.arrow(
            Arrow(
                start: CGPoint(x: 0, y: size / 2),
                end: CGPoint(x: size, y: size / 2),
                color: .systemRed
            )
        )

        let flattened = AnnotationRenderer.flatten(base: base, annotations: [arrow])
        XCTAssertNotNil(flattened)

        let buffer = pixelData(of: flattened!)
        let sample = pixel(buffer, x: size / 2, y: size / 2, width: size)

        // A horizontal red-ish line through the vertical center should no
        // longer read as pure white at the midpoint.
        let isPureWhite = sample.r == 255 && sample.g == 255 && sample.b == 255
        XCTAssertFalse(isPureWhite, "expected the annotated pixel to differ from the white base")
    }
}
