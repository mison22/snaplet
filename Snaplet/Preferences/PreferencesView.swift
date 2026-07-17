import AppKit
import SwiftUI

/// Root view for the Preferences window: hotkeys, save location, and general
/// (launch-at-login) settings.
///
/// Uses a custom toolbar-style tab header rather than SwiftUI's `TabView`,
/// whose macOS chrome renders inconsistently when hosted in a plain window
/// (collapsing into an overflow menu). Observes `AppSettings.shared` directly
/// since it is a true app-wide singleton every consumer already reaches the
/// same way.
struct PreferencesView: View {

    enum Layout {
        static let windowWidth: CGFloat = 520
        static let windowHeight: CGFloat = 400
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case hotkeys, saveLocation, general
        var id: String { rawValue }

        var title: String {
            switch self {
            case .hotkeys: return "Hotkeys"
            case .saveLocation: return "Save Location"
            case .general: return "General"
            }
        }

        var symbol: String {
            switch self {
            case .hotkeys: return "keyboard"
            case .saveLocation: return "folder"
            case .general: return "gearshape"
            }
        }
    }

    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var loginItem = LoginItemManager()
    @State private var selection: Tab = .hotkeys

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
        .frame(width: Layout.windowWidth, height: Layout.windowHeight)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                TabButton(
                    title: tab.title,
                    symbol: tab.symbol,
                    isSelected: selection == tab,
                    action: { selection = tab }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .hotkeys:
            HotKeysSectionView(settings: settings)
        case .saveLocation:
            SaveLocationSectionView(settings: settings)
        case .general:
            GeneralSectionView(loginItem: loginItem)
        }
    }
}

// MARK: - Tab bar button

private struct TabButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11))
            }
            .frame(width: 92, height: 50)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Section scaffolding

/// Shared header (title + one-line description) so every section reads the
/// same way.
private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hotkeys

/// Lets the user rebind each of Snaplet's three global hotkeys, rejecting any
/// rebind that would collide with one of the other two.
private struct HotKeysSectionView: View {
    @ObservedObject var settings: AppSettings
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Global Hotkeys", subtitle: "Capture from anywhere, even when Snaplet isn't focused.")

            GroupBox {
                VStack(spacing: 10) {
                    ForEach(Array(HotKeyAction.allCases.enumerated()), id: \.element) { index, action in
                        HStack {
                            Text(title(for: action))
                            Spacer()
                            HotKeyRecorder(
                                definition: binding(for: action),
                                isValid: { candidate in
                                    candidate.isValidGlobalShortcut
                                        && settings.actionsConflicting(with: candidate).isEmpty
                                }
                            )
                        }
                        if index < HotKeyAction.allCases.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(6)
            }

            if let conflictMessage {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Text("Each shortcut needs at least one modifier (⌘ ⌥ ⌃ ⇧), or use a function key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func title(for action: HotKeyAction) -> String {
        switch action {
        case .fullScreen: return "Full Screen"
        case .window: return "Window"
        case .area: return "Area"
        }
    }

    private func binding(for action: HotKeyAction) -> Binding<HotKeyDefinition> {
        Binding(
            get: { settings.hotKey(for: action) },
            set: { candidate in
                let conflicts = settings.actionsConflicting(with: candidate)
                guard conflicts.isEmpty else {
                    conflictMessage = "Can't use \(candidate.displayString) — already used by \(names(for: conflicts))."
                    return
                }
                conflictMessage = nil
                settings.setHotKey(candidate)
            }
        )
    }

    private func names(for actions: [HotKeyAction]) -> String {
        actions.map(title(for:)).joined(separator: ", ")
    }
}

// MARK: - Save Location

/// Shows and lets the user change `AppSettings.shared.saveDirectory`, plus
/// reveal it in Finder or reset it to the default. Changes apply immediately
/// (and are persisted by `AppSettings`) since every save reads `saveDirectory`
/// fresh.
private struct SaveLocationSectionView: View {
    @ObservedObject var settings: AppSettings

    private var isDefault: Bool {
        settings.saveDirectory.standardizedFileURL == AppConstants.defaultSaveDirectory.standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Save Location", subtitle: "Where new screenshots are written when you choose Save.")

            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.saveDirectory.lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                        Text(settings.saveDirectory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
            }

            HStack(spacing: 10) {
                Button("Choose…", action: chooseDirectory)
                Button("Reveal in Finder", action: revealInFinder)
                Spacer()
                Button("Reset to Default", action: resetToDefault)
                    .disabled(isDefault)
            }

            if isDefault {
                Text("Using the default folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Snaplet saves screenshots"
        panel.directoryURL = settings.saveDirectory

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        settings.saveDirectory = chosenURL
    }

    private func revealInFinder() {
        try? settings.ensureSaveDirectoryExists()
        NSWorkspace.shared.activateFileViewerSelecting([settings.saveDirectory])
    }

    private func resetToDefault() {
        settings.saveDirectory = AppConstants.defaultSaveDirectory
    }
}

// MARK: - General

/// "Launch at Login" toggle backed by `LoginItemManager`/`SMAppService`,
/// which applies immediately with no restart required.
private struct GeneralSectionView: View {
    @ObservedObject var loginItem: LoginItemManager
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "General", subtitle: "How Snaplet behaves on your Mac.")

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    Text("Start Snaplet automatically and keep it in the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { newValue in
                do {
                    try loginItem.setEnabled(newValue)
                    errorMessage = nil
                } catch {
                    errorMessage = "Couldn't update Launch at Login: \(error.localizedDescription)"
                }
            }
        )
    }
}
