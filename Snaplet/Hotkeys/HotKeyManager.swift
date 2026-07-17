import Carbon
import Foundation

/// Errors raised while registering global hotkeys with Carbon.
enum HotKeyError: Error {
    /// `RegisterEventHotKey` returned a non-`noErr` status for this action.
    case registrationFailed(action: HotKeyAction, status: OSStatus)
    /// The shared Carbon event handler could not be installed.
    case eventHandlerInstallFailed(status: OSStatus)
}

/// Registers and dispatches global hotkeys via the Carbon Event Manager.
///
/// Carbon's `RegisterEventHotKey` is used instead of
/// `NSEvent.addGlobalMonitorForEvents` because Carbon hotkeys are
/// exclusively consumed by the registering app: the keystroke never reaches
/// whatever app is focused, and no other listener can also react to it.
/// `NSEvent` global monitors only *observe* events after the system has
/// already routed them elsewhere, which would let a capture shortcut leak
/// through to the focused app (e.g. inserting the letter into a text
/// field) — unacceptable for a screenshot hotkey.
final class HotKeyManager {

    /// Invoked on the main thread whenever a registered hotkey fires.
    var onHotKey: ((HotKeyAction) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: HotKeyAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 1

    /// Four-character code identifying this app's hotkeys to Carbon.
    private static let signature: OSType = {
        var result: OSType = 0
        for scalar in "SNPL".unicodeScalars {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }()

    init() {}

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Registers all given definitions, replacing any previously registered
    /// bindings. Throws on the first registration failure; anything
    /// registered earlier in this call is rolled back before throwing.
    func register(_ definitions: [HotKeyDefinition]) throws {
        unregisterAll()
        try installEventHandlerIfNeeded()

        for definition in definitions {
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextHotKeyID)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                definition.keyCode,
                definition.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            guard status == noErr, let registeredRef = hotKeyRef else {
                unregisterAll()
                throw HotKeyError.registrationFailed(action: definition.action, status: status)
            }
            hotKeyRefs.append(registeredRef)
            actionsByID[nextHotKeyID] = definition.action
            nextHotKeyID += 1
        }
    }

    /// Unregisters every currently-registered hotkey. Safe to call when
    /// nothing is registered.
    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionsByID.removeAll()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKeyID(hotKeyID)
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard status == noErr, let installedRef = handlerRef else {
            throw HotKeyError.eventHandlerInstallFailed(status: status)
        }
        eventHandlerRef = installedRef
    }

    private func handleHotKeyID(_ hotKeyID: EventHotKeyID) {
        guard let action = actionsByID[hotKeyID.id] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onHotKey?(action)
        }
    }
}
