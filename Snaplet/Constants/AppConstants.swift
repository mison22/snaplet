import AppKit
import Carbon

/// Central namespace for shared, hard-coded values used across Snaplet.
///
/// This is a pure namespace (no cases, never instantiated) so that every
/// default, key, and format string in the app has exactly one source of
/// truth. Other modules (Hotkeys, Preferences, Capture, Annotation) read
/// from here rather than re-declaring their own literals.
enum AppConstants {

    // MARK: - Hotkey defaults

    /// Raw default values for a single global hotkey registration.
    ///
    /// This intentionally holds only the primitive values Carbon's
    /// `RegisterEventHotKey` needs. It is NOT the app's hotkey model type —
    /// `Hotkeys/HotKeyDefinition.swift` owns that richer type (e.g. adding
    /// persistence/decoding). Keeping this to raw values avoids a naming
    /// collision between the two files.
    struct HotKeyDefault {
        /// Stable identifier used to persist/look up this binding, independent
        /// of its current key/modifier values (which the user may rebind).
        let id: String
        /// Carbon virtual key code (e.g. `kVK_ANSI_S`).
        let keyCode: UInt32
        /// Carbon event modifier flags (e.g. `optionKey | shiftKey`).
        let modifiers: UInt32
    }

    /// Default binding for capturing the full screen: Option+Shift+S.
    static let fullScreenHotKeyDefault = HotKeyDefault(
        id: "fullScreen",
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(optionKey | shiftKey)
    )

    /// Default binding for capturing a single window: Option+Shift+W.
    static let windowHotKeyDefault = HotKeyDefault(
        id: "window",
        keyCode: UInt32(kVK_ANSI_W),
        modifiers: UInt32(optionKey | shiftKey)
    )

    /// Default binding for capturing a user-selected area: Option+Shift+A.
    static let areaHotKeyDefault = HotKeyDefault(
        id: "area",
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(optionKey | shiftKey)
    )

    // MARK: - Annotation

    /// Preset color swatches offered in the annotation color picker.
    static let annotationPalette: [NSColor] = [
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .systemPurple,
        .white,
        .black,
    ]

    /// Preset arrow thicknesses, in the screenshot's native pixels. Captures
    /// are Retina (often 3000px+ wide), so these are deliberately large -- a
    /// single-digit width reads as a hairline once the shot is viewed at full
    /// resolution.
    static let annotationLineWidths: [CGFloat] = [6, 14, 26, 42]

    /// Preset text/bubble font sizes offered in the editor, in native pixels.
    static let annotationFontSizes: [CGFloat] = [16, 24, 36, 48, 64, 96]

    /// Curated font families offered for text and bubbles. The system font is
    /// offered separately (a `nil` family), so it isn't listed here. Each name
    /// is a macOS family name resolvable via `NSFontManager`.
    static let annotationFontNames: [String] = [
        "Helvetica Neue",
        "Avenir Next",
        "Georgia",
        "Times New Roman",
        "Menlo",
        "Marker Felt",
        "Snell Roundhand",
    ]

    // MARK: - Save location

    /// Default folder screenshots are written to: `~/Pictures/Screenshots`.
    ///
    /// Computed (rather than stored) so it always reflects the current
    /// user's home directory.
    static var defaultSaveDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    // MARK: - Filenames

    /// `DateFormatter.dateFormat` used to build screenshot filenames, e.g.
    /// "Snaplet 2026-07-15 at 14.30.00".
    static let filenameDateFormat = "'Snaplet' yyyy-MM-dd 'at' HH.mm.ss"

    /// Extension (without the leading dot) applied to saved screenshots.
    static let imageFileExtension = "png"

    // MARK: - UserDefaults keys

    /// Namespaced `UserDefaults` keys for persisted settings.
    ///
    /// All keys are prefixed with the app's reverse-DNS identifier to avoid
    /// collisions with other defaults (e.g. framework or system keys).
    enum DefaultsKey: String {
        /// Plain path string for the user-chosen save directory. Snaplet is
        /// not sandboxed, so a plain path (rather than a security-scoped
        /// bookmark) is sufficient — see the note on `AppSettings.saveDirectory`.
        case saveDirectoryPath = "com.mikeison.Snaplet.saveDirectoryPath"

        /// `CaptureResolution.rawValue` (Int) for the supersample multiplier
        /// applied on top of the display's native `backingScaleFactor`.
        case captureResolution = "com.mikeison.Snaplet.captureResolution"
    }
}
