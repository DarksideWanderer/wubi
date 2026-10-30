import Foundation

public enum CodeKey: Equatable {
    case letter(String)
    case backspace
    case reset
}

/// Platform-independent reducer for the uncommitted code. No input history is stored.
public struct PendingCode {
    public private(set) var code = ""
    private var previousText = ""
    private var freshLetter = false

    public init() {}

    public static func normalize(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...4).contains(code.utf8.count) && code.utf8.allSatisfy { (65...89).contains($0) || (97...121).contains($0) } ? code.uppercased() : ""
    }

    public mutating func consume(_ key: CodeKey) {
        switch key {
        case .letter(let letter):
            let normalized = Self.normalize(letter)
            guard normalized.count == 1 else { clear(); return }
            if code.count >= 4 { code = "" }
            code += normalized
            freshLetter = true
        case .backspace:
            if !code.isEmpty { code.removeLast() }
        case .reset:
            code = ""
            freshLetter = false
        }
    }

    public mutating func reconcile(context: String) -> String {
        var committed = context
        // Some editors expose Latin preedit letters as part of their AX value.
        if !code.isEmpty && committed.uppercased().hasSuffix(code) {
            committed = String(committed.dropLast(code.count))
        }
        if !previousText.isEmpty && committed != previousText && !freshLetter { code = "" }
        previousText = committed
        freshLetter = false
        return committed
    }

    public mutating func clear() { self = PendingCode() }
}
