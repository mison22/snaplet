import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Full-desktop transparent overlay for window-mode capture: highlights the
/// candidate window under the cursor and returns the one the user clicks.
///
/// One window is created **per connected screen** (rather than a single
/// window spanning their combined bounds) since macOS treats each display as
/// its own independent space by default; a single window stretched across
/// multiple displays can fail to reliably receive mouse events on whichever
/// display it isn't currently "backed" by. All the per-screen windows share
/// the same candidate list and complete together -- choosing a window or
/// cancelling on any one of them resolves the whole presentation.
@MainActor
final class WindowSelectionOverlayWindow: NSWindow {

    /// Window level high enough to sit above all normal app windows,
    /// matching the system screenshot UI.
    private static let overlayWindowLevel: NSWindow.Level = .screenSaver

    private let interactiveView: WindowSelectionInteractiveView

    private init(
        screen: NSScreen,
        windows: [SCWindow],
        onChoose: @escaping (SCWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let frame = screen.frame
        let view = WindowSelectionInteractiveView(frame: NSRect(origin: .zero, size: frame.size))
        view.candidateWindows = windows
        view.originOffset = frame.origin
        view.instructionText = "Click a window to capture it, or press Esc to cancel"
        view.instructionScreenFrame = screen.visibleFrame.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
        view.onChoose = onChoose
        view.onCancel = onCancel
        self.interactiveView = view

        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = Self.overlayWindowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = view
    }

    /// Presents one overlay per connected screen over the given candidate
    /// windows.
    ///
    /// - Parameter windows: Candidate `SCWindow`s (Snaplet's own windows
    ///   already excluded by the caller).
    /// - Returns: The chosen `SCWindow`, or `nil` if the user cancelled
    ///   with Esc.
    static func present(windows: [SCWindow]) async -> SCWindow? {
        guard !windows.isEmpty, !NSScreen.screens.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            var didFinish = false
            var overlays: [WindowSelectionOverlayWindow] = []

            @MainActor func finish(with chosen: SCWindow?) {
                guard !didFinish else { return }
                didFinish = true
                overlays.forEach { $0.orderOut(nil) }
                continuation.resume(returning: chosen)
            }

            overlays = NSScreen.screens.map { screen in
                WindowSelectionOverlayWindow(
                    screen: screen,
                    windows: windows,
                    onChoose: { finish(with: $0) },
                    onCancel: { finish(with: nil) }
                )
            }

            // Snaplet is `LSUIElement`; without activating first, these
            // windows can fail to reliably become key -- and so miss
            // `mouseMoved` events -- when another app was frontmost when the
            // hotkey/menu item fired, which is the common case for a
            // screenshot tool.
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

/// Interactive view backing `WindowSelectionOverlayWindow`: tracks mouse
/// movement to highlight the candidate window under the cursor and listens
/// for a click (choose) or Esc (cancel).
@MainActor
private final class WindowSelectionInteractiveView: SelectionOverlayView {

    var candidateWindows: [SCWindow] = []

    /// This overlay window's screen-coordinate origin (AppKit space). Used
    /// to translate between this view's own coordinate space (origin at
    /// zero) and full screen coordinates.
    var originOffset: CGPoint = .zero

    var onChoose: ((SCWindow) -> Void)?
    var onCancel: (() -> Void)?

    private var hoveredWindow: SCWindow?

    override var acceptsFirstResponder: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let screenPoint = CGPoint(x: point.x + originOffset.x, y: point.y + originOffset.y)

        hoveredWindow = candidateWindows.first { appKitFrame(for: $0).contains(screenPoint) }
        highlightRect = hoveredWindow.map { viewRect(for: $0) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let hoveredWindow else { return }
        onChoose?(hoveredWindow)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }

    /// `SCWindow.frame` is in ScreenCaptureKit/Quartz's global display
    /// coordinate space (origin top-left, Y increasing downward), while
    /// this view uses AppKit's screen coordinate space (origin bottom-left,
    /// Y increasing upward). Mixing the two without conversion silently
    /// flips hit-testing vertically.
    private func appKitFrame(for window: SCWindow) -> CGRect {
        window.frame.convertedFromQuartzGlobalSpace()
    }

    private func viewRect(for window: SCWindow) -> CGRect {
        appKitFrame(for: window).offsetBy(dx: -originOffset.x, dy: -originOffset.y)
    }
}
