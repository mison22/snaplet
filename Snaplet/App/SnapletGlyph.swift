import AppKit

/// The Snaplet "focus reticle" mark: a lens ring with N/E/S/W focus ticks and
/// a center dot.
///
/// Drawn programmatically from a single geometry definition (rather than
/// shipped as a raster asset) so the identical mark stays crisp at any size
/// and can be recolored for each place it appears: the menu-bar status item
/// (a tintable template) and the area-capture cursor (a light mark with a
/// dark halo so it reads over arbitrary screen content).
enum SnapletGlyph {

    /// Reference drawing box; all geometry below is expressed in a 100x100
    /// space and scaled to the requested output size.
    private static let referenceExtent: CGFloat = 100
    private static let ringRadius: CGFloat = 17
    private static let tickInnerRadius: CGFloat = 22
    private static let tickOuterRadius: CGFloat = 31
    private static let dotRadius: CGFloat = 3.6
    private static let strokeWidth: CGFloat = 7

    /// Extra stroke width (and half that added to the dot radius) drawn in the
    /// halo pass, giving the mark a legible outline over any background.
    private static let haloExtraWidth: CGFloat = 3

    /// Builds a square image of the reticle `size` points on a side.
    ///
    /// - Parameters:
    ///   - color: the mark's stroke/fill color.
    ///   - haloColor: if set, a thicker outline drawn *behind* `color` so the
    ///     mark stays legible over arbitrary content (used for the cursor).
    ///   - isTemplate: marks the image as a template so AppKit tints it for the
    ///     menu bar and dark mode (used for the status item).
    static func image(
        size: CGFloat,
        color: NSColor,
        haloColor: NSColor? = nil,
        isTemplate: Bool = false
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            if let haloColor {
                drawMark(extent: size, color: haloColor, extraWidth: haloExtraWidth)
            }
            drawMark(extent: size, color: color, extraWidth: 0)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    /// Draws the mark into the current graphics context. The mark is
    /// vertically and horizontally symmetric, so it renders identically in
    /// flipped or unflipped coordinate spaces.
    private static func drawMark(extent: CGFloat, color: NSColor, extraWidth: CGFloat) {
        let scale = extent / referenceExtent
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: y * scale) }

        color.set()
        let lineWidth = strokeWidth * scale + extraWidth

        let ring = NSBezierPath(ovalIn: NSRect(
            x: (50 - ringRadius) * scale,
            y: (50 - ringRadius) * scale,
            width: ringRadius * 2 * scale,
            height: ringRadius * 2 * scale
        ))
        ring.lineWidth = lineWidth
        ring.stroke()

        let ticks = NSBezierPath()
        ticks.lineWidth = lineWidth
        ticks.lineCapStyle = .round
        let inner = tickInnerRadius, outer = tickOuterRadius
        ticks.move(to: point(50, 50 - inner)); ticks.line(to: point(50, 50 - outer))
        ticks.move(to: point(50, 50 + inner)); ticks.line(to: point(50, 50 + outer))
        ticks.move(to: point(50 + inner, 50)); ticks.line(to: point(50 + outer, 50))
        ticks.move(to: point(50 - inner, 50)); ticks.line(to: point(50 - outer, 50))
        ticks.stroke()

        let dotR = dotRadius * scale + extraWidth / 2
        NSBezierPath(ovalIn: NSRect(
            x: 50 * scale - dotR,
            y: 50 * scale - dotR,
            width: dotR * 2,
            height: dotR * 2
        )).fill()
    }
}
