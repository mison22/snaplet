import AppKit

/// Shared crosshair/dimming visual used by both the region- and
/// window-selection overlays.
///
/// Kept separate from the interactive (mouse-tracking) logic in
/// `RegionSelectionOverlayWindow` and `WindowSelectionOverlayWindow` so the
/// drawing code isn't duplicated between the two.
class SelectionOverlayView: NSView {

    /// Alpha of the dimmed backdrop drawn over the whole screen.
    private static let backdropAlpha: CGFloat = 0.25
    /// Width of the border stroked around the current highlight rectangle.
    private static let highlightBorderWidth: CGFloat = 2.0
    /// Color used for the highlight rectangle's border.
    private static let highlightBorderColor = NSColor.white

    /// Styling for the instruction badge -- a dimmed overlay alone doesn't
    /// tell the user a gesture (hover+click, or drag) is expected, so this
    /// spells it out the way macOS's own screenshot UI does.
    private static let instructionFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private static let instructionTopMargin: CGFloat = 16
    private static let instructionHorizontalPadding: CGFloat = 16
    private static let instructionVerticalPadding: CGFloat = 10
    private static let instructionBackgroundAlpha: CGFloat = 0.6

    /// The rectangle (in this view's own coordinate space) to leave
    /// undimmed and outline. `nil` draws only the dimmed backdrop.
    var highlightRect: CGRect? {
        didSet { needsDisplay = true }
    }

    /// Short instruction shown in a pill near the top of the screen, e.g.
    /// "Click a window to capture it". Each concrete overlay sets its own
    /// wording for the gesture it expects.
    var instructionText: String? {
        didSet { needsDisplay = true }
    }

    /// The active screen's *visible* frame (in this view's own local
    /// coordinate space) to center the instruction badge within. This
    /// view's `bounds` spans the union of every connected display, not any
    /// one screen -- without this, "near the top" of that union can land on
    /// a different monitor than the one the user is looking at, or in the
    /// gap between displays entirely. Using `visibleFrame` (rather than the
    /// full `frame` this overlay dims) additionally keeps the badge clear of
    /// the real menu bar/notch, whose reserved height varies by Mac model.
    /// Set once by the presenting overlay to whichever screen was under the
    /// cursor when it appeared.
    var instructionScreenFrame: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.withAlphaComponent(Self.backdropAlpha).cgColor)
        context.fill(bounds)

        if let rect = highlightRect, rect.width > 0, rect.height > 0 {
            // Punch a clear "hole" out of the dimmed backdrop so the selected
            // area previews at full brightness, matching macOS's own capture UI.
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            context.setStrokeColor(Self.highlightBorderColor.cgColor)
            context.setLineWidth(Self.highlightBorderWidth)
            context.stroke(rect.insetBy(dx: Self.highlightBorderWidth / 2, dy: Self.highlightBorderWidth / 2))
        }

        drawInstructionBadge()
    }

    private func drawInstructionBadge() {
        guard let instructionText else { return }

        let attributedString = NSAttributedString(
            string: instructionText,
            attributes: [.font: Self.instructionFont, .foregroundColor: NSColor.white]
        )
        let textSize = attributedString.size()
        let badgeSize = CGSize(
            width: textSize.width + Self.instructionHorizontalPadding * 2,
            height: textSize.height + Self.instructionVerticalPadding * 2
        )
        let screenFrame = instructionScreenFrame ?? bounds
        let badgeRect = CGRect(
            x: screenFrame.minX + (screenFrame.width - badgeSize.width) / 2,
            y: screenFrame.maxY - Self.instructionTopMargin - badgeSize.height,
            width: badgeSize.width,
            height: badgeSize.height
        )

        NSColor.black.withAlphaComponent(Self.instructionBackgroundAlpha).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: badgeSize.height / 2, yRadius: badgeSize.height / 2).fill()

        attributedString.draw(at: CGPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        ))
    }
}
