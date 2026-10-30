/// Key repeat must not turn a hold gesture into a toggle.
public struct HoldKeyboardState {
    public private(set) var visible = false
    public init() {}
    @discardableResult public mutating func handle(isDown: Bool) -> Bool {
        guard visible != isDown else { return false }
        visible = isDown
        return true
    }
}

/// Captures a complete shortcut press, including repeats and key-up after a
/// modifier is released. A key already held before the chord must not activate it.
public struct HoldKeyboardShortcut {
    public static let keyCode = 40 // Physical K key.
    public static let label = "Control+Option+K"
    public private(set) var visible = false
    private var captured = false
    public var isPressed: Bool { captured }

    public init() {}

    @discardableResult
    public mutating func handle(keyCode: Int, isDown: Bool,
                                requiredModifiers: Bool, isRepeat: Bool = false) -> Bool {
        guard keyCode == Self.keyCode else { return false }
        if captured {
            if !isDown { reset() }
            return true
        }
        guard isDown, requiredModifiers, !isRepeat else { return false }
        captured = true
        visible = true
        return true
    }

    public mutating func modifiersChanged(requiredModifiers: Bool) {
        if !requiredModifiers { visible = false }
    }

    public mutating func reset() {
        captured = false
        visible = false
    }
}
