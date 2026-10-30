import Foundation
import CryptoKit
import XCTest
@testable import WubiCore

final class CoreTests: XCTestCase {
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
