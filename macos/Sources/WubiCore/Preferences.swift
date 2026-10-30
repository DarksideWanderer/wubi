import Foundation
import CSQLite

/// Aggregate counts only: at most three preceding Han characters, never a text log.
public final class PreferenceStore {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure(); sqlite3_close(database); database = nil; throw error
        }
        sqlite3_busy_timeout(database, 80)
        do {
            try execute("CREATE TABLE IF NOT EXISTS preferences (context TEXT NOT NULL, character TEXT NOT NULL, count INTEGER NOT NULL CHECK(count > 0), PRIMARY KEY(context, character)) WITHOUT ROWID")
        } catch { sqlite3_close(database); database = nil; throw error }
    }

    deinit { sqlite3_close(database) }

    private func failure() -> NSError {
        NSError(domain: "WubiPreferences", code: Int(sqlite3_errcode(database)),
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }

    private func statement(_ sql: String, _ arguments: [String]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            sqlite3_finalize(stmt); throw failure()
        }
        for (index, value) in arguments.enumerated() {
            if sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient) != SQLITE_OK {
                sqlite3_finalize(stmt); throw failure()
            }
        }
        return stmt
    }

    private func execute(_ sql: String, _ arguments: [String] = []) throws {
        let stmt = try statement(sql, arguments); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }

    public static func contexts(_ text: String) -> [String] {
        // Stop at punctuation, Latin text or line breaks rather than retaining them.
        let han = text.reversed().prefix { character in
            character.unicodeScalars.count == 1 && character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
        }.prefix(3).reversed().map(String.init)
        return [""] + (han.isEmpty ? [] : (1...han.count).map { han.suffix($0).joined() })
    }

    public func record(context: String, character: String, weight: Int = 1) throws {
        guard weight > 0, weight <= 8, character.unicodeScalars.count == 1,
              character.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) }) else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for suffix in Self.contexts(context) {
                try execute("UPDATE preferences SET count = MIN(count + \(weight), 1000000000) WHERE context=? AND character=?", [suffix, character])
                if sqlite3_changes(database) == 0 {
                    try execute("INSERT INTO preferences(context,character,count) VALUES(?,?,\(weight))", [suffix, character])
                }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    public func scores(context: String) throws -> [String: Double] {
        var scores: [String: Double] = [:]
        for (length, suffix) in Self.contexts(context).enumerated() {
            let stmt = try statement("SELECT character,count FROM preferences WHERE context=?", [suffix])
            defer { sqlite3_finalize(stmt) }
            var bucket: [(String, Double)] = []
            var result = sqlite3_step(stmt)
            while result == SQLITE_ROW {
                bucket.append((String(cString: sqlite3_column_text(stmt, 0)), Double(sqlite3_column_int64(stmt, 1))))
                result = sqlite3_step(stmt)
            }
            guard result == SQLITE_DONE else { throw failure() }
            let sum = bucket.reduce(0) { $0 + $1.1 }
            for (character, count) in bucket { scores[character, default: 0] += pow(12, Double(length)) * count / sum }
        }
        return scores
    }
}

public struct PredictionColumns {
    public let preferred: [WubiCandidate]
    public let regular: [WubiCandidate]
    public var all: [WubiCandidate] { preferred + regular }
}

public final class PersonalizedPredictor {
    private let engine: LearningEngine
    private let store: PreferenceStore?
    public private(set) var notice = ""

    public init(engine: LearningEngine, databaseURL: URL) {
        self.engine = engine
        do { store = try PreferenceStore(url: databaseURL) }
        catch { store = nil; notice = "偏好数据库不可用，使用常规联想：\(error.localizedDescription)" }
    }

    public func record(context: String, character: String, explicit: Bool = false) {
        guard engine.lookup(character: character) != nil, let store = store else { return }
        do { try store.record(context: context, character: character, weight: explicit ? 4 : 1); notice = "" }
        catch { notice = "偏好未保存：\(error.localizedDescription)" }
    }

    public func predict(context: String, codePrefix: String = "") -> PredictionColumns {
        let baseline = engine.predict(context: context, codePrefix: codePrefix)
        let prefix = PendingCode.normalize(codePrefix)
        var scores: [String: Double] = [:]
        if let store = store {
            do { scores = try store.scores(context: context) }
            catch { notice = "偏好读取失败，使用常规联想：\(error.localizedDescription)" }
        }
        var preferred = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.compactMap { character, _ -> WubiCandidate? in
            guard let info = engine.lookup(character: character), prefix.isEmpty || info.code.hasPrefix(prefix) || info.shortCode.split(separator: " ").contains(where: { $0.hasPrefix(prefix) }) else { return nil }
            return WubiCandidate(info: info, reason: "个人偏好")
        }
        preferred = Array(preferred.prefix(9))
        var seen = Set(preferred.map(\.id))
        for candidate in baseline where preferred.count < 9 && seen.insert(candidate.id).inserted { preferred.append(candidate) }
        return PredictionColumns(preferred: preferred, regular: Array(baseline.filter { !seen.contains($0.id) }.prefix(9)))
    }
}

/// Learn only a short append following an observed IME composition in the same field.
/// Focus changes, navigation, deletions, long pastes and initial reads are baselines.
public struct CommittedInputTracker {
    private var previous = "", code = "", focus = ""
    public init() {}
    public mutating func clear() { self = CommittedInputTracker() }
    public mutating func observe(context: String, code: String, focus: String) -> [(context: String, character: String)] {
        defer { previous = context; self.code = code; self.focus = focus }
        guard !focus.isEmpty, focus == self.focus, !self.code.isEmpty else { return [] }
        let old = Array(previous), new = Array(context)
        var overlap = old.count
        if !context.hasPrefix(previous) {
            guard previous.utf16.count == 80, context.utf16.count == 80 else { return [] }
            while overlap >= max(1, old.count - 4) && Array(old.suffix(overlap)) != Array(new.prefix(overlap)) { overlap -= 1 }
        }
        let count = new.count - overlap
        guard overlap >= max(0, old.count - 4), (1...4).contains(count), Array(old.suffix(overlap)) == Array(new.prefix(overlap)) else { return [] }
        return (overlap..<new.count).map { (String(new.prefix($0)), String(new[$0])) }
    }
}
