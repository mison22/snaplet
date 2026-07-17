import AppKit
import Carbon
import SwiftUI

/// A clickable control that shows a hotkey's current binding and lets the
/// user rebind it by pressing a new key combination.
///
/// Preferences hosts three of these (one per `HotKeyAction`); conflict
/// detection across the three lives in Preferences, not here — this view
/// only reports whatever `isValid` says about the single candidate it just
/// captured.
struct HotKeyRecorder: View {
    @Binding var definition: HotKeyDefinition
    var isValid: (HotKeyDefinition) -> Bool = { _ in true }

    @State private var isRecording = false
    @State private var isRejected = false

    var body: some View {
        Button {
            isRecording = true
            isRejected = false
        } label: {
            Text(isRecording ? "Press a key combination…" : definition.displayString)
                .frame(minWidth: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .background(
            KeyCaptureView(
                isRecording: $isRecording,
                onCapture: { keyCode, modifiers in
                    let candidate = HotKeyDefinition(
                        action: definition.action,
                        keyCode: keyCode,
                        modifiers: modifiers
                    )
                    if isValid(candidate) {
                        definition = candidate
                        isRejected = false
                    } else {
                        isRejected = true
                    }
                    isRecording = false
                },
                onCancel: {
                    isRejected = false
                    isRecording = false
                }
            )
        )
    }

    private var backgroundColor: Color {
        if isRejected { return Color.red.opacity(0.2) }
        if isRecording { return Color.accentColor.opacity(0.2) }
        return Color.gray.opacity(0.15)
    }
}

/// `NSViewRepresentable` bridge that becomes first responder while
/// `isRecording` is true and reports the next `keyDown` as a Carbon key
/// code + modifier mask, since SwiftUI has no API to intercept an arbitrary
/// raw key combination.
///
/// Escape is treated specially: it cancels recording via `onCancel` rather
/// than being captured as a candidate binding, matching every other
/// shortcut-recording control in macOS (and this app's own capture-selection
/// overlays, which also use Escape to cancel).
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (_ keyCode: UInt32, _ modifiers: UInt32) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CapturingView {
        let view = CapturingView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: CapturingView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        if isRecording, nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class CapturingView: NSView {
        var onCapture: ((UInt32, UInt32) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard event.keyCode != UInt16(kVK_Escape) else {
                onCancel?()
                return
            }
            let carbonKeyCode = UInt32(event.keyCode)
            let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
            onCapture?(carbonKeyCode, carbonModifiers)
        }

        /// Translates AppKit's `NSEvent.ModifierFlags` to the Carbon modifier
        /// bit values `HotKeyManager`/`HotKeyDefinition` use throughout.
        private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
            var result: UInt32 = 0
            if flags.contains(.control) { result |= UInt32(controlKey) }
            if flags.contains(.option) { result |= UInt32(optionKey) }
            if flags.contains(.shift) { result |= UInt32(shiftKey) }
            if flags.contains(.command) { result |= UInt32(cmdKey) }
            return result
        }
    }
}
