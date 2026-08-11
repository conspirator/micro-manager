import XCTest
@testable import WLKit

/// What the picker on key 6 offers, and what it says when it can offer nothing.
///
/// The decision is split out of the launch so every outcome is testable without
/// `NSWorkspace`, without a Herdr socket, and without caring which of the three
/// apps is installed on the machine running the tests — `locate` is injected for
/// exactly that reason.
final class OpenWithTests: XCTestCase {

    private let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    private let zed = URL(fileURLWithPath: "/Applications/Zed.app")
    private let tower = URL(fileURLWithPath: "/Applications/Tower.app")

    private func all(_ app: OpenWith.App) -> URL? {
        switch app {
        case .finder: return finder
        case .zed: return zed
        case .tower: return tower
        }
    }

    private func agent(cwd: String? = "/Users/webb/src/micro-manager") -> HerdrAgent {
        HerdrAgent(status: "idle", cwd: cwd, focused: true)
    }

    /// Unwraps a `.show`, failing the test on a refusal rather than letting a
    /// nil-ish default quietly stand in for a strip that was never offered.
    private func strip(
        _ start: OpenWith.Start,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> OpenWith.Strip {
        guard case .show(let strip) = start else {
            XCTFail("expected a strip, got \(start)", file: file, line: line)
            throw Refused.instead
        }
        return strip
    }

    private enum Refused: Error { case instead }

    // MARK: - What the strip holds

    /// The order is the gesture: "6, right, Enter" only means Zed for as long as
    /// Finder, Zed, Tower is the order, so it is pinned here rather than left to
    /// whatever `CaseIterable` happens to produce.
    func testItOffersFinderThenZedThenTower() throws {
        let strip = try strip(OpenWith.start(agent: agent(), locate: all))

        XCTAssertEqual(strip.choices.map(\.app), [.finder, .zed, .tower])
        XCTAssertEqual(strip.choices.map(\.url), [finder, zed, tower])
        XCTAssertEqual(strip.directory, URL(fileURLWithPath: "/Users/webb/src/micro-manager"))
    }

    /// Finder every time, never the last thing you chose. A selection that moves
    /// on its own has to be read before Enter can be trusted.
    func testItStartsOnFinder() throws {
        let strip = try strip(OpenWith.start(agent: agent(), locate: all))

        XCTAssertEqual(strip.selection, 0)
        XCTAssertEqual(strip.selected.app, .finder)
    }

    /// `foreground_cwd` follows a `cd` inside the pane and `cwd` is only where
    /// the pane started, so the picker opens where the agent is working now.
    /// Same rule as the Tower key, and it has to stay the same rule.
    func testItFollowsTheAgentOutOfTheDirectoryItStartedIn() throws {
        let agent = HerdrAgent(
            status: "idle",
            cwd: "/Users/webb/src/micro-manager",
            foregroundCwd: "/Users/webb/src/herdr",
            focused: true
        )

        let strip = try strip(OpenWith.start(agent: agent, locate: all))

        XCTAssertEqual(strip.directory, URL(fileURLWithPath: "/Users/webb/src/herdr"))
    }

    // MARK: - Missing apps

    /// An uninstalled app is left out, not shown and refusing: an icon you can
    /// select but not launch is a key press that fails for no visible reason.
    ///
    /// The selection is an index into `choices`, and indexing `App.all` instead
    /// is the easy way to break this — with Zed gone, position 1 is Tower in one
    /// list and Zed in the other.
    func testAMissingAppIsLeftOutAndTheSelectionStillPointsAtFinder() throws {
        let strip = try strip(OpenWith.start(agent: agent()) { app in
            app == .zed ? nil : self.all(app)
        })

        XCTAssertEqual(strip.choices.map(\.app), [.finder, .tower])
        XCTAssertEqual(strip.selected.app, .finder)
        XCTAssertEqual(strip.selected.url, finder)
    }

    func testAMissingFinderShiftsEveryoneLeft() throws {
        let strip = try strip(OpenWith.start(agent: agent()) { app in
            app == .finder ? nil : self.all(app)
        })

        XCTAssertEqual(strip.choices.map(\.app), [.zed, .tower])
        XCTAssertEqual(strip.selected.app, .zed,
                       "the first choice is selected, whichever app that turns out to be")
    }

    // MARK: - Refusals

    /// These two strings are the Tower key's own words. One fault must not get
    /// two descriptions depending on which key you pressed.
    func testNothingFocusedIsReported() {
        let start = OpenWith.start(agent: nil, locate: all)

        XCTAssertEqual(start, .refuse("Nothing has focus in Herdr right now."))
    }

    func testAnAgentWithNoDirectoryIsReported() {
        let start = OpenWith.start(agent: agent(cwd: nil), locate: all)

        XCTAssertEqual(start,
                       .refuse("Herdr did not report a working directory for this agent."))
    }

    /// A strip cannot exist with nothing in it, so this is a refusal rather than
    /// an empty window. `selected` being non-optional depends on it.
    func testAStripWithNoAppsInItIsRefused() {
        let start = OpenWith.start(agent: agent()) { _ in nil }

        XCTAssertEqual(start, .refuse("Finder, Zed and Tower are all missing."))
    }

    // MARK: - Moving the selection

    func testRightWrapsPastTheLastChoice() throws {
        var strip = try strip(OpenWith.start(agent: agent(), locate: all))

        strip.move(.right)
        XCTAssertEqual(strip.selected.app, .zed)
        strip.move(.right)
        XCTAssertEqual(strip.selected.app, .tower)
        strip.move(.right)
        XCTAssertEqual(strip.selected.app, .finder, "right off the end comes back to the start")
    }

    /// The reason wrapping is worth having: Tower is one press away from Finder
    /// going left, and two going right.
    func testLeftWrapsPastTheFirstChoice() throws {
        var strip = try strip(OpenWith.start(agent: agent(), locate: all))

        strip.move(.left)

        XCTAssertEqual(strip.selected.app, .tower)
    }

    func testWithOneChoiceMovingGoesNowhere() throws {
        var strip = try strip(OpenWith.start(agent: agent()) { app in
            app == .finder ? self.finder : nil
        })

        strip.move(.left)
        strip.move(.right)

        XCTAssertEqual(strip.selection, 0)
        XCTAssertEqual(strip.choices.count, 1)
    }

    // MARK: - Keys

    /// Read from the event's key code rather than its characters: the arrow keys
    /// have no sensible characters, and a layout that remaps letters must not
    /// move the selection.
    func testTheKeysThatDriveTheStrip() {
        XCTAssertEqual(OpenWith.Key(keyCode: 123), .left)
        XCTAssertEqual(OpenWith.Key(keyCode: 124), .right)
        XCTAssertEqual(OpenWith.Key(keyCode: 36), .confirm)
        XCTAssertEqual(OpenWith.Key(keyCode: 76), .confirm, "keypad Enter is Enter")
        XCTAssertEqual(OpenWith.Key(keyCode: 53), .dismiss)
    }

    /// Anything else neither moves nor dismisses. A stray keystroke while the
    /// strip is up would otherwise either launch something or throw away a
    /// window you were still reading.
    ///
    /// Up and down are not in this list: they are real cases now, for the model
    /// picker, and the strip treats them the way it treats an unrecognised key.
    func testEveryOtherKeyIsIgnored() {
        for keyCode in [UInt16(0), 1, 12, 48, 49] {
            XCTAssertEqual(OpenWith.Key(keyCode: keyCode), .ignore, "key code \(keyCode)")
        }
    }

    /// The vertical axis belongs to the model picker, the horizontal one to the
    /// strip. One type reads both so neither panel invents its own key codes.
    func testTheVerticalArrowsAreTheirOwnCases() {
        XCTAssertEqual(PanelKey(keyCode: 125), .down)
        XCTAssertEqual(PanelKey(keyCode: 126), .up)
        XCTAssertEqual(PanelKey(keyCode: 125, modifiers: .command), .passThrough)
    }

    /// The strip swallows plain keys so they do not beep, which means it must not
    /// swallow the ones that were never meant for it: Cmd-Q while a picker is up
    /// should still quit, and Cmd-Tab should still switch apps.
    func testModifiedKeysAreLeftAlone() {
        XCTAssertEqual(OpenWith.Key(keyCode: 12, modifiers: .command), .passThrough,
                       "Cmd-Q is not the strip's to eat")
        XCTAssertEqual(OpenWith.Key(keyCode: 48, modifiers: .command), .passThrough)
        XCTAssertEqual(OpenWith.Key(keyCode: 123, modifiers: .option), .passThrough)
        XCTAssertEqual(OpenWith.Key(keyCode: 36, modifiers: .control), .passThrough)
    }

    /// Shift and Caps Lock are not commands, so they must not turn Enter into a
    /// key the strip declines to act on.
    func testShiftStillDrivesTheStrip() {
        XCTAssertEqual(OpenWith.Key(keyCode: 36, modifiers: .shift), .confirm)
        XCTAssertEqual(OpenWith.Key(keyCode: 124, modifiers: .capsLock), .right)
    }
}
