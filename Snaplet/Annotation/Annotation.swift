import AppKit
import CoreGraphics
import CoreText

/// A single user-drawn markup element layered on top of a screenshot.
///
/// Modeled as a discriminated union so `AnnotationRenderer` (and, in a later
/// wave, the SwiftUI canvas) can switch over a closed set of kinds without
/// subclassing. Each payload struct owns its own geometry, color, and
/// `draw(in:)` implementation; the enum's `draw(in:)` only dispatches.
///
/// ## Coordinate convention
/// All `draw(in:)` implementations assume a **flipped, top-left-origin**
/// `CGContext` — i.e. increasing Y moves *down*, matching AppKit view
/// coordinates and the coordinate space screenshots are naturally captured
/// in. `AnnotationRenderer` sets up its bitmap context accordingly
/// (`context.translateBy` + a flip, or an equivalent CTM) before invoking any
/// annotation's `draw(in:)`. A later SwiftUI `Canvas`-based editor uses the
/// same top-left-origin convention by default, so annotation geometry can be
/// shared as-is between on-screen editing and final flattening.
enum Annotation: Identifiable {
    case arrow(Arrow)
    case text(TextBox)
    case bubble(SpeechBubble)

    /// Stable identity for undo stacks and SwiftUI list diffing.
    var id: UUID {
        switch self {
        case .arrow(let arrow):
            return arrow.id
        case .text(let textBox):
            return textBox.id
        case .bubble(let speechBubble):
            return speechBubble.id
        }
    }

    /// This annotation's current stroke/fill color.
    var color: NSColor {
        switch self {
        case .arrow(let arrow):
            return arrow.color
        case .text(let textBox):
            return textBox.color
        case .bubble(let speechBubble):
            return speechBubble.color
        }
    }

    /// Returns a copy of this annotation recolored to `color`.
    func withColor(_ color: NSColor) -> Annotation {
        switch self {
        case .arrow(var arrow):
            arrow.color = color
            return .arrow(arrow)
        case .text(var textBox):
            textBox.color = color
            return .text(textBox)
        case .bubble(var speechBubble):
            speechBubble.color = color
            return .bubble(speechBubble)
        }
    }

    /// Returns a copy with `lineWidth` applied, if this annotation kind has
    /// an adjustable line width (currently only arrows); otherwise returns
    /// `self` unchanged.
    func withLineWidth(_ lineWidth: CGFloat) -> Annotation {
        guard case .arrow(var arrow) = self else { return self }
        arrow.lineWidth = lineWidth
        return .arrow(arrow)
    }

    /// Renders this annotation into `context`.
    ///
    /// - Parameter context: A `CGContext` using the flipped, top-left-origin
    ///   convention documented on `Annotation`.
    func draw(in context: CGContext) {
        switch self {
        case .arrow(let arrow):
            arrow.draw(in: context)
        case .text(let textBox):
            textBox.draw(in: context)
        case .bubble(let speechBubble):
            speechBubble.draw(in: context)
        }
    }

    /// Axis-aligned bounds in the same native-pixel space as this
    /// annotation's own geometry, used for the selection outline and (for
    /// text/bubble) hit-testing.
    var boundingBox: CGRect {
        switch self {
        case .arrow(let arrow):
            return CGRect(
                x: min(arrow.start.x, arrow.end.x),
                y: min(arrow.start.y, arrow.end.y),
                width: abs(arrow.end.x - arrow.start.x),
                height: abs(arrow.end.y - arrow.start.y)
            ).insetBy(dx: -arrow.lineWidth, dy: -arrow.lineWidth)
        case .text(let textBox):
            return CGRect(origin: textBox.origin, size: textBox.measuredSize)
        case .bubble(let speechBubble):
            return speechBubble.bodyRect
        }
    }

    /// Whether `point` (native-pixel space) should be considered a hit for
    /// selecting this annotation. Arrows use distance-to-segment (their
    /// bounding box would otherwise make the whole diagonal span clickable);
    /// text and bubbles use their bounding box with a small grab margin.
    func hitTest(_ point: CGPoint) -> Bool {
        switch self {
        case .arrow(let arrow):
            return arrow.distance(to: point) <= max(arrow.lineWidth, 8) + 6
        case .text, .bubble:
            return boundingBox.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    /// Returns a copy of this annotation shifted by `delta` (native-pixel
    /// space), used to drag a selected annotation to a new position.
    func translated(by delta: CGSize) -> Annotation {
        switch self {
        case .arrow(var arrow):
            arrow.start.x += delta.width
            arrow.start.y += delta.height
            arrow.end.x += delta.width
            arrow.end.y += delta.height
            return .arrow(arrow)
        case .text(var textBox):
            textBox.origin.x += delta.width
            textBox.origin.y += delta.height
            return .text(textBox)
        case .bubble(var speechBubble):
            speechBubble.bodyRect.origin.x += delta.width
            speechBubble.bodyRect.origin.y += delta.height
            speechBubble.tailTarget.x += delta.width
            speechBubble.tailTarget.y += delta.height
            return .bubble(speechBubble)
        }
    }

    /// The draggable resize control points this annotation exposes when
    /// selected, in native-pixel space.
    var resizeHandles: [ResizeHandle] {
        switch self {
        case .arrow(let arrow):
            return [
                ResizeHandle(kind: .arrowStart, position: arrow.start),
                ResizeHandle(kind: .arrowEnd, position: arrow.end),
            ]
        case .text(let textBox):
            let corner = CGPoint(
                x: textBox.origin.x + textBox.measuredSize.width,
                y: textBox.origin.y + textBox.measuredSize.height
            )
            return [ResizeHandle(kind: .textCorner, position: corner)]
        case .bubble(let speechBubble):
            let rect = speechBubble.bodyRect
            return [
                ResizeHandle(kind: .bubbleCorner(.topLeft), position: CGPoint(x: rect.minX, y: rect.minY)),
                ResizeHandle(kind: .bubbleCorner(.topRight), position: CGPoint(x: rect.maxX, y: rect.minY)),
                ResizeHandle(kind: .bubbleCorner(.bottomLeft), position: CGPoint(x: rect.minX, y: rect.maxY)),
                ResizeHandle(kind: .bubbleCorner(.bottomRight), position: CGPoint(x: rect.maxX, y: rect.maxY)),
            ]
        }
    }

    /// Returns a copy of this annotation with `handle` dragged to `point`
    /// (native-pixel space). `self` must be the drag's original, unmodified
    /// snapshot -- callers re-derive from that same snapshot on every drag
    /// tick (rather than compounding onto the previous tick's result) so a
    /// resize can't drift.
    func resized(handle: ResizeHandle.Kind, to point: CGPoint) -> Annotation {
        switch (self, handle) {
        case (.arrow(var arrow), .arrowStart):
            arrow.start = point
            return .arrow(arrow)
        case (.arrow(var arrow), .arrowEnd):
            arrow.end = point
            return .arrow(arrow)
        case (.text(var textBox), .textCorner):
            textBox.fontSize = TextBox.scaledFontSize(for: textBox, draggingCornerTo: point)
            return .text(textBox)
        case (.bubble(var speechBubble), .bubbleCorner(let corner)):
            speechBubble.bodyRect = SpeechBubble.resizedRect(speechBubble.bodyRect, corner: corner, draggedTo: point)
            return .bubble(speechBubble)
        default:
            return self
        }
    }
}

/// One draggable resize control point an annotation exposes when selected.
/// `position` is in the same native-pixel space as the annotation's own
/// geometry; `kind` identifies which control point so
/// `Annotation.resized(handle:to:)` knows how to apply a drag to it.
struct ResizeHandle {
    enum Kind: Equatable {
        case arrowStart
        case arrowEnd
        case textCorner
        case bubbleCorner(Corner)
    }

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    let kind: Kind
    let position: CGPoint
}

// MARK: - Arrow

/// A straight line from `start` to `end`, capped with an arrowhead at `end`.
struct Arrow: Identifiable {
    static let defaultLineWidth: CGFloat = 14
    /// Arrowhead length as a multiple of the shaft's `lineWidth`, so the head
    /// stays proportioned to the shaft at every thickness.
    private static let arrowheadLengthMultiplier: CGFloat = 4
    private static let arrowheadAngle: CGFloat = .pi / 7

    let id = UUID()
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat

    init(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat = Arrow.defaultLineWidth) {
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let arrowheadLength = lineWidth * Self.arrowheadLengthMultiplier
        let angle = atan2(end.y - start.y, end.x - start.x)
        let leftWingAngle = angle + .pi - Self.arrowheadAngle
        let rightWingAngle = angle + .pi + Self.arrowheadAngle
        let leftWing = CGPoint(
            x: end.x + arrowheadLength * cos(leftWingAngle),
            y: end.y + arrowheadLength * sin(leftWingAngle)
        )
        let rightWing = CGPoint(
            x: end.x + arrowheadLength * cos(rightWingAngle),
            y: end.y + arrowheadLength * sin(rightWingAngle)
        )

        context.setFillColor(color.cgColor)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: leftWing)
        context.addLine(to: rightWing)
        context.closePath()
        context.fillPath()
    }

    /// Shortest distance from `point` to the line segment from `start` to
    /// `end`, used for hit-testing since an arrow's bounding box would
    /// otherwise make its whole diagonal span (including empty corners)
    /// clickable.
    func distance(to point: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

// MARK: - TextBox

/// A plain string drawn starting at `origin`.
struct TextBox: Identifiable {
    static let defaultFontSize: CGFloat = 24
    static let minFontSize: CGFloat = 8
    static let maxFontSize: CGFloat = 200

    let id = UUID()
    var origin: CGPoint
    var text: String
    var color: NSColor
    var fontSize: CGFloat

    init(origin: CGPoint, text: String, color: NSColor, fontSize: CGFloat = TextBox.defaultFontSize) {
        self.origin = origin
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }

    /// Draws `text` with `origin` as its top-left corner, matching the
    /// flipped, top-left-origin convention documented on `Annotation`.
    func draw(in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        context.saveGState()
        defer { context.restoreGState() }

        // CoreText draws with a bottom-left text origin in an unflipped
        // (math) coordinate space. Our context is flipped/top-left, so flip
        // locally around the text's own baseline before invoking CTLineDraw,
        // and offset by the line's ascent so `origin` reads as the visual
        // top-left corner of the rendered text.
        context.textMatrix = .identity
        context.translateBy(x: origin.x, y: origin.y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: 0)
        CTLineDraw(line, context)
    }

    /// The rendered size of `text` at `fontSize`, matching the bounds
    /// `draw(in:)` lays the glyphs out within. Used for hit-testing and the
    /// selection outline.
    var measuredSize: CGSize {
        let attributedString = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        return CGSize(width: bounds.width, height: bounds.height)
    }

    /// The font size that moves `original`'s bottom-right corner to `point`,
    /// keeping `origin` fixed as the resize anchor. `original` must be the
    /// drag's unmodified starting snapshot -- see `Annotation.resized(handle:to:)`.
    static func scaledFontSize(for original: TextBox, draggingCornerTo point: CGPoint) -> CGFloat {
        let originalSize = original.measuredSize
        let originalDistance = hypot(originalSize.width, originalSize.height)
        guard originalDistance > 0 else { return original.fontSize }

        let newDistance = hypot(point.x - original.origin.x, point.y - original.origin.y)
        let scale = newDistance / originalDistance
        return min(max(original.fontSize * scale, minFontSize), maxFontSize)
    }
}

// MARK: - SpeechBubble

/// A rounded-rect bubble containing `text`, with a triangular tail pointing
/// toward `tailTarget`.
struct SpeechBubble: Identifiable {
    private static let cornerRadius: CGFloat = 12
    private static let strokeWidth: CGFloat = 2
    private static let textInset: CGFloat = 12
    private static let tailBaseWidth: CGFloat = 16
    private static let minBodySize: CGFloat = 32

    let id = UUID()
    var bodyRect: CGRect
    var tailTarget: CGPoint
    var text: String
    var color: NSColor
    var fontSize: CGFloat

    init(
        bodyRect: CGRect,
        tailTarget: CGPoint,
        text: String,
        color: NSColor,
        fontSize: CGFloat = TextBox.defaultFontSize
    ) {
        self.bodyRect = bodyRect
        self.tailTarget = tailTarget
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }

    func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let path = bubblePath()
        context.addPath(path)
        context.setFillColor(color.withAlphaComponent(0.15).cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(Self.strokeWidth)
        context.drawPath(using: .fillStroke)

        let textOrigin = CGPoint(
            x: bodyRect.minX + Self.textInset,
            y: bodyRect.minY + Self.textInset
        )
        TextBox(origin: textOrigin, text: text, color: color, fontSize: fontSize).draw(in: context)
    }

    /// Resizes `original` by dragging `corner` to `point`, keeping the
    /// opposite corner fixed -- mirrors how the initial bubble-creation drag
    /// builds a rect from two corners. Clamped to `minBodySize` so a corner
    /// dragged past its opposite can't collapse the rect to zero (which would
    /// break `anchorPoint`'s straight-segment math).
    static func resizedRect(_ original: CGRect, corner: ResizeHandle.Corner, draggedTo point: CGPoint) -> CGRect {
        let fixed: CGPoint
        switch corner {
        case .topLeft: fixed = CGPoint(x: original.maxX, y: original.maxY)
        case .topRight: fixed = CGPoint(x: original.minX, y: original.maxY)
        case .bottomLeft: fixed = CGPoint(x: original.maxX, y: original.minY)
        case .bottomRight: fixed = CGPoint(x: original.minX, y: original.minY)
        }

        return CGRect(
            x: min(point.x, fixed.x),
            y: min(point.y, fixed.y),
            width: max(abs(point.x - fixed.x), minBodySize),
            height: max(abs(point.y - fixed.y), minBodySize)
        )
    }

    /// Which straight edge of the rounded rect the tail attaches to.
    private enum Edge {
        case top, right, bottom, left
    }

    /// Builds the rounded rect and tail as a **single** closed path, so
    /// filling/stroking never leaves a seam where the tail meets the body.
    ///
    /// A naive implementation combines a full rounded-rect subpath with a
    /// separate triangular tail subpath. Filling that union looks fine
    /// (overlapping fill regions merge), but stroking it draws the body's own
    /// border *underneath* the tail too, producing a visible line across the
    /// tail's base. Instead this traces the rounded rect's perimeter once,
    /// replacing the straight segment at the tail's anchor with a detour out
    /// to `tailTarget` and back, so there is exactly one boundary to stroke.
    private func bubblePath() -> CGPath {
        let halfBase = Self.tailBaseWidth / 2
        let (anchor, edge) = anchorPoint(on: bodyRect, cornerRadius: Self.cornerRadius, halfBase: halfBase, towards: tailTarget)
        let isHorizontalEdge = (edge == .top || edge == .bottom)
        let baseA = isHorizontalEdge
            ? CGPoint(x: anchor.x - halfBase, y: anchor.y)
            : CGPoint(x: anchor.x, y: anchor.y - halfBase)
        let baseB = isHorizontalEdge
            ? CGPoint(x: anchor.x + halfBase, y: anchor.y)
            : CGPoint(x: anchor.x, y: anchor.y + halfBase)

        let rect = bodyRect
        let r = Self.cornerRadius
        // The four straight edges and their trailing corner arc, traced in
        // order starting just after the top-left corner. Each arc's start
        // and end points are verified to coincide exactly with the
        // neighboring straight segments, so the whole perimeter closes.
        let segments: [(edge: Edge, start: CGPoint, end: CGPoint, arcCenter: CGPoint, arcStart: CGFloat, arcEnd: CGFloat)] = [
            (.top, CGPoint(x: rect.minX + r, y: rect.minY), CGPoint(x: rect.maxX - r, y: rect.minY),
             CGPoint(x: rect.maxX - r, y: rect.minY + r), -.pi / 2, 0),
            (.right, CGPoint(x: rect.maxX, y: rect.minY + r), CGPoint(x: rect.maxX, y: rect.maxY - r),
             CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0, .pi / 2),
            (.bottom, CGPoint(x: rect.maxX - r, y: rect.maxY), CGPoint(x: rect.minX + r, y: rect.maxY),
             CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2, .pi),
            (.left, CGPoint(x: rect.minX, y: rect.maxY - r), CGPoint(x: rect.minX, y: rect.minY + r),
             CGPoint(x: rect.minX + r, y: rect.minY + r), .pi, 3 * .pi / 2),
        ]

        let path = CGMutablePath()
        path.move(to: segments[0].start)

        for segment in segments {
            if segment.edge == edge {
                // Whichever base point is nearer this segment's start comes
                // first, so the detour is spliced in with the correct
                // orientation regardless of which direction this edge is
                // traced in.
                let distanceAToStart = hypot(baseA.x - segment.start.x, baseA.y - segment.start.y)
                let distanceBToStart = hypot(baseB.x - segment.start.x, baseB.y - segment.start.y)
                let (firstBase, secondBase) = distanceAToStart < distanceBToStart ? (baseA, baseB) : (baseB, baseA)
                path.addLine(to: firstBase)
                path.addLine(to: tailTarget)
                path.addLine(to: secondBase)
            }
            path.addLine(to: segment.end)
            path.addArc(center: segment.arcCenter, radius: r, startAngle: segment.arcStart, endAngle: segment.arcEnd, clockwise: false)
        }

        path.closeSubpath()
        return path
    }

    /// Finds the point on `rect`'s perimeter closest to `target`, clamped
    /// away from the rounded corners by `cornerRadius + halfBase` so the
    /// tail's full base width always lies on a straight segment.
    private func anchorPoint(
        on rect: CGRect,
        cornerRadius: CGFloat,
        halfBase: CGFloat,
        towards target: CGPoint
    ) -> (point: CGPoint, edge: Edge) {
        let safeInset = cornerRadius + halfBase
        let clampedX = min(max(target.x, rect.minX), rect.maxX)
        let clampedY = min(max(target.y, rect.minY), rect.maxY)

        let distanceToLeft = abs(clampedX - rect.minX)
        let distanceToRight = abs(clampedX - rect.maxX)
        let distanceToTop = abs(clampedY - rect.minY)
        let distanceToBottom = abs(clampedY - rect.maxY)
        let minDistance = min(distanceToLeft, distanceToRight, distanceToTop, distanceToBottom)

        // Rectangles smaller than 2x the safe inset have no room for a
        // full-width tail base on a straight segment; clamping still keeps
        // the tail on the segment's midpoint rather than crashing.
        let safeMinX = min(rect.minX + safeInset, rect.midX)
        let safeMaxX = max(rect.maxX - safeInset, rect.midX)
        let safeMinY = min(rect.minY + safeInset, rect.midY)
        let safeMaxY = max(rect.maxY - safeInset, rect.midY)

        switch minDistance {
        case distanceToLeft:
            return (CGPoint(x: rect.minX, y: min(max(clampedY, safeMinY), safeMaxY)), .left)
        case distanceToRight:
            return (CGPoint(x: rect.maxX, y: min(max(clampedY, safeMinY), safeMaxY)), .right)
        case distanceToTop:
            return (CGPoint(x: min(max(clampedX, safeMinX), safeMaxX), y: rect.minY), .top)
        default:
            return (CGPoint(x: min(max(clampedX, safeMinX), safeMaxX), y: rect.maxY), .bottom)
        }
    }
}
