import AppKit
import Carbon.HIToolbox

/// Full-desktop transparent overlay that lets the user drag out an
/// arbitrary rectangle for area capture.
///
/// One window is created **per connected screen** (rather than a single
/// window spanning their combined bounds) since macOS treats each display as
/// its own independent space by default; a single window stretched across
/// multiple displays can fail to reliably receive mouse events on whichever
/// display it isn't currently "backed" by. Each window handles its own
/// independent drag entirely in its own screen's coordinate space -- a
/// capture can't span two physical displays as one image via ScreenCaptureKit
/// anyway, so confining a drag to the screen it started on isn't a
/// regression. All the per-screen windows complete together -- finishing or
/// cancelling on any one of them resolves the whole presentation.
@MainActor
final class RegionSelectionOverlayWindow: NSWindow {

    /// Window level high enough to sit above all normal app windows,
    /// matching the system screenshot UI.
    private static let overlayWindowLevel: NSWindow.Level = .screenSaver

    private let interactiveView: RegionSelectionInteractiveView

    private init(screen: NSScreen, onFinish: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        let frame = screen.frame
        let view = RegionSelectionInteractiveView(frame: NSRect(origin: .zero, size: frame.size))
        view.instructionText = "Drag to select an area to capture, or press Esc to cancel"
        view.instructionScreenFrame = screen.visibleFrame.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
        view.onFinish = onFinish
        view.onCancel = onCancel
        self.interactiveView = view

        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = Self.overlayWindowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = view
    }

    /// Presents one overlay per connected screen and awaits a drag-to-select
    /// gesture on whichever one the user drags in.
    ///
    /// - Returns: The selected rectangle (in AppKit screen coordinates) and
    ///   the `NSScreen` it was drawn on, or `nil` if the user cancelled
    ///   with Esc.
    static func present() async -> (rect: CGRect, screen: NSScreen)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            var didFinish = false
            var overlays: [RegionSelectionOverlayWindow] = []

            @MainActor func finish(with result: (rect: CGRect, screen: NSScreen)?) {
                guard !didFinish else { return }
                didFinish = true
                overlays.forEach { $0.orderOut(nil) }
                continuation.resume(returning: result)
            }

            overlays = screens.map { screen in
                RegionSelectionOverlayWindow(
                    screen: screen,
                    onFinish: { viewRect in
                        guard viewRect.width > 1, viewRect.height > 1 else {
                            finish(with: nil)
                            return
                        }
                        // This window's view bounds origin coincides with
                        // its own screen's frame origin, so converting to
                        // screen coordinates is a simple translation rather
                        // than a full NSWindow/NSView coordinate conversion.
                        let screenRect = viewRect.offsetBy(dx: screen.frame.origin.x, dy: screen.frame.origin.y)
                        finish(with: (rect: screenRect, screen: screen))
                    },
                    onCancel: { finish(with: nil) }
                )
            }

            // Snaplet is `LSUIElement`; without activating first, these
            // windows can fail to reliably become key when another app was
            // frontmost when the hotkey/menu item fired -- the common case
            // for a screenshot tool.
            NSApp.activate(ignoringOtherApps: true)
            overlays.forEach { $0.orderFrontRegardless() }
            // Exactly one window can be key at a time; any of them becoming
            // key routes Esc to the same shared `onCancel`, so which one
            // doesn't matter. `becomeKey()` below keeps first responder
            // correct if a click on a different screen later steals it.
            overlays.first?.makeKey()
            overlays.forEach { $0.invalidateCursorRects(for: $0.interactiveView) }
        }
    }

    override var canBecomeKey: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(interactiveView)
    }
}

/// Interactive view backing `RegionSelectionOverlayWindow`: tracks a
/// mouse-drag gesture to build the highlight rectangle and listens for Esc.
@MainActor
private final class RegionSelectionInteractiveView: SelectionOverlayView {

    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?

    /// Snaplet's focus-reticle mark as the area-capture cursor, so the cursor
    /// itself signals "you're selecting an area" and reinforces the app's
    /// identity. Drawn white with a dark halo to stay visible over any screen
    /// content; the hot spot is the reticle's center dot.
    private let reticleCursor: NSCursor = {
        let size: CGFloat = 28
        let image = SnapletGlyph.image(size: size, color: .white, haloColor: .black)
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: reticleCursor)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        highlightRect = CGRect(origin: point, size: .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        highlightRect = CGRect(
            x: min(dragStart.x, point.x),
            y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x),
            height: abs(point.y - dragStart.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        let rect = highlightRect ?? .zero
        dragStart = nil
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }
}
