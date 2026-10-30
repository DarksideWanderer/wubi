import AppKit
import CoreGraphics
import ApplicationServices
import WubiCore

/// Global shortcuts are reserved by the system. The event tap only observes typing.
final class KeyMonitor {
    var onKey: ((CodeKey, pid_t) -> Void)?
    var onShortcut: ((String) -> Void)?
    var onKeyboardVisibility: ((Bool) -> Void)?
    private var keyboard = HoldKeyboardShortcut()
    private let shortcuts = GlobalShortcuts()
    private var pressedActions = Set<UInt32>()
    private var modifierTimer: Timer?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var installed: Bool { tap != nil }
    var shortcutsReady: Bool { shortcuts.allRegistered }
    var shortcutStatus: String { shortcuts.status }

    func start() {
        shortcuts.onChange = { [weak self] identifier, isDown in
            self?.handleShortcut(identifier, isDown: isDown)
        }
        shortcuts.start()
        guard tap == nil, CGPreflightListenEventAccess() else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyMonitor>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown || type == .keyUp || type == .flagsChanged {
                monitor.observe(event, type: type)
            }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .listenOnly, eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap = tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
        shortcuts.stop(); pressedActions.removeAll()
        resetKeyboard()
    }

    func retryShortcuts() {
        shortcuts.stop(); pressedActions.removeAll(); resetKeyboard()
        start()
    }

    private func handleShortcut(_ identifier: UInt32, isDown: Bool) {
        if identifier == 1 {
            let wasVisible = keyboard.visible
            keyboard.handle(keyCode: HoldKeyboardShortcut.keyCode, isDown: isDown, requiredModifiers: true)
            if wasVisible != keyboard.visible { onKeyboardVisibility?(keyboard.visible) }
            if isDown, modifierTimer == nil {
                // Modifier state is available without reading keystrokes. This
                // also handles releasing Control/Option when no event tap is allowed.
                let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
                    self?.checkModifiers(CGEventSource.flagsState(.combinedSessionState))
                }
                modifierTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            } else if !isDown { modifierTimer?.invalidate(); modifierTimer = nil }
            return
        }
        if !isDown { pressedActions.remove(identifier); return }
        guard pressedActions.insert(identifier).inserted else { return }
        onShortcut?(identifier == 2 ? "W" : "T")
    }

    private func resetKeyboard() {
        modifierTimer?.invalidate(); modifierTimer = nil
        let wasVisible = keyboard.visible
        keyboard.reset()
        if wasVisible { onKeyboardVisibility?(false) }
    }

    private func checkModifiers(_ flags: CGEventFlags) {
        let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let wasVisible = keyboard.visible
        keyboard.modifiersChanged(requiredModifiers: modifiers == [.maskControl, .maskAlternate])
        if wasVisible != keyboard.visible { onKeyboardVisibility?(keyboard.visible) }
    }

    private func observe(_ event: CGEvent, type: CGEventType) {
        if type == .flagsChanged {
            checkModifiers(event.flags)
            return
        }
        guard type == .keyDown else { return }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if shortcuts.owns(keyCode: key), modifiers == [.maskControl, .maskAlternate] { return }
        if key == HoldKeyboardShortcut.keyCode, keyboard.isPressed { return }
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        if !flags.isEmpty { onKey?(.reset, pid); return }
        if let letter = Self.letters[key], letter != "Z" { onKey?(.letter(letter), pid) }
        else if key == 51 { onKey?(.backspace, pid) }
        else { onKey?(.reset, pid) }
    }

    // Physical QWERTY positions; IME-converted Unicode is intentionally not used here.
    private static let letters: [Int: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
        12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I", 35:"P",
        37:"L", 38:"J", 40:"K", 45:"N", 46:"M"
    ]
    deinit { stop() }
}
