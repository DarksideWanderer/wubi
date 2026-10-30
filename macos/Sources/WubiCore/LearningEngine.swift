import Foundation

public struct WubiCharacter: Identifiable, Equatable {
    public var id: String { character }
    public let character: String
    public let code: String
    public let shortCode: String
    public let units: String
    public let keyUnit: Bool
    public let strokeUnit: Bool
    public let charUnit: Bool
    public let identification: String

    public var explanation: String {
        if keyUnit { return "键名字：连打四次所在键" }
        if strokeUnit { return "单笔画：所在键两次 + LL" }
        if charUnit { return "成字字根：报户口 + 首笔 + 次笔 + 末笔（不足则省略）" }
        if !identification.isEmpty { return "末位识别码：\(identification)（不是额外字根）" }
        return "按字根顺序取码；超过四根取首、次、三、末"
    }
}

public struct WubiCandidate: Identifiable, Equatable {
    public var id: String { info.id }
    public let info: WubiCharacter
    public let reason: String

    public init(info: WubiCharacter, reason: String) {
        self.info = info
        self.reason = reason
    }
}

/// Uses the same TSV/YAML files and scoring rules as the Windows implementation.
public final class LearningEngine {
    public private(set) var characters: [String: WubiCharacter] = [:]
    public private(set) var phraseCount = 0
    public private(set) var keyboardRoots: [String: String] = [:]
    private var transitions: [String: [String: Double]] = [:]
    private var frequencies: [String: Double] = [:]

    public init(dataDirectory: URL) throws {
        let lines = try Self.lines(dataDirectory.appendingPathComponent("decomposition.tsv"))
        for line in lines.dropFirst() {
            let p = line.components(separatedBy: "\t")
            guard p.count >= 9, p[0].utf16.count == 1,
                  Self.validCode(p[1]) else { continue }
            let units = p[7].replacingOccurrences(of: "[〖〗※]", with: "", options: .regularExpression)
            characters[p[0]] = WubiCharacter(
                character: p[0], code: p[1].uppercased(),
                shortCode: p[2].replacingOccurrences(of: "/", with: " ").uppercased(),
                units: units, keyUnit: p[4] == "1", strokeUnit: p[5] == "1",
                charUnit: p[6] == "1",
                identification: p[8].replacingOccurrences(of: "〔.*?〕", with: "", options: .regularExpression)
            )
        }
        var seen = Set<String>()
        for line in try Self.lines(dataDirectory.appendingPathComponent("wubi86.dict.yaml")) {
            if line.hasPrefix("#") { continue }
            let p = line.components(separatedBy: "\t")
            guard p.count >= 2, Self.validCode(p[1]), seen.insert(p[0]).inserted else { continue }
            let word = p[0]
            guard word.allSatisfy({ characters[String($0)] != nil }) else { continue }
            let value = p.count > 2 ? Double(p[2].replacingOccurrences(of: "%", with: "")) ?? 0 : 0
            let weight = 1 + sqrt(max(0, value)) / 100
            if word.count == 1 { frequencies[word, default: 0] += weight }
            else { train(word, weight: weight); phraseCount += 1 }
        }
        let corpus = try String(contentsOf: dataDirectory.appendingPathComponent("corpus.txt"), encoding: .utf8)
        let expression = try NSRegularExpression(pattern: "[\u{4e00}-\u{9fff}]+")
        for match in expression.matches(in: corpus, range: NSRange(corpus.startIndex..., in: corpus)) {
            if let range = Range(match.range, in: corpus) { train(String(corpus[range]), weight: 12) }
        }
        let common = "的了是在我有和你不这人们中大为上个国到说时要就出会可也对生能而子那得于着下自之年过发后作里用道行所然家种事成多天好学谢见气欢想今明去吃饭工作生活"
        for (index, ch) in common.enumerated() { frequencies[String(ch), default: 0] += Double(100 - index) }
        for line in try Self.lines(dataDirectory.appendingPathComponent("keyboard.tsv")) {
            let p = line.components(separatedBy: "\t")
            guard p.count >= 4, let key = p[0].first, ("A"..."Y").contains(String(key)) else { continue }
            var seenRoots = Set<Unicode.Scalar>()
            let roots = p[1...3].joined().unicodeScalars.filter {
                (0xE000...0xF8FF).contains($0.value) && seenRoots.insert($0).inserted
            }
            keyboardRoots[String(key)] = String(String.UnicodeScalarView(roots))
        }
    }

    private static func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
    }

    private static func validCode(_ code: String) -> Bool {
        (1...4).contains(code.utf8.count) && code.utf8.allSatisfy { (97...121).contains($0) }
    }

    private func train(_ text: String, weight: Double) {
        let letters = text.map(String.init)
        guard letters.count > 1 else { return }
        for index in 1..<letters.count {
            guard characters[letters[index]] != nil else { continue }
            for length in 1...min(6, index) {
                let prefix = letters[(index - length)..<index].joined()
                transitions[prefix, default: [:]][letters[index], default: 0] += weight
            }
        }
    }

    public func predict(context: String, codePrefix: String = "") -> [WubiCandidate] {
        let prefix = PendingCode.normalize(codePrefix)
        let letters = Array(context)
        var scores: [String: Double] = [:]
        var reasons: [String: String] = [:]
        if !letters.isEmpty {
            for length in stride(from: min(6, letters.count), through: 1, by: -1) {
                let suffix = String(letters.suffix(length))
                guard let bucket = transitions[suffix] else { continue }
                let sum = bucket.values.reduce(0, +)
                for (character, weight) in bucket {
                    scores[character, default: 0] += pow(12, Double(length)) * weight / sum
                    if reasons[character] == nil { reasons[character] = "续接「\(suffix)」" }
                }
            }
        }
        for (character, weight) in frequencies where characters[character] != nil {
            scores[character, default: 0] += weight * 0.00001
        }
        if !prefix.isEmpty {
            for info in characters.values where info.code.hasPrefix(prefix) && scores[info.character] == nil {
                scores[info.character] = 0
            }
        }
        return scores.filter { character, _ in
            guard let info = characters[character] else { return false }
            return prefix.isEmpty || info.code.hasPrefix(prefix) || info.shortCode.split(separator: " ").contains { $0.hasPrefix(prefix) }
        }.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }.prefix(5).compactMap { character, _ in
            guard let info = characters[character] else { return nil }
            return WubiCandidate(info: info, reason: (reasons[character] ?? "常用字补足") + (prefix.isEmpty ? "" : " · \(prefix)"))
        }
    }
}
