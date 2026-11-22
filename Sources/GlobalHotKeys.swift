import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts, registered through Carbon's hot key API, which needs no special permission.
@MainActor
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    struct Shortcut {
        let keyCode: Int                      // kVK_ANSI_B and so on
        let modifiers: Int                    // controlKey | optionKey and so on
        let action: () -> Void
    }

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    /// Replaces whatever was registered before.
    func register(_ shortcuts: [Shortcut]) {
        unregister()
        installHandlerIfNeeded()
        for (index, shortcut) in shortcuts.enumerated() {
            let id = EventHotKeyID(signature: 0x42534D4C, id: UInt32(index + 1))           // 'BSML'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id.id] = shortcut.action
            }
        }
    }

    func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        actions = [:]
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let number = id.id
    DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKeys.shared.fire(number) } }
    return noErr
}
