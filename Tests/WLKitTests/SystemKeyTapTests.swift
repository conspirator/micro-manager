import XCTest
@testable import WLKit

/// The tap table is the kind of thing that fails while looking like working
/// software: a wrong key code posts a perfectly real event to the wrong key,
/// and nothing anywhere reports a fault.
final class SystemKeyTapTests: XCTestCase {

    func testEscapeAndEnterAreUnmodifiedSingleTaps() {
        XCTAssertEqual(SystemKeyTap.escape.keyCode, 0x35)
        XCTAssertEqual(SystemKeyTap.enter.keyCode, 0x24)
        for tap in [SystemKeyTap.escape, .enter] {
            XCTAssertEqual(tap.flags, [], "a plain key carries no modifier flag")
            XCTAssertEqual(tap.taps, 1)
        }
    }

    /// Right control, not its left twin: they are different key codes and
    /// VoiceInk is bound to one of them.
    func testRightControlCarriesTheControlFlag() {
        XCTAssertEqual(SystemKeyTap.rightControl.keyCode, 0x3E)
        XCTAssertEqual(SystemKeyTap.rightControl.flags, .maskControl)
        XCTAssertEqual(SystemKeyTap.rightControl.taps, 1)
    }

    /// VoiceInk drops the second tap only inside its 0.5 s press cooldown.
    /// A longer gap makes the second tap stop the take the first one started.
    func testDoubleTapIsTwoTapsInsideVoiceInksCooldown() {
        let double = SystemKeyTap.rightControlDouble
        XCTAssertEqual(double.keyCode, SystemKeyTap.rightControl.keyCode)
        XCTAssertEqual(double.flags, SystemKeyTap.rightControl.flags)
        XCTAssertEqual(double.taps, 2)
        XCTAssertEqual(double.gap, 0.15, accuracy: 0.0001)
        XCTAssertLessThan(double.gap, 0.5, "a tap after VoiceInk's cooldown stops the take")
    }

    /// A zero-length press is classified by duration downstream, so the hold is
    /// deliberate rather than incidental.
    func testEveryTapHoldsTheKeyBrieflyBeforeReleasing() {
        for tap in [SystemKeyTap.escape, .enter, .rightControl, .rightControlDouble] {
            XCTAssertGreaterThan(tap.hold, 0, "\(tap.keyCode) is pressed and released instantly")
            XCTAssertLessThan(tap.hold, 0.4, "\(tap.keyCode) is held long enough to read as a hold")
        }
    }

    func testTheSystemKeysAreTheOnlyKeysThatPostEvents() {
        XCTAssertEqual(SystemKeyTap.forKey(Pad.escKeyID), .escape)
        XCTAssertEqual(SystemKeyTap.forKey(Pad.enterKeyID), .enter)
        XCTAssertNil(SystemKeyTap.forKey(Pad.voiceKeyID),
                     "the voice key picks its gesture from the take state, not from a table")
        XCTAssertNil(SystemKeyTap.forKey(Pad.newTabKeyID))
        XCTAssertNil(SystemKeyTap.forKey(Pad.openWithKeyID))
        for key in Pad.agentKeyIDs { XCTAssertNil(SystemKeyTap.forKey(key)) }
    }
}
