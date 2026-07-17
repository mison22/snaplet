import Foundation

/// The three ways a user can trigger a Snaplet screenshot.
enum CaptureMode {
    /// Captures the entire display holding the currently focused window
    /// (`NSScreen.main`).
    case fullScreen
    /// Lets the user click a specific on-screen window to capture.
    case window
    /// Lets the user drag out an arbitrary rectangular region to capture.
    case area
}
