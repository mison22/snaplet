import AppKit
import Combine

/// Application delegate for Snaplet.
///
/// Owns every long-lived subsystem — the menu-bar status item, the capture
/// engine, the Preferences window, and global hotkey registration — and
/// wires them into a single capture pipeline (`runCapture`) so the menu
/// items and the global hotkeys drive the exact same flow.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Retained for the app's lifetime; releasing it removes the menu-bar item.
    private var statusItemController: StatusItemController?

    /// Performs the actual screen capture for every entry point.
    private let captureEngine = CaptureEngine()

    /// One Preferences window, reused across every "Preferences…" selection.
    private let preferencesWindowController = PreferencesWindowController()

    /// Registers and dispatches the global capture hotkeys.
    private let hotKeyManager = HotKeyManager()

    /// Annotation windows currently open, keyed by their `NSWindow`. Each
    /// controller must stay retained for as long as its window is open —
    /// without this, the controller (and its window) would deinit
    /// immediately after `show()` returns.
    private var openAnnotationWindowControllers: [NSWindow: AnnotationWindowController] = [:]

    /// The `willCloseNotification` observer for each open annotation window,
    /// so it can be removed when the window closes rather than accumulating
    /// one dead registration per capture.
    private var annotationCloseObservers: [NSWindow: NSObjectProtocol] = [:]

    /// Keeps the Combine subscription that re-registers hotkeys on rebind
    /// alive for the app's lifetime.
    private var hotKeySubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController()
        controller.onCaptureFullScreen = { [weak self] in self?.runCapture(.fullScreen) }
        controller.onCaptureWindow = { [weak self] in self?.runCapture(.window) }
        controller.onCaptureArea = { [weak self] in self?.runCapture(.area) }
        controller.onOpenPreferences = { [weak self] in self?.preferencesWindowController.show() }
        statusItemController = controller

        hotKeyManager.onHotKey = { [weak self] action in self?.runCapture(CaptureMode(action)) }
        registerHotKeys(AppSettings.shared.hotKeys)

        // Preferences can rebind hotkeys while the app is running; re-register
        // the full set on every change so a rebind takes effect immediately,
        // without requiring a relaunch. `dropFirst()` skips the initial
        // synchronous emission from `@Published`, which duplicates the
        // registration already performed above.
        hotKeySubscription = AppSettings.shared.$hotKeys
            .dropFirst()
            .sink { [weak self] updatedHotKeys in
                self?.registerHotKeys(updatedHotKeys)
            }
    }

    /// Registers `definitions` with `hotKeyManager`, logging and surfacing a
    /// non-fatal alert on failure rather than crashing the app.
    private func registerHotKeys(_ definitions: [HotKeyDefinition]) {
        do {
            try hotKeyManager.register(definitions)
        } catch {
            NSLog("Snaplet: failed to register hotkeys: \(error)")

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Register Hotkeys"
            alert.informativeText = "Snaplet's global keyboard shortcuts are unavailable. You can still capture from the menu bar."
            alert.runModal()
        }
    }

    /// Runs the shared capture → annotate flow for `mode`. Both the status
    /// item's menu actions and the global hotkeys call this same method, so
    /// there is exactly one capture pipeline in the app.
    private func runCapture(_ mode: CaptureMode) {
        Task { @MainActor in
            guard let captured = await captureEngine.capture(mode) else {
                // Permission failure already alerted inside the engine;
                // user cancellation (Esc) is a normal no-op.
                return
            }

            let annotationController = AnnotationWindowController(image: captured.cgImage, captureScale: captured.scale)
            guard let window = annotationController.window else { return }

            openAnnotationWindowControllers[window] = annotationController
            annotationCloseObservers[window] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] notification in
                guard let self, let closedWindow = notification.object as? NSWindow else { return }
                // `queue: .main` guarantees this runs on the main thread, so
                // touching the main-actor state here is safe.
                MainActor.assumeIsolated {
                    self.openAnnotationWindowControllers.removeValue(forKey: closedWindow)
                    if let observer = self.annotationCloseObservers.removeValue(forKey: closedWindow) {
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
            }

            annotationController.show()
        }
    }
}

private extension CaptureMode {
    /// Maps a global hotkey action to the capture mode it triggers.
    init(_ action: HotKeyAction) {
        switch action {
        case .fullScreen: self = .fullScreen
        case .window: self = .window
        case .area: self = .area
        }
    }
}
