import CoreGraphics
import XCTest

@testable import Snaplet

/// Covers `ImageUpscaler.upscale`, the post-capture supersampling step that
/// replaced requesting an inflated resolution directly from
/// `SCStreamConfiguration` -- that approach left the excess canvas blank for
/// cropped (Area/Window) captures instead of actually scaling the content up.
final class ImageUpscalerTests: XCTestCase {

    /// Builds a `width` x `height` fully opaque red `CGImage`.
    private func makeRedImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func testFactorOneReturnsImageUnchanged() {
        let image = makeRedImage(width: 40, height: 30)

        let result = ImageUpscaler.upscale(image, factor: 1)

        XCTAssertEqual(result?.width, 40)
        XCTAssertEqual(result?.height, 30)
    }

    func testUpscaleFillsTheEntireRequestedCanvas() {
        let image = makeRedImage(width: 40, height: 30)

        let result = ImageUpscaler.upscale(image, factor: 2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 80)
        XCTAssertEqual(result?.height, 60)

        // The regression this guards against: requesting more pixels than
        // the source's native resolution left the excess canvas blank
        // instead of scaling the content to fill it. Sample every corner
        // (not just the center) to confirm the entire canvas -- including
        // the far edges an under-filled render would leave blank -- carries
        // real content.
        var buffer = [UInt8](repeating: 0, count: 80 * 60 * 4)
        let readbackContext = CGContext(
            data: &buffer,
            width: 80,
            height: 60,
            bitsPerComponent: 8,
            bytesPerRow: 80 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        readbackContext.draw(result!, in: CGRect(x: 0, y: 0, width: 80, height: 60))

        // Compare red against green (rather than asserting an exact
        // intensity): CIContext's color-managed rendering can shift a
        // synthetic device-RGB red's raw byte value, but a genuinely
        // unfilled/blank pixel reads as black or transparent -- red and
        // green would be equal (both ~0) -- so this still catches the
        // regression without being sensitive to color management.
        let corners = [(0, 0), (79, 0), (0, 59), (79, 59), (40, 30)]
        for (x, y) in corners {
            let offset = (y * 80 + x) * 4
            XCTAssertGreaterThan(buffer[offset], buffer[offset + 1] + 50, "expected red at (\(x), \(y)), found a blank/unfilled pixel")
        }
    }
}
