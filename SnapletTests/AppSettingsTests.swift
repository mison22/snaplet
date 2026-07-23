import Carbon
import XCTest

@testable import Snaplet

/// Covers `AppSettings` persistence and conflict-detection logic against an
/// isolated `UserDefaults` suite so tests never touch the real app domain.
@MainActor
final class AppSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.mikeison.Snaplet.AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - saveDirectory

    func testDefaultSaveDirectoryIsPicturesScreenshots() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.saveDirectory, AppConstants.defaultSaveDirectory)
    }

    func testSettingSaveDirectoryPersistsAndReloads() {
        let settings = AppSettings(defaults: defaults)
        let customDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SnapletTestDir", isDirectory: true)

        settings.saveDirectory = customDirectory

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.saveDirectory.path, customDirectory.path)
    }

    // MARK: - hotKeys

    func testDefaultHotKeysEqualHotKeyDefinitionDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotKeys, HotKeyDefinition.defaults)
    }

    func testSetHotKeyReplacesAndPersists() {
        let settings = AppSettings(defaults: defaults)
        let rebind = HotKeyDefinition(action: .fullScreen, keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(controlKey))

        settings.setHotKey(rebind)

        XCTAssertEqual(settings.hotKey(for: .fullScreen), rebind)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.hotKey(for: .fullScreen), rebind)
    }

    // MARK: - captureResolution

    func testDefaultCaptureResolutionIsHigh() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.captureResolution, .high)
    }

    func testSettingCaptureResolutionPersistsAndReloads() {
        let settings = AppSettings(defaults: defaults)

        settings.captureResolution = .maximum

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.captureResolution, .maximum)
    }

    // MARK: - actionsConflicting

    func testActionsConflictingDetectsCollision() {
        let settings = AppSettings(defaults: defaults)
        let candidate = HotKeyDefinition(
            action: .window,
            keyCode: AppConstants.fullScreenHotKeyDefault.keyCode,
            modifiers: AppConstants.fullScreenHotKeyDefault.modifiers
        )

        let conflicts = settings.actionsConflicting(with: candidate)

        XCTAssertEqual(conflicts, [.fullScreen])
    }

    func testActionsConflictingReturnsEmptyWhenUnique() {
        let settings = AppSettings(defaults: defaults)
        let candidate = HotKeyDefinition(action: .fullScreen, keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(controlKey))

        let conflicts = settings.actionsConflicting(with: candidate)

        XCTAssertEqual(conflicts, [])
    }
}
