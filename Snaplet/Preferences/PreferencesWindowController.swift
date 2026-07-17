import AppKit
import SwiftUI

/// Owns the single Preferences window, hosting `PreferencesView` via
/// `NSHostingController`.
///
/// Callers (Wave 3's `AppDelegate`) should keep exactly one instance around
/// (e.g. as a stored property) and call `show()` whenever the user opens
/// Preferences, rather than constructing a new controller per invocation —
/// `show()` re-uses the existing window instead of spawning duplicates.
@MainActor
final class PreferencesWindowController: NSWindowController {

    private static let windowTitle = "Snaplet Preferences"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: PreferencesView.Layout.windowWidth,
                height: PreferencesView.Layout.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = PreferencesWindowController.windowTitle
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: PreferencesView())

        self.init(window: window)
    }

    /// Brings Snaplet and the Preferences window to the foreground. See
    /// `NSWindowController.activateAndShowWindow()`.
    ///
    /// Safe to call repeatedly: since `window.isReleasedWhenClosed` is
    /// `false`, the same `NSWindow` is reused after the user closes it, so
    /// this never creates a second Preferences window.
    func show() {
        activateAndShowWindow()
    }
}
