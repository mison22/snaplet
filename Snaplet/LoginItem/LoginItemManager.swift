import ServiceManagement

/// Manages whether Snaplet is registered to launch automatically at login.
///
/// Wraps `SMAppService.mainApp` rather than the legacy
/// `SMLoginItemSetEnabled` API (which requires a separate helper-app bundle
/// embedded in the main app) or a `LaunchAgent` plist (which requires
/// hand-maintained XML and manual `launchctl` bookkeeping). `SMAppService`
/// is the modern, sandboxable replacement Apple recommends since macOS 13:
/// it needs no helper target, persists its own registration, and exposes a
/// simple status/register/unregister surface.
@MainActor
final class LoginItemManager: ObservableObject {

    /// Whether Snaplet is currently registered to launch at login.
    ///
    /// Initialized from `SMAppService.mainApp.status` and kept in sync as
    /// `setEnabled(_:)` succeeds, so SwiftUI views (e.g. Preferences) can
    /// bind a `Toggle` directly to this property.
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters Snaplet as a login item.
    ///
    /// On failure, `isEnabled` is reverted to its previous value and the
    /// underlying error is rethrown so the caller (e.g. Preferences) can
    /// surface it to the user.
    func setEnabled(_ enabled: Bool) throws {
        let previousValue = isEnabled

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
        } catch {
            isEnabled = previousValue
            throw error
        }
    }
}
