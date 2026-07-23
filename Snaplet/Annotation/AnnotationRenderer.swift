import AppKit
import CoreGraphics

/// Flattens a base screenshot and an ordered stack of `Annotation`s into a
/// single `CGImage`, at the base image's native pixel dimensions.
///
/// This is the only place that owns the bitmap `CGContext` used for final
/// export (Save/Copy consume its output); `Annotation.draw(in:)` stays
/// context-agnostic beyond the coordinate convention it documents.
enum AnnotationRenderer {

    private static let bitsPerComponent = 8
    private static let bytesPerPixel = 4

    /// Draws `base` followed by `annotations`, in order, into a new bitmap
    /// context sized to `base`'s pixel dimensions, and returns the flattened
    /// result.
    ///
    /// - Parameters:
    ///   - base: The screenshot to annotate. Its `width`/`height` (in pixels)
    ///     determine the output image's dimensions.
    ///   - annotations: Drawn in array order, each on top of the previous.
    /// - Returns: A flattened `CGImage` at `base`'s pixel dimensions, or
    ///   `nil` if the backing bitmap context could not be created.
    static func flatten(base: CGImage, annotations: [Annotation]) -> CGImage? {
        let width = base.width
        let height = base.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // Flatten in the capture's own color space (Display P3 on a wide-gamut
        // screen), not a generic device RGB. Redrawing into device RGB clamps
        // out-of-sRGB colors and strips the profile, so exports look duller
        // than what was on screen. Fall back to device RGB only if the source
        // space can't back a bitmap context.
        let colorSpace = base.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) ?? CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
        guard let context else {
            return nil
        }

        // Draw the base first, in the context's default (bottom-left-origin)
        // space, where `CGContext.draw(_:in:)` lands a `CGImage` upright.
        // Applying the top-left-origin flip *before* this instead would draw
        // the base upside down -- the flip is only needed for annotation
        // geometry, not the base bitmap.
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: fullRect)

        // Now flip to the top-left-origin convention documented on
        // `Annotation` -- move the origin to the top edge, then invert Y so
        // increasing Y moves down -- for drawing the annotation stack.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        for annotation in annotations {
            annotation.draw(in: context)
        }

        return context.makeImage()
    }

    /// Convenience wrapper around `flatten(base:annotations:)` for callers
    /// (Copy) that want an `NSImage` sized in points at the base image's
    /// native pixel resolution.
    ///
    /// - Parameter pointScale: Pixels-per-point the base image was captured
    ///   at (`CapturedImage.scale`). `NSImage.size` must be in points, not
    ///   pixels -- reporting the raw pixel count as the size understates how
    ///   much pixel data is actually available for a given point size, so a
    ///   receiving app renders it at the wrong physical size and upscales it
    ///   on a Retina display, reading as grainy.
    static func flattenToNSImage(base: CGImage, annotations: [Annotation], pointScale: CGFloat) -> NSImage? {
        guard let flattened = flatten(base: base, annotations: annotations) else {
            return nil
        }
        let size = NSSize(width: CGFloat(flattened.width) / pointScale, height: CGFloat(flattened.height) / pointScale)
        return NSImage(cgImage: flattened, size: size)
    }
}
