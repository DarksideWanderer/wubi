import AppKit
import CoreGraphics
import ApplicationServices
import WubiCore

/// Passes typing through unchanged; only the companion's F8 shortcut is consumed.
final class KeyMonitor {
    var onKey: ((CodeKey, pid_t) -> Void)?
    var onShortcut: ((String) -> Void)?
    var onKeyboardVisibility: ((Bool) -> Void)?
    private var keyboard = HoldKeyboardState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var installed: Bool { tap != nil }

    func start() {
        guard tap == nil, AXIsProcessTrusted(), CGPreflightListenEventAccess() else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyMonitor>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if monitor.keyboard.handle(isDown: false) { monitor.onKeyboardVisibility?(false) }
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown || type == .keyUp, monitor.handle(event, type: type) { return nil }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                options: .defaultTap, eventsOfInterest: mask, callback: callback,
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
        if keyboard.handle(isDown: false) { onKeyboardVisibility?(false) }
    }

    private func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if key == 100 { // kVK_F8. Consume only this application-owned shortcut.
            let visible = type == .keyDown
            if keyboard.handle(isDown: visible) { onKeyboardVisibility?(visible) }
            return true
        }
        guard type == .keyDown else { return false }
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if flags == [.maskControl, .maskAlternate], let letter = Self.letters[key], letter == "W" || letter == "T" {
            onShortcut?(letter); return false
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        if !flags.isEmpty { onKey?(.reset, pid); return false }
        if let letter = Self.letters[key], letter != "Z" { onKey?(.letter(letter), pid) }
        else if key == 51 { onKey?(.backspace, pid) }
        else { onKey?(.reset, pid) }
        return false
    }

    // Physical QWERTY positions; IME-converted Unicode is intentionally not used here.
    private static let letters: [Int: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
        12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I", 35:"P",
        37:"L", 38:"J", 40:"K", 45:"N", 46:"M"
    ]
    deinit { stop() }
}
