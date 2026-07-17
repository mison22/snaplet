import Carbon
import XCTest

@testable import Snaplet

/// Covers the pure/data logic around hotkeys: default mapping, persistence,
/// equality, and display rendering. Deliberately does not call
/// `HotKeyManager.register` with real Carbon defaults in a loop or assert on
/// its success — registering system-wide hotkeys from CI would be flaky and
/// could collide with hotkeys already held by the test runner's host.
final class HotKeyManagerTests: XCTestCase {

    // MARK: - HotKeyDefinition.defaults

    func testDefaultsMapFullScreenFromAppConstants() {
        let definition = HotKeyDefinition.defaults.first { $0.action == .fullScreen }
        XCTAssertEqual(definition?.keyCode, AppConstants.fullScreenHotKeyDefault.keyCode)
        XCTAssertEqual(definition?.modifiers, AppConstants.fullScreenHotKeyDefault.modifiers)
        XCTAssertEqual(definition?.keyCode, UInt32(kVK_ANSI_S))
    }

    func testDefaultsMapWindowFromAppConstants() {
        let definition = HotKeyDefinition.defaults.first { $0.action == .window }
        XCTAssertEqual(definition?.keyCode, AppConstants.windowHotKeyDefault.keyCode)
        XCTAssertEqual(definition?.modifiers, AppConstants.windowHotKeyDefault.modifiers)
        XCTAssertEqual(definition?.keyCode, UInt32(kVK_ANSI_W))
    }

    func testDefaultsMapAreaFromAppConstants() {
        let definition = HotKeyDefinition.defaults.first { $0.action == .area }
        XCTAssertEqual(definition?.keyCode, AppConstants.areaHotKeyDefault.keyCode)
        XCTAssertEqual(definition?.modifiers, AppConstants.areaHotKeyDefault.modifiers)
        XCTAssertEqual(definition?.keyCode, UInt32(kVK_ANSI_A))
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = HotKeyDefinition(action: .fullScreen, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyDefinition.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Equatable

    func testEquatableDistinguishesKeyCode() {
        let base = HotKeyDefinition(action: .fullScreen, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))
        let differentKey = HotKeyDefinition(action: .fullScreen, keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(optionKey | shiftKey))
        XCTAssertNotEqual(base, differentKey)
    }

    func testEquatableDistinguishesAction() {
        let base = HotKeyDefinition(action: .fullScreen, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))
        let differentAction = HotKeyDefinition(action: .window, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))
        XCTAssertNotEqual(base, differentAction)
    }

    func testEquatableTreatsIdenticalValuesAsEqual() {
        let base = HotKeyDefinition(action: .area, keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | shiftKey))
        let same = HotKeyDefinition(action: .area, keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | shiftKey))
        XCTAssertEqual(base, same)
    }

    // MARK: - displayString

    func testDisplayStringForFullScreenDefault() {
        let definition = HotKeyDefinition(action: .fullScreen, default: AppConstants.fullScreenHotKeyDefault)
        XCTAssertEqual(definition.displayString, "⌥⇧S")
    }

    func testDisplayStringForWindowDefault() {
        let definition = HotKeyDefinition(action: .window, default: AppConstants.windowHotKeyDefault)
        XCTAssertEqual(definition.displayString, "⌥⇧W")
    }

    func testDisplayStringForAreaDefault() {
        let definition = HotKeyDefinition(action: .area, default: AppConstants.areaHotKeyDefault)
        XCTAssertEqual(definition.displayString, "⌥⇧A")
    }

    // MARK: - HotKeyManager

    func testUnregisterAllIsSafeWithNothingRegistered() {
        let manager = HotKeyManager()
        manager.unregisterAll()
        manager.unregisterAll()
    }
}
