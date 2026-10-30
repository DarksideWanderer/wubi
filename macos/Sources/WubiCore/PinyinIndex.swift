import Foundation

public struct PinyinCharacter: Identifiable, Equatable {
    // Swift String equality folds CJK compatibility ideographs. Use the scalar
    // identity so those distinct dictionary entries remain visible and unique.
    public var id: UInt32 { character.unicodeScalars.first!.value }
    public let character: String
    public let readings: [String]
}

/// Exact, tone-insensitive single-syllable lookup; no phrases or result cap.
public final class PinyinIndex {
    private var buckets: [String: [PinyinCharacter]] = [:]
    public private(set) var characterCount = 0

    public init(url: URL, frequencies: [UInt32: Double], knownCharacters: Set<UInt32>) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, parts[0].unicodeScalars.count == 1 else { continue }
            let item = PinyinCharacter(character: String(parts[0]), readings: parts[1].split(separator: ",").map(String.init))
            characterCount += 1
            for reading in item.readings { buckets[reading, default: []].append(item) }
        }
        for syllable in Array(buckets.keys) {
            buckets[syllable]?.sort {
                let a = frequencies[$0.id, default: 0], b = frequencies[$1.id, default: 0]
                if a != b { return a > b }
                let ak = knownCharacters.contains($0.id), bk = knownCharacters.contains($1.id)
                if ak != bk { return ak }
                return $0.character.unicodeScalars.first!.value < $1.character.unicodeScalars.first!.value
            }
        }
    }

    public static func normalize(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, value.utf8.allSatisfy({ (97...122).contains($0) }) else { return "" }
        // Accept common keyboard spellings for üe, while keeping lu and lv distinct.
        return ["lue": "lve", "nue": "nve"][value] ?? value
    }

    public func search(_ query: String) -> [PinyinCharacter] {
        buckets[Self.normalize(query)] ?? []
    }
}
