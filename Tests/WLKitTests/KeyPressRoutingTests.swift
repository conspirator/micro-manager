import XCTest
@testable import WLKit

/// Where a press ends up. This is the branch that has gone wrong twice: once
/// when keys 6–12 reported `ACT` names the parser dropped, and once when two
/// matrix positions shared one action. Both looked like working software.
///
/// Key 9 is deliberately not pressed here: it talks to Herdr, and a test that
/// creates a tab on the machine running it is a test nobody wants to run twice.
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
        var towerPresses = 0
        controller.onSystemKey = { posted.append($0) }
        controller.onOpenWithKey = { openWithPresses += 1 }
        controller.onTowerKey = { towerPresses += 1 }

        controller.handleKeyPress(Pad.openWithKeyID)
        controller.handleKeyPress(Pad.towerKeyID)
        for key in Pad.agentKeyIDs { controller.handleKeyPress(key) }

        XCTAssertEqual(openWithPresses, 1)
        XCTAssertEqual(towerPresses, 1)
        XCTAssertTrue(posted.isEmpty)
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
