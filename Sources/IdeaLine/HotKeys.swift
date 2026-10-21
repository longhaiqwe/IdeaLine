import AppKit
import Carbon

struct AppShortcut {
    let keyCode: Int
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let label: String

    static let newIdea = AppShortcut(keyCode: kVK_ANSI_N, key: "n", modifiers: [.control, .option], label: "⌃⌥N")
    static let toggleLine = AppShortcut(keyCode: kVK_ANSI_L, key: "l", modifiers: [.control, .option], label: "⌃⌥L")

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    func matches(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.control, .option, .command, .shift]) == modifiers
            && Int(event.keyCode) == keyCode
    }
}

// Carbon registration follows Tendedero's permission-free shortcut approach.
final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            if let action = owner.actions[id.id] {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: AppShortcut, id: UInt32, action: @escaping () -> Void) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, EventHotKeyID(signature: 0x49444C4E, id: id), GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref); actions[id] = action; return true
    }
    deinit { refs.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
}
