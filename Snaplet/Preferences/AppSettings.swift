import Foundation

/// Shared, observable app settings backing both the annotation Save/Copy
/// actions and the Preferences UI.
///
/// `@MainActor` because it is an `ObservableObject` bound into SwiftUI views;
/// all mutation and observation happens on the main thread.
@MainActor
final class AppSettings: ObservableObject {

    /// App-wide singleton. Pragmatic for a personal, single-window-less menu
    /// bar app: there is exactly one save directory and one set of hotkeys,
    /// and every consumer (menu bar, capture pipeline, Preferences window)
    /// needs the same instance.
    static let shared = AppSettings()

    /// Key for the JSON-encoded `[HotKeyDefinition]` array. Reuses the
    /// existing per-action `DefaultsKey` cases would require three separate
    /// reads/writes kept in sync; storing the whole array under one key is
    /// simpler and just as easy to migrate later, so that's the choice made
    /// here.
    private static let hotKeysDefaultsKey = "com.mikeison.Snaplet.hotKeys"

    private let defaults: UserDefaults

    /// The directory screenshots are saved to.
    ///
    /// Persisted as a plain path string, not a security-scoped bookmark.
    /// Security-scoped bookmarks exist to keep sandboxed apps' file access
    /// alive across launches without re-prompting the user; Snaplet is not
    /// sandboxed, so a plain path is sufficient and avoids the added
    /// complexity of bookmark staleness/resolution.
    @Published var saveDirectory: URL {
        didSet {
            defaults.set(saveDirectory.path, forKey: AppConstants.DefaultsKey.saveDirectoryPath.rawValue)
        }
    }

    /// Current global hotkey bindings, one per `HotKeyAction`.
    @Published var hotKeys: [HotKeyDefinition] {
        didSet {
            persistHotKeys()
        }
    }

    /// - Parameter defaults: The `UserDefaults` domain to read/write.
    ///   Defaults to `.standard`; tests should inject an isolated
    ///   `UserDefaults(suiteName:)` instance instead.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedPath = defaults.string(forKey: AppConstants.DefaultsKey.saveDirectoryPath.rawValue) {
            self.saveDirectory = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.saveDirectory = AppConstants.defaultSaveDirectory
        }

        if let data = defaults.data(forKey: AppSettings.hotKeysDefaultsKey),
           let decoded = try? JSONDecoder().decode([HotKeyDefinition].self, from: data) {
            self.hotKeys = decoded
        } else {
            self.hotKeys = HotKeyDefinition.defaults
        }
    }

    /// Creates `saveDirectory` (and any missing intermediate directories) if
    /// it does not already exist. Called by the Save action before writing a
    /// screenshot so a missing/relocated folder doesn't fail the save.
    func ensureSaveDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: saveDirectory,
            withIntermediateDirectories: true
        )
    }

    /// The current binding for a given action, falling back to its built-in
    /// default if `hotKeys` somehow lacks an entry for it.
    func hotKey(for action: HotKeyAction) -> HotKeyDefinition {
        hotKeys.first { $0.action == action }
            ?? HotKeyDefinition.defaults.first { $0.action == action }!
    }

    /// Replaces the binding for `def.action` with `def` and persists the
    /// updated set.
    func setHotKey(_ def: HotKeyDefinition) {
        var updated = hotKeys
        if let index = updated.firstIndex(where: { $0.action == def.action }) {
            updated[index] = def
        } else {
            updated.append(def)
        }
        hotKeys = updated
    }

    /// Returns any other actions whose current binding shares `candidate`'s
    /// key code and modifiers, i.e. would conflict if `candidate` were
    /// applied. Used by Preferences to warn before committing a rebind.
    func actionsConflicting(with candidate: HotKeyDefinition) -> [HotKeyAction] {
        hotKeys
            .filter { $0.action != candidate.action }
            .filter { $0.keyCode == candidate.keyCode && $0.modifiers == candidate.modifiers }
            .map(\.action)
    }

    private func persistHotKeys() {
        guard let data = try? JSONEncoder().encode(hotKeys) else { return }
        defaults.set(data, forKey: AppSettings.hotKeysDefaultsKey)
    }
}
