import XCTest
@testable import WLKit

final class KeyBindingsTests: XCTestCase {

    private func parse(_ json: String) -> KeyBindings {
        KeyBindings.parse(Data(json.utf8))
    }

    /// Every key now has a built-in role, so nothing types text until the file
    /// says so. A default here would silently replace Esc or Enter.
    func testNoKeyTypesTextUntilConfigured() {
        let bindings = KeyBindings()
        for key in Pad.rebindableKeyIDs {
            XCTAssertNil(bindings.text(for: key), "key \(key) has a role, not a default string")
        }
        XCTAssertTrue(KeyBindings.defaults.isEmpty)
    }

    /// A configured string replaces the key's role, and only on the keys the pad
    /// routes through the binding — an agent key answers as an agent first.
    func testTextIsOnlyHonouredOnTheRebindableKeys() {
        let bindings = parse(#"{"keys": {"9": "Ship it", "0": "not an agent key"}}"#)
        XCTAssertEqual(bindings.text(for: 9), "Ship it")
        for key in Pad.agentKeyIDs + [Pad.stackKeyID, Pad.tabCycleKeyID, Pad.towerKeyID] {
            XCTAssertFalse(Pad.rebindableKeyIDs.contains(key),
                           "key \(key) would lose its role to a stray config line")
        }
    }

    func testEachKeyBindsOnItsOwn() {
        let bindings = parse(#"{"keys": {"10": "new tab no more", "11": "quiet please"}}"#)
        XCTAssertEqual(bindings.text(for: 10), "new tab no more")
        XCTAssertEqual(bindings.text(for: 11), "quiet please")
        XCTAssertNil(bindings.text(for: 12), "binding one key leaves its neighbour alone")
    }

    /// The wide-keycap alias named a cap that does not exist: row 3 is three
    /// separate keys. It must not quietly bind two of them at once.
    func testTheWideKeyAliasIsGone() {
        let bindings = parse(#"{"keys": {"10+11": "Summarise your progress"}}"#)
        XCTAssertNil(bindings.text(for: 10))
        XCTAssertNil(bindings.text(for: 11))
    }

    /// An empty string unbinds: the key falls back to its role rather than
    /// typing nothing.
    func testEmptyStringUnbindsAKey() {
        let bindings = parse(#"{"keys": {"12": "", "9": "Ship it"}}"#)
        XCTAssertNil(bindings.text(for: 12))
        XCTAssertEqual(bindings.text(for: 9), "Ship it")
    }

    func testMalformedFileFallsBackToDefaults() {
        XCTAssertEqual(parse("not json"), KeyBindings())
        XCTAssertEqual(parse(#"{"keys": "nope"}"#), KeyBindings())
    }

    func testClaudeModelAndEffortListsHaveDefaults() {
        let bindings = KeyBindings()
        XCTAssertEqual(bindings.claudeModels, ["fable", "opus", "sonnet", "haiku"])
        XCTAssertEqual(bindings.claudeEfforts, ["low", "medium", "high", "xhigh", "max"])
    }

    func testClaudeListsAreOverridable() {
        let bindings = parse(#"{"claude": {"models": ["opus", "sonnet"], "efforts": ["low", "high"]}}"#)
        XCTAssertEqual(bindings.claudeModels, ["opus", "sonnet"])
        XCTAssertEqual(bindings.claudeEfforts, ["low", "high"])
    }

    func testEmptyClaudeListsFallBackToDefaults() {
        let bindings = parse(#"{"claude": {"models": []}}"#)
        XCTAssertEqual(bindings.claudeModels, KeyBindings.defaultClaudeModels)
    }

    /// Codex's list has no default to fall back on: it is a copy of what that
    /// TUI offers, and guessing it would put wrong names next to the numbers.
    func testCodexModelsAreEmptyUntilConfigured() {
        XCTAssertEqual(KeyBindings().codexModels, [])
        XCTAssertEqual(parse(#"{"codex": {"models": []}}"#).codexModels, [])
    }

    func testCodexModelsComeFromTheFile() {
        let bindings = parse(#"{"codex": {"models": ["gpt-5.6-sol", "gpt-5.6-codex"]}}"#)
        XCTAssertEqual(bindings.codexModels, ["gpt-5.6-sol", "gpt-5.6-codex"])
        XCTAssertEqual(bindings.claudeModels, KeyBindings.defaultClaudeModels,
                       "a codex-only config leaves the claude side alone")
    }
}
