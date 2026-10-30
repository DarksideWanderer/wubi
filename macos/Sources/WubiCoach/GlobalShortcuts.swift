import Carbon
import Foundation
import WubiCore

/// System-registered shortcuts take precedence over a foreground app's local
/// key bindings, and do not depend on Accessibility or Input Monitoring access.
final class GlobalShortcuts {
    var onChange: ((UInt32, Bool) -> Void)?
    private static let signature: OSType = 0x57424348 // WBCH
    private static let definitions: [(id: UInt32, key: UInt32, label: String)] = [
        (1, UInt32(HoldKeyboardShortcut.keyCode), HoldKeyboardShortcut.label),
        (2, 13, "Control+Option+W"),
        (3, 17, "Control+Option+T")
    ]
    private var handler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var errors: [UInt32: OSStatus] = [:]
    private var handlerError: OSStatus = noErr

    var keyboardRegistered: Bool { registrations[1] != nil }
    var allRegistered: Bool { registrations.count == Self.definitions.count }
    var status: String {
        if handlerError != noErr { return "全局快捷键事件处理器安装失败（错误 \(handlerError)）" }
        let failures = Self.definitions.compactMap { definition -> String? in
            guard let error = errors[definition.id] else { return nil }
            let reason = error == OSStatus(eventHotKeyExistsErr) ? "已被其他程序注册" : "注册失败"
            return "\(definition.label) \(reason)（错误 \(error)）"
        }
        return failures.isEmpty ? "全局快捷键已就绪 · ⌃⌥K 字根键盘 · ⌃⌥W 暂停 · ⌃⌥T 置顶" : failures.joined(separator: "；")
    }

    func owns(keyCode: Int) -> Bool {
        Self.definitions.contains { Int($0.key) == keyCode && registrations[$0.id] != nil }
    }

    func start() {
        guard handler == nil else { return }
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let callback: EventHandlerUPP = { _, event, pointer in
            guard let event = event, let pointer = pointer else { return OSStatus(eventNotHandledErr) }
            let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(pointer).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == GlobalShortcuts.signature,
                  shortcuts.registrations[identifier.id] != nil else { return OSStatus(eventNotHandledErr) }
            shortcuts.onChange?(identifier.id, GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }
        handlerError = InstallEventHandler(GetApplicationEventTarget(), callback, types.count, types,
                                          Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerError == noErr else { return }
        for definition in Self.definitions {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(definition.key, UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: Self.signature, id: definition.id),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if result == noErr, let reference = reference {
                registrations[definition.id] = reference
            } else { errors[definition.id] = result }
        }
    }

    func stop() {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        registrations.removeAll(); errors.removeAll()
        if let handler = handler { RemoveEventHandler(handler) }
        handler = nil; handlerError = noErr
    }

    deinit { stop() }
}
