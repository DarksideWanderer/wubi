import Foundation
import CryptoKit
import XCTest
@testable import WubiCore

final class CoreTests: XCTestCase {
    func testPreferenceStorePersistenceCountsAndMinimalContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.sqlite3")
        do {
            let store = try PreferenceStore(url: url)
            try store.record(context: "不保存这整段输入你好", character: "猫")
            try store.record(context: "你好", character: "猫")
            try store.record(context: "你好", character: "吗")
            XCTAssertEqual(try store.scores(context: "")["猫"], 2.0 / 3.0)
            XCTAssertEqual(PreferenceStore.contexts("private@example.com，输入你好"), ["", "好", "你好", "入你好"])
            XCTAssertEqual(PreferenceStore.contexts("中文abc"), [""])
        }
        let reopened = try PreferenceStore(url: url)
        XCTAssertGreaterThan(try reopened.scores(context: "你好")["猫"]!, try reopened.scores(context: "你好")["吗"]!)
    }

    func testPersonalizedColumnsFallbackLearningDedupAndCodeFilter() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let predictor = PersonalizedPredictor(engine: Self.engine, databaseURL: directory.appendingPathComponent("preferences.sqlite3"))
        let baseline = Self.engine.predict(context: "直")
        let cold = predictor.predict(context: "直")
        XCTAssertEqual(cold.preferred, Array(baseline.prefix(9)))
        XCTAssertEqual(cold.regular, Array(baseline.dropFirst(9)))
        predictor.record(context: "直", character: "猫", explicit: true)
        predictor.record(context: "你好", character: "吗", explicit: true)
        for (context, prefix) in [("直", ""), ("你好", ""), ("直", "R"), ("直", "YYYY"), ("直", "VVVV"), ("直", "Q")] {
            let columns = predictor.predict(context: context, codePrefix: prefix)
            XCTAssertTrue(columns.preferred.count <= 9 && columns.regular.count <= 9)
            XCTAssertEqual(Set(columns.all.map(\.id)).count, columns.all.count)
            let left = Set(columns.preferred.map(\.id))
            XCTAssertEqual(columns.regular, Array(Self.engine.predict(context: context, codePrefix: prefix).filter { !left.contains($0.id) }.prefix(9)))
            XCTAssertTrue(columns.all.allSatisfy { prefix.isEmpty || $0.info.code.hasPrefix(prefix) || $0.info.shortCode.split(separator: " ").contains { $0.hasPrefix(prefix) } })
        }
        XCTAssertEqual(predictor.predict(context: "直").preferred.first?.id, "猫")
        XCTAssertEqual(predictor.predict(context: "你好").preferred.first?.id, "吗")
        XCTAssertTrue(predictor.notice.isEmpty)
    }

    func testPreferenceFailureFallsBackWithoutReplacingBrokenFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = Data("broken database".utf8)
        try contents.write(to: url)
        let predictor = PersonalizedPredictor(engine: Self.engine, databaseURL: url)
        XCTAssertFalse(predictor.notice.isEmpty)
        XCTAssertEqual(predictor.predict(context: "直").all, Self.engine.predict(context: "直"))
        predictor.record(context: "直", character: "猫")
        XCTAssertEqual(try Data(contentsOf: url), contents)
    }

    func testCommittedLearningRequiresCompositionSameFocusAndShortAppend() {
        var tracker = CommittedInputTracker()
        XCTAssertTrue(tracker.observe(context: "你好", code: "", focus: "A").isEmpty)
        XCTAssertTrue(tracker.observe(context: "你好", code: "Q", focus: "A").isEmpty)
        let committed = tracker.observe(context: "你好猫", code: "", focus: "A")
        XCTAssertEqual(committed.map { $0.context }, ["你好"])
        XCTAssertEqual(committed.map { $0.character }, ["猫"])
        XCTAssertTrue(tracker.observe(context: "你好猫", code: "", focus: "A").isEmpty)
        XCTAssertTrue(tracker.observe(context: "你好猫咪", code: "Q", focus: "B").isEmpty)
        XCTAssertTrue(tracker.observe(context: "你好猫", code: "Q", focus: "B").isEmpty)
        XCTAssertTrue(tracker.observe(context: "你好", code: "", focus: "B").isEmpty)
        _ = tracker.observe(context: "你好", code: "Q", focus: "B")
        tracker.clear()
        XCTAssertTrue(tracker.observe(context: "你好猫", code: "", focus: "B").isEmpty)
        _ = tracker.observe(context: "你", code: "Q", focus: "A")
        XCTAssertTrue(tracker.observe(context: "你好很长的一段粘贴文本", code: "", focus: "A").isEmpty)
        let old = String(repeating: "你", count: 79) + "好"
        _ = tracker.observe(context: old, code: "Q", focus: "C")
        XCTAssertEqual(tracker.observe(context: String(old.dropFirst()) + "猫", code: "", focus: "C").map { $0.character }, ["猫"])
    }
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let engine = try! LearningEngine(dataDirectory: root.appendingPathComponent("data"))

    func testSharedWindowsPredictionFixtures() throws {
        struct Fixture: Decodable { let context: String; let prefix: String; let characters: [String] }
        let data = try Data(contentsOf: Self.root.appendingPathComponent("tests/fixtures/predictions.json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
        for fixture in fixtures {
            XCTAssertEqual(Array(Self.engine.predict(context: fixture.context, codePrefix: fixture.prefix).prefix(5)).map { $0.info.character },
                           fixture.characters, "\(fixture.context) + \(fixture.prefix)")
        }
    }

    func testEighteenCandidatesAndSharedOrdering() throws {
        let fixture = try String(contentsOf: Self.root.appendingPathComponent("tests/fixtures/predictions18.tsv"), encoding: .utf8)
        for line in fixture.components(separatedBy: "\n").dropFirst() where !line.isEmpty {
            let p = line.components(separatedBy: "\t")
            let actual = Self.engine.predict(context: p[0], codePrefix: p[1]).map { $0.info.character }
            let expected = p[2].isEmpty ? [] : p[2].components(separatedBy: ",")
            XCTAssertEqual(actual, expected, "\(p[0]) + \(p[1])")
            XCTAssertEqual(Set(actual).count, actual.count)
            XCTAssertTrue(actual.count <= 18)
        }
        XCTAssertEqual(Self.engine.predict(context: "你好").count, 18)
        XCTAssertEqual(Self.engine.predict(context: "直", codePrefix: "R").count, 18)
        XCTAssertEqual(Self.engine.predict(context: "直", codePrefix: "RUVG").count, 1)
    }

    func testDictionaryAndRadicals() {
        XCTAssertEqual(Self.engine.characters.count, 13_178)
        XCTAssertEqual(Self.engine.phraseCount, 61_194)
        XCTAssertEqual(Self.engine.characters.values.filter { !$0.units.isEmpty }.count, 11_187)
        XCTAssertEqual(Self.engine.characters["接"]?.code, "RUVG")
        XCTAssertEqual(Self.engine.characters["接"]?.identification, "横·左右")
        XCTAssertEqual(Self.engine.keyboardRoots.count, 25)
        XCTAssertTrue(Self.engine.characters["人"]?.keyUnit ?? false)
    }

    func testAllPinyinSyllablesMatchWindowsFixtures() throws {
        let fixture = try String(contentsOf: Self.root.appendingPathComponent("tests/fixtures/pinyin.tsv"), encoding: .utf8)
        XCTAssertEqual(Self.engine.pinyin.characterCount, 44_440)
        for line in fixture.split(separator: "\n").dropFirst() {
            let p = line.split(separator: "\t").map(String.init)
            let items = Self.engine.pinyin.search(p[0])
            XCTAssertEqual(items.count, Int(p[1]), p[0])
            XCTAssertEqual(Set(items.map(\.id)).count, items.count, "No duplicate code points: \(p[0])")
            XCTAssertTrue(items.allSatisfy { $0.character.unicodeScalars.count == 1 && $0.readings.contains(p[0]) })
            let digest = SHA256.hash(data: Data(items.map(\.character).joined().utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, p[2], "Complete result and ordering: \(p[0])")
        }
    }

    func testPinyinNormalizationPolyphonesAndUncodedCharacters() {
        let index = Self.engine.pinyin
        XCTAssertEqual(index.search(" NI "), index.search("ni"))
        XCTAssertEqual(index.search("lue"), index.search("lve"))
        XCTAssertEqual(index.search("nue"), index.search("nve"))
        XCTAssertTrue(index.search("lv").contains { $0.character == "吕" })
        XCTAssertFalse(index.search("lu").contains { $0.character == "吕" })
        XCTAssertTrue(index.search("xing").contains { $0.character == "行" })
        XCTAssertTrue(index.search("hang").contains { $0.character == "行" })
        XCTAssertTrue(index.search("zhong").contains { $0.character == "重" })
        XCTAssertTrue(index.search("chong").contains { $0.character == "重" })
        XCTAssertGreaterThan(index.search("shi").count, 5)
        XCTAssertTrue(index.search("ji").contains { $0.character.unicodeScalars.first!.value > 0xFFFF })
        XCTAssertTrue(index.search("shi").contains { Self.engine.lookup(character: $0.character) == nil })
        for query in ["", "nihao", "ni3", "你好", "ni hao", "ni'hao", "!!!", "ß"] {
            XCTAssertTrue(index.search(query).isEmpty, query)
        }
    }


    func testPendingCodeEditingAndCommit() {
        var state = PendingCode()
        XCTAssertEqual(state.reconcile(context: "直"), "直")
        state.consume(.letter("r"))
        XCTAssertEqual(state.reconcile(context: "直r"), "直")
        XCTAssertEqual(state.code, "R")
        state.consume(.letter("u")); XCTAssertEqual(state.code, "RU")
        state.consume(.backspace); XCTAssertEqual(state.code, "R")
        state.consume(.reset); XCTAssertEqual(state.code, "")
        state.consume(.letter("r")); _ = state.reconcile(context: "直")
        _ = state.reconcile(context: "直接"); XCTAssertEqual(state.code, "")
        for letter in ["R", "U", "V", "G", "A"] { state.consume(.letter(letter)) }
        XCTAssertEqual(state.code, "A")
        state.clear(); XCTAssertEqual(state.code, "")
    }

    func testHoldKeyboardDoesNotToggleOrMutateCode() {
        var hold = HoldKeyboardState()
        var code = PendingCode(); code.consume(.letter("R"))
        XCTAssertFalse(hold.visible)
        XCTAssertTrue(hold.handle(isDown: true)); XCTAssertTrue(hold.visible)
        XCTAssertFalse(hold.handle(isDown: true)); XCTAssertTrue(hold.visible)
        XCTAssertTrue(hold.handle(isDown: false)); XCTAssertFalse(hold.visible)
        XCTAssertFalse(hold.handle(isDown: false))
        XCTAssertEqual(code.code, "R")
    }

    func testDeleteRetainsRemainingCodeAcrossStaleAXSnapshots() {
        for base in ["", "直", "已经上屏的中文"] {
            var state = PendingCode()
            _ = state.reconcile(context: base)
            state.consume(.letter("Y")); _ = state.reconcile(context: base + "y")
            state.consume(.letter("T")); _ = state.reconcile(context: base + "yt")
            XCTAssertEqual(state.code, "YT")
            state.consume(.backspace)
            XCTAssertEqual(state.code, "Y")
            for _ in 0..<3 {
                XCTAssertEqual(state.reconcile(context: base + "yt"), base)
                XCTAssertEqual(state.code, "Y")
            }
            XCTAssertEqual(state.reconcile(context: base + "y"), base)
            XCTAssertEqual(state.code, "Y")
            XCTAssertEqual(state.reconcile(context: base), base)
            XCTAssertEqual(state.code, "Y")
            XCTAssertTrue(Self.engine.predict(context: base, codePrefix: state.code).allSatisfy { $0.info.code.hasPrefix("Y") })
        }
    }

    func testRepeatedDeleteAndRetypeWhileAXCatchesUp() {
        var state = PendingCode()
        _ = state.reconcile(context: "直")
        state.consume(.letter("Y")); state.consume(.letter("T"))
        XCTAssertEqual(state.reconcile(context: "直y"), "直")
        XCTAssertEqual(state.code, "YT")
        XCTAssertEqual(state.reconcile(context: "直yt"), "直")
        state.consume(.backspace); state.consume(.backspace)
        XCTAssertEqual(state.reconcile(context: "直yt"), "直")
        XCTAssertEqual(state.code, "")
        XCTAssertEqual(state.reconcile(context: "直y"), "直")
        XCTAssertEqual(state.reconcile(context: "直"), "直")
        state.consume(.letter("Y")); state.consume(.letter("T"))
        _ = state.reconcile(context: "直yt")
        state.consume(.backspace); state.consume(.letter("R"))
        XCTAssertEqual(state.reconcile(context: "直yt"), "直")
        XCTAssertEqual(state.code, "YR")
        XCTAssertEqual(state.reconcile(context: "直y"), "直")
        XCTAssertEqual(state.code, "YR")
        XCTAssertEqual(state.reconcile(context: "直yr"), "直")
        XCTAssertEqual(state.code, "YR")
    }

    func testDeleteWithoutVisibleLatinPreeditAndActualCommit() {
        var state = PendingCode()
        _ = state.reconcile(context: "")
        state.consume(.letter("Y")); state.consume(.letter("T"))
        _ = state.reconcile(context: "")
        state.consume(.backspace)
        XCTAssertEqual(state.reconcile(context: ""), "")
        XCTAssertEqual(state.code, "Y")
        XCTAssertEqual(state.reconcile(context: "言"), "言")
        XCTAssertEqual(state.code, "")
        state.consume(.letter("Y")); _ = state.reconcile(context: "言y")
        state.consume(.reset)
        XCTAssertEqual(state.reconcile(context: "言"), "言")
        XCTAssertEqual(state.code, "")
        state.clear()
        XCTAssertEqual(state.reconcile(context: "其他输入框yt"), "其他输入框yt")
        XCTAssertEqual(state.code, "")
    }

    func testInsertInMiddleOfPreeditWithLeftAndRightArrows() {
        for base in ["", "直"] {
            var state = PendingCode()
            _ = state.reconcile(context: base)
            state.consume(.letter("Y")); state.consume(.letter("T"))
            _ = state.reconcile(context: base + "yt")
            state.consume(.moveLeft)
            XCTAssertEqual(state.code, "YT"); XCTAssertEqual(state.caret, 1)
            XCTAssertEqual(state.reconcile(context: base + "yt"), base)
            XCTAssertEqual(state.reconcile(context: base + "y"), base)
            state.consume(.letter("R"))
            XCTAssertEqual(state.code, "YRT"); XCTAssertEqual(state.caret, 2)
            for stale in ["yt", "y", "yr", "yrt"] {
                XCTAssertEqual(state.reconcile(context: base + stale), base)
                XCTAssertEqual(state.code, "YRT")
            }
            state.consume(.moveRight)
            XCTAssertEqual(state.caret, 3)
            state.consume(.backspace)
            XCTAssertEqual(state.code, "YR"); XCTAssertEqual(state.caret, 2)
            XCTAssertEqual(state.reconcile(context: base + "yrt"), base)
            XCTAssertEqual(state.reconcile(context: base + "yr"), base)
            XCTAssertEqual(state.code, "YR")
        }
    }

    func testDeleteAtPreeditCaretAndArrowBoundaries() {
        var state = PendingCode()
        _ = state.reconcile(context: "直")
        state.consume(.letter("Y")); state.consume(.letter("T"))
        _ = state.reconcile(context: "直yt")
        state.consume(.moveLeft); state.consume(.backspace)
        XCTAssertEqual(state.code, "T"); XCTAssertEqual(state.caret, 0)
        for stale in ["yt", "y", ""] {
            XCTAssertEqual(state.reconcile(context: "直" + stale), "直")
            XCTAssertEqual(state.code, "T")
        }
        state.consume(.backspace); state.consume(.moveLeft)
        XCTAssertEqual(state.code, "T"); XCTAssertEqual(state.caret, 0)
        state.consume(.letter("Y")); XCTAssertEqual(state.code, "YT")
        state.consume(.deleteForward)
        XCTAssertEqual(state.code, "Y"); XCTAssertEqual(state.caret, 1)
        state.consume(.moveRight); state.consume(.moveRight)
        XCTAssertEqual(state.code, "Y"); XCTAssertEqual(state.caret, 1)
        state.consume(.reset)
        XCTAssertEqual(state.code, ""); XCTAssertEqual(state.caret, 0)
        state.consume(.moveLeft); state.consume(.moveRight)
        XCTAssertEqual(state.reconcile(context: "其他光标位置"), "其他光标位置")
        XCTAssertEqual(state.code, ""); XCTAssertEqual(state.caret, 0)
    }

    func testPreeditEditsAcrossEightyUnitContextWindow() {
        let base = String(repeating: "中文", count: 40)
        func window(_ suffix: String) -> String { String((base + suffix).suffix(80)) }
        var state = PendingCode()
        _ = state.reconcile(context: window(""))
        state.consume(.letter("Y")); _ = state.reconcile(context: window("y"))
        state.consume(.letter("T")); _ = state.reconcile(context: window("yt"))
        state.consume(.backspace)
        _ = state.reconcile(context: window("yt"))
        _ = state.reconcile(context: window("y"))
        XCTAssertEqual(state.code, "Y")
        state.consume(.letter("T")); _ = state.reconcile(context: window("yt"))
        state.consume(.moveLeft); _ = state.reconcile(context: window("y"))
        state.consume(.letter("R")); _ = state.reconcile(context: window("yr"))
        _ = state.reconcile(context: window("yrt"))
        XCTAssertEqual(state.code, "YRT"); XCTAssertEqual(state.caret, 2)
        _ = state.reconcile(context: String((base + "话").suffix(80)))
        XCTAssertEqual(state.code, "")
    }

    func testInvalidPrefixAndNoMatch() {
        XCTAssertEqual(PendingCode.normalize(" rU "), "RU")
        XCTAssertEqual(PendingCode.normalize("abcde"), "")
        XCTAssertEqual(PendingCode.normalize("z"), "")
        XCTAssertEqual(PendingCode.normalize("123"), "")
        XCTAssertEqual(PendingCode.normalize("ß"), "")
        XCTAssertTrue(Self.engine.predict(context: "直", codePrefix: "AYYY").isEmpty)
    }

    func testHoldShortcutConsumesRepeatsAndKeyUp() {
        var shortcut = HoldKeyboardShortcut()
        XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: true))
        XCTAssertTrue(shortcut.visible)
        for _ in 0..<5 {
            XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: true, isRepeat: true))
            XCTAssertTrue(shortcut.visible)
        }
        XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: false, requiredModifiers: true))
        XCTAssertFalse(shortcut.visible)
        XCTAssertFalse(shortcut.handle(keyCode: 40, isDown: false, requiredModifiers: false))
    }

    func testHoldShortcutReleasesModifiersBeforeKey() {
        var shortcut = HoldKeyboardShortcut()
        XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: true))
        shortcut.modifiersChanged(requiredModifiers: false)
        XCTAssertFalse(shortcut.visible)
        XCTAssertTrue(shortcut.isPressed)
        XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: false, isRepeat: true))
        shortcut.modifiersChanged(requiredModifiers: true)
        XCTAssertFalse(shortcut.visible)
        XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: false, requiredModifiers: false))
        XCTAssertFalse(shortcut.isPressed)
        XCTAssertTrue(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: true))
        XCTAssertTrue(shortcut.visible)
        shortcut.reset()
        XCTAssertFalse(shortcut.visible)
        XCTAssertFalse(shortcut.handle(keyCode: 40, isDown: false, requiredModifiers: false))
    }

    func testHoldShortcutPassesNormalTypingAndFunctionKeys() {
        var shortcut = HoldKeyboardShortcut()
        XCTAssertFalse(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: false))
        shortcut.modifiersChanged(requiredModifiers: true)
        XCTAssertFalse(shortcut.visible)
        XCTAssertFalse(shortcut.handle(keyCode: 40, isDown: true, requiredModifiers: true, isRepeat: true))
        XCTAssertFalse(shortcut.handle(keyCode: 40, isDown: false, requiredModifiers: true))
        XCTAssertFalse(shortcut.handle(keyCode: 100, isDown: true, requiredModifiers: true))
        XCTAssertFalse(shortcut.handle(keyCode: 15, isDown: true, requiredModifiers: true))
        XCTAssertFalse(shortcut.visible)
    }
}
