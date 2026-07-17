import AppKit

extension NSWindowController {
    /// Activates the app and brings this controller's window to the
    /// front/key.
    ///
    /// Snaplet runs as an `LSUIElement` (no Dock icon, no regular activation
    /// policy transitions elsewhere), so without this call a newly shown
    /// window can appear behind whatever app currently has focus.
    func activateAndShowWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
