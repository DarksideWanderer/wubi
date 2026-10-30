import Foundation

public enum CodeKey: Equatable {
    case letter(String)
    case backspace
    case deleteForward
    case moveLeft
    case moveRight
    case reset
}

/// Platform-independent reducer for the uncommitted code. No input history is stored.
public struct PendingCode {
    public private(set) var code = ""
    public private(set) var caret = 0
    private var previousText = ""
    private var hasContext = false
    private var previousWindowWasFull = false
    private var freshEdit = false
    // AX can lag behind the keyboard event tap. Keep bounded versions of the
    // current preedit until AX catches up, including versions before deletion.
    private var preeditVersions: [String] = []

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
            if code.count >= 4 { code = ""; caret = 0; preeditVersions.removeAll() }
            let position = code.index(code.startIndex, offsetBy: caret)
            code.insert(contentsOf: normalized, at: position)
            caret += 1
            rememberCurrentPreedit()
            freshEdit = true
        case .backspace:
            if caret > 0 {
                rememberCurrentPreedit()
                code.remove(at: code.index(code.startIndex, offsetBy: caret - 1))
                caret -= 1
                rememberCurrentPreedit()
                freshEdit = true
            }
        case .deleteForward:
            if caret < code.count {
                rememberCurrentPreedit()
                code.remove(at: code.index(code.startIndex, offsetBy: caret))
                rememberCurrentPreedit()
                freshEdit = true
            }
        case .moveLeft, .moveRight:
            if !code.isEmpty {
                rememberCurrentPreedit()
                caret = min(code.count, max(0, caret + (key == .moveLeft ? -1 : 1)))
                rememberCurrentPreedit()
                freshEdit = true
            } else {
                preeditVersions.removeAll()
                freshEdit = false
            }
        case .reset:
            code = ""
            caret = 0
            preeditVersions.removeAll()
            freshEdit = false
        }
    }

    public mutating func reconcile(context: String) -> String {
        var committed = context
        let windowIsFull = context.utf16.count == 80
        // Prefer a known preedit suffix that leaves the last committed context
        // unchanged. For YT -> Delete -> Y, an old AX value ending in "yt"
        // still represents the same composition, not newly committed text.
        let version = preeditVersions.sorted { $0.count > $1.count }.first {
            hasPreeditSuffix(context, $0) && sameCommittedContext(String(context.dropLast($0.count)), windowIsFull: windowIsFull)
        } ?? (!code.isEmpty && hasPreeditSuffix(context, code) ? code : nil)
        if let version = version {
            committed = String(context.dropLast(version.count))
        }
        if hasContext && !sameCommittedContext(committed, windowIsFull: windowIsFull) && !freshEdit {
            code = ""
            caret = 0
            preeditVersions.removeAll()
        } else if code.isEmpty && committed == context {
            preeditVersions.removeAll()
        }
        previousText = committed
        hasContext = true
        previousWindowWasFull = windowIsFull
        freshEdit = false
        return committed
    }

    private func sameCommittedContext(_ text: String, windowIsFull: Bool) -> Bool {
        if text == previousText { return true }
        // The reader keeps only 80 UTF-16 units before the caret. Preedit edits
        // can reveal/hide up to four units at the *start* of that window while
        // the committed suffix remains unchanged.
        guard windowIsFull || previousWindowWasFull,
              abs(text.utf16.count - previousText.utf16.count) <= 4 else { return false }
        return text.hasSuffix(previousText) || previousText.hasSuffix(text)
    }

    private mutating func rememberCurrentPreedit() {
        rememberPreedit(code)
        // AX reads text before the caret. When the IME exposes an in-code caret,
        // that can be only "y" for a complete pending code of "yt".
        rememberPreedit(String(code.prefix(caret)))
    }

    private mutating func rememberPreedit(_ value: String) {
        guard !value.isEmpty else { return }
        preeditVersions.removeAll { $0 == value }
        preeditVersions.append(value)
        if preeditVersions.count > 32 { preeditVersions.removeFirst() }
    }

    private func hasPreeditSuffix(_ context: String, _ value: String) -> Bool {
        let suffix = String(context.suffix(value.count))
        return suffix.utf8.allSatisfy { (65...89).contains($0) || (97...121).contains($0) }
            && suffix.uppercased() == value
    }

    public mutating func clear() { self = PendingCode() }
}
