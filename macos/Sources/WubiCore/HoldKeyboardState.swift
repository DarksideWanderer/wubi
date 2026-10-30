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
