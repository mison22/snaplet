import AppKit
import CoreGraphics

/// Namespace for checking and requesting Screen Recording permission before
/// any screen capture is attempted.
///
/// macOS distinguishes two ways to check this permission:
/// - `CGRequestScreenCaptureAccess()` prompts the user with the system
///   dialog (only on the very first call for a given app) and returns the
///   access state.
/// - `CGPreflightScreenCaptureAccess()` silently reports the current access
///   state without ever prompting.
///
/// We only want the OS prompt to appear once. After that, re-prompting is
/// pointless (macOS won't show it again) and misleading, so subsequent
/// checks use the silent preflight call and, if access is still missing,
/// this namespace shows Snaplet's own alert pointing the user to System
/// Settings instead.
enum ScreenRecordingPermission {

    /// `UserDefaults` key tracking whether Snaplet has already made its one
    /// permitted `CGRequestScreenCaptureAccess()` prompt.
    ///
    /// Kept private to this file rather than added to
    /// `AppConstants.DefaultsKey` since that enum is owned by another task.
    private static let hasRequestedAccessDefaultsKey = "com.mikeison.Snaplet.screenRecordingRequested"

    /// Deep link into System Settings' Screen Recording privacy pane.
    private static let screenRecordingSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// Checks (and, on first launch only, requests) Screen Recording access.
    ///
    /// - Returns: `true` if Snaplet currently has Screen Recording access.
    static func ensureAccess() -> Bool {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: hasRequestedAccessDefaultsKey) {
            return CGPreflightScreenCaptureAccess()
        }

        defaults.set(true, forKey: hasRequestedAccessDefaultsKey)
        return CGRequestScreenCaptureAccess()
    }

    /// Verifies Screen Recording access is available and, if not, surfaces a
    /// modal alert directing the user to System Settings.
    ///
    /// Call this immediately before every capture. The `CaptureEngine` must
    /// abort the capture whenever this returns `false` — never proceed
    /// without confirmed access.
    ///
    /// - Returns: `true` only when the caller may proceed with a capture.
    @discardableResult
    static func requestIfNeededAndVerify() -> Bool {
        if ensureAccess() {
            return true
        }

        presentAccessRequiredAlert()
        return false
    }

    /// Shows the modal alert explaining why Screen Recording access is
    /// needed and, on request, opens System Settings to the relevant pane.
    private static func presentAccessRequiredAlert() {
        assert(Thread.isMainThread, "NSAlert must be presented on the main thread")

        let alert = NSAlert()
        alert.messageText = "Screen Recording Access Required"
        alert.informativeText = "Snaplet needs Screen Recording permission to capture your screen. " +
            "Grant access in System Settings, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              let settingsURL = URL(string: screenRecordingSettingsURLString) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
}
