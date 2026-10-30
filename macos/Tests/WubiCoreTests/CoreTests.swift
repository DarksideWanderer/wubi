import Foundation
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
            XCTAssertEqual(Self.engine.predict(context: fixture.context, codePrefix: fixture.prefix).map { $0.info.character },
                           fixture.characters, "\(fixture.context) + \(fixture.prefix)")
        }
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
}
