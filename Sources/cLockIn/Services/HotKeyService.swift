import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's hot keys need no Accessibility permission.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Registers the shortcut, replacing any previous one. `.off` just unregisters.
    func register(_ choice: HotKeyChoice, action: @escaping () -> Void) {
        unregister()
        self.action = action
        guard let (keyCode, modifiers) = Self.carbonKey(for: choice) else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x634C_6B49), id: 1) // "cLkI"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    fileprivate func fire() {
        action?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKeyService.shared.fire() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }

    private static func carbonKey(for choice: HotKeyChoice) -> (UInt32, UInt32)? {
        switch choice {
        case .controlOptionT: (UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey))
        case .commandOptionT: (UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .off: nil
        }
    }
}
