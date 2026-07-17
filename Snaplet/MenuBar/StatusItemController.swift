import AppKit

/// Owns Snaplet's menu-bar (status item) presence and its dropdown menu.
///
/// This controller only builds UI and exposes callbacks; it has no knowledge
/// of capture, annotation, or preferences types. `AppDelegate` wires the
/// actual behavior into the callback properties.
final class StatusItemController {

    // MARK: - Menu item titles

    private static let captureFullScreenTitle = "Capture Full Screen"
    private static let captureWindowTitle = "Capture Window"
    private static let captureAreaTitle = "Capture Area"
    private static let preferencesTitle = "Preferences…"
    private static let quitTitle = "Quit Snaplet"

    /// Point size the Snaplet reticle mark is rendered at for the menu bar.
    private static let statusIconSize: CGFloat = 18

    /// Tooltip shown when hovering the status item.
    private static let statusItemTooltip = "Snaplet"

    // MARK: - Public callbacks

    /// Invoked when the user selects "Capture Full Screen".
    var onCaptureFullScreen: (() -> Void)?

    /// Invoked when the user selects "Capture Window".
    var onCaptureWindow: (() -> Void)?

    /// Invoked when the user selects "Capture Area".
    var onCaptureArea: (() -> Void)?

    /// Invoked when the user selects "Preferences…".
    var onOpenPreferences: (() -> Void)?

    // MARK: - Private state

    /// Retained for the lifetime of the app; releasing it removes the item
    /// from the menu bar.
    private let statusItem: NSStatusItem

    // MARK: - Init

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let icon = SnapletGlyph.image(size: Self.statusIconSize, color: .black, isTemplate: true)
            icon.accessibilityDescription = Self.statusItemTooltip
            button.image = icon
            button.toolTip = Self.statusItemTooltip
        }

        statusItem.menu = Self.buildMenu(target: self)
    }

    // MARK: - Menu construction

    private static func buildMenu(target: StatusItemController) -> NSMenu {
        let menu = NSMenu()

        let captureFullScreenItem = NSMenuItem(
            title: captureFullScreenTitle,
            action: #selector(StatusItemController.captureFullScreenSelected),
            keyEquivalent: ""
        )
        captureFullScreenItem.target = target

        let captureWindowItem = NSMenuItem(
            title: captureWindowTitle,
            action: #selector(StatusItemController.captureWindowSelected),
            keyEquivalent: ""
        )
        captureWindowItem.target = target

        let captureAreaItem = NSMenuItem(
            title: captureAreaTitle,
            action: #selector(StatusItemController.captureAreaSelected),
            keyEquivalent: ""
        )
        captureAreaItem.target = target

        let preferencesItem = NSMenuItem(
            title: preferencesTitle,
            action: #selector(StatusItemController.preferencesSelected),
            keyEquivalent: ""
        )
        preferencesItem.target = target

        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(StatusItemController.quitSelected),
            keyEquivalent: ""
        )
        quitItem.target = target

        menu.addItem(captureFullScreenItem)
        menu.addItem(captureWindowItem)
        menu.addItem(captureAreaItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu actions

    @objc private func captureFullScreenSelected() {
        onCaptureFullScreen?()
    }

    @objc private func captureWindowSelected() {
        onCaptureWindow?()
    }

    @objc private func captureAreaSelected() {
        onCaptureArea?()
    }

    @objc private func preferencesSelected() {
        onOpenPreferences?()
    }

    @objc private func quitSelected() {
        NSApp.terminate(nil)
    }
}
