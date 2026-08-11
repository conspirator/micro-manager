import XCTest
@testable import WLKit

/// Where a press ends up. This is the branch that has gone wrong twice: once
/// when keys 6–12 reported `ACT` names the parser dropped, and once when two
/// matrix positions shared one action. Both looked like working software.
///
/// Keys 7 and 9 are deliberately never pressed to completion here: they talk to
/// Herdr, and a test that creates — or closes — a tab on the machine running it
/// is a test nobody wants to run twice. Key 7 is pressed once, which by design
/// only arms.
@MainActor
final class KeyPressRoutingTests: XCTestCase {

    private func bridge() -> BridgeController {
        BridgeController(config: BridgeConfig())
    }

    func testEscAndEnterPostTheirOwnKeystrokes() {
        let controller = bridge()
        var posted: [SystemKeyTap] = []
        controller.onSystemKey = { posted.append($0) }

        controller.handleKeyPress(Pad.escKeyID)
        controller.handleKeyPress(Pad.enterKeyID)

        XCTAssertEqual(posted, [.escape, .enter])
    }

    func testTheVoiceKeyGoesToTheVoiceControllerAndPostsNothingItself() {
        let controller = bridge()
        var voicePresses = 0
        var posted: [SystemKeyTap] = []
        controller.onVoiceKey = { voicePresses += 1 }
        controller.onSystemKey = { posted.append($0) }

        controller.handleKeyPress(Pad.voiceKeyID)

        XCTAssertEqual(voicePresses, 1)
        XCTAssertTrue(posted.isEmpty, "the voice gesture depends on state the bridge does not hold")
    }

    /// A press must land in exactly one branch. The keys either side of the
    /// system keys share a row with them, and an off-by-one here would fire the
    /// wrong action with nothing reporting a fault.
    func testTheActionKeysDoNotPostKeystrokes() {
        let controller = bridge()
        var posted: [SystemKeyTap] = []
        var openWithPresses = 0
        controller.onSystemKey = { posted.append($0) }
        controller.onOpenWithKey = { openWithPresses += 1 }

        controller.handleKeyPress(Pad.openWithKeyID)
        for key in Pad.agentKeyIDs { controller.handleKeyPress(key) }

        XCTAssertEqual(openWithPresses, 1)
        XCTAssertTrue(posted.isEmpty)
    }

    /// One press of key 7 must not reach Herdr at all. Nothing here can prove a
    /// tab was left alone, so the arm flag is the evidence: it is the state that
    /// stands between one press and a closed tab.
    func testOnePressOfTheCloseTabKeyOnlyArms() {
        let controller = bridge()
        var posted: [SystemKeyTap] = []
        controller.onSystemKey = { posted.append($0) }

        XCTAssertFalse(controller.closeTabArmed)
        controller.handleKeyPress(Pad.closeTabKeyID)

        XCTAssertTrue(controller.closeTabArmed)
        XCTAssertTrue(posted.isEmpty)
    }

    /// Esc while armed cancels, and the keystroke goes nowhere: an Esc posted
    /// into an agent mid-turn is its own kind of damage.
    func testEscCancelsTheArmWithoutPostingItself() {
        let controller = bridge()
        var posted: [SystemKeyTap] = []
        controller.onSystemKey = { posted.append($0) }

        controller.handleKeyPress(Pad.closeTabKeyID)
        controller.handleKeyPress(Pad.escKeyID)

        XCTAssertFalse(controller.closeTabArmed)
        XCTAssertTrue(posted.isEmpty, "the arm swallows the Esc that cancels it")

        controller.handleKeyPress(Pad.escKeyID)
        XCTAssertEqual(posted, [.escape], "and only that one")
    }

    /// Any other key cancels the arm and still does its own job — the press that
    /// changed Herdr's focus must not leave a confirm pointing at a different
    /// tab than the one you armed.
    func testAnotherKeyCancelsTheArmAndStillActs() {
        let controller = bridge()
        var openWithPresses = 0
        controller.onOpenWithKey = { openWithPresses += 1 }

        controller.handleKeyPress(Pad.closeTabKeyID)
        controller.handleKeyPress(Pad.openWithKeyID)

        XCTAssertFalse(controller.closeTabArmed)
        XCTAssertEqual(openWithPresses, 1)
    }

    /// A modal window claims every key while it is up, and that has to include
    /// the one that arms a close: a pad key pressed to dismiss a window must not
    /// also leave the ring red.
    func testAnInterceptedPressNeverArms() {
        let controller = bridge()
        controller.onKeyIntercept = { _ in true }

        controller.handleKeyPress(Pad.closeTabKeyID)

        XCTAssertFalse(controller.closeTabArmed)
    }

    /// A modal window can claim every key while it is up, which turns the rest
    /// of the pad into "cancel". That has to hold for the keys that synthesise
    /// keystrokes too, or an Esc meant to dismiss the window would be posted at
    /// the terminal instead.
    func testAPendingConfirmationSwallowsTheSystemKeys() {
        let controller = bridge()
        var posted: [SystemKeyTap] = []
        var voicePresses = 0
        controller.onSystemKey = { posted.append($0) }
        controller.onVoiceKey = { voicePresses += 1 }
        controller.onKeyIntercept = { _ in true }

        controller.handleKeyPress(Pad.escKeyID)
        controller.handleKeyPress(Pad.enterKeyID)
        controller.handleKeyPress(Pad.voiceKeyID)

        XCTAssertTrue(posted.isEmpty)
        XCTAssertEqual(voicePresses, 0)
    }
}
