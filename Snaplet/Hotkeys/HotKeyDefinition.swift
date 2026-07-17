import Carbon

/// Identifies which capture action a global hotkey triggers.
enum HotKeyAction: String, Codable, CaseIterable {
    case fullScreen
    case window
    case area
}

/// A single global hotkey binding: an action plus the Carbon key code and
/// modifier flags that trigger it.
///
/// `Codable` so `Preferences` can persist user rebinds to `UserDefaults`
/// (see `AppConstants.DefaultsKey`); `Equatable` so `Preferences` can detect
/// conflicting bindings before handing them to `HotKeyManager`.
struct HotKeyDefinition: Codable, Equatable {
    let action: HotKeyAction
    var keyCode: UInt32
    var modifiers: UInt32

    init(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Builds a definition from one of `AppConstants`'s raw defaults.
    init(action: HotKeyAction, default hotKeyDefault: AppConstants.HotKeyDefault) {
        self.action = action
        self.keyCode = hotKeyDefault.keyCode
        self.modifiers = hotKeyDefault.modifiers
    }

    /// The three built-in defaults, sourced from `AppConstants` so there is
    /// exactly one place raw key codes/modifiers are declared.
    static var defaults: [HotKeyDefinition] {
        [
            HotKeyDefinition(action: .fullScreen, default: AppConstants.fullScreenHotKeyDefault),
            HotKeyDefinition(action: .window, default: AppConstants.windowHotKeyDefault),
            HotKeyDefinition(action: .area, default: AppConstants.areaHotKeyDefault),
        ]
    }

    /// Whether this binding is safe to register as a global hotkey.
    ///
    /// A bare key with no modifier (e.g. plain "S") would be consumed
    /// system-wide by Carbon, making that key unusable for normal typing.
    /// So a modifier is required — except for the function keys (F1–F12),
    /// which are conventionally bound modifier-free.
    var isValidGlobalShortcut: Bool {
        modifiers != 0 || HotKeyDefinition.functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
    ]

    /// Human-readable rendering for display in Preferences, e.g. "⌥⇧S".
    var displayString: String {
        modifierSymbols + keySymbol
    }

    private var modifierSymbols: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    /// `keyCodeSymbols` covers the keys a rebind is realistically expected to
    /// use; `KeyCaptureView` (see `HotKeyRecorder.swift`) will accept and
    /// store any key the user presses, so anything not in the table falls
    /// back to a numeric label rather than an unhelpful "?".
    private var keySymbol: String {
        HotKeyDefinition.keyCodeSymbols[keyCode] ?? "Key \(keyCode)"
    }

    /// Carbon virtual key codes mapped to their on-screen symbol. Covers
    /// letters, numbers, and the non-letter keys a screenshot app's
    /// rebindable hotkeys are realistically bound to (arrows, function keys,
    /// navigation keys); not an exhaustive keyboard map — see `keySymbol`'s
    /// fallback for anything still missing.
    private static let keyCodeSymbols: [UInt32: String] = {
        var map: [UInt32: String] = [:]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        for (code, symbol) in letters {
            map[UInt32(code)] = symbol
        }

        let functionKeys: [(Int, String)] = [
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"),
            (kVK_F5, "F5"), (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"),
            (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]
        for (code, symbol) in functionKeys {
            map[UInt32(code)] = symbol
        }

        map[UInt32(kVK_Space)] = "Space"
        map[UInt32(kVK_Return)] = "⏎"
        map[UInt32(kVK_Escape)] = "⎋"
        map[UInt32(kVK_Tab)] = "⇥"
        map[UInt32(kVK_Delete)] = "⌫"
        map[UInt32(kVK_ForwardDelete)] = "⌦"
        map[UInt32(kVK_LeftArrow)] = "←"
        map[UInt32(kVK_RightArrow)] = "→"
        map[UInt32(kVK_UpArrow)] = "↑"
        map[UInt32(kVK_DownArrow)] = "↓"
        map[UInt32(kVK_Home)] = "↖"
        map[UInt32(kVK_End)] = "↘"
        map[UInt32(kVK_PageUp)] = "⇞"
        map[UInt32(kVK_PageDown)] = "⇟"
        return map
    }()
}
