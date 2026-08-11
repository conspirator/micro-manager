import XCTest
@testable import WLKit

/// Key 7 closes a Herdr tab, which kills whatever is running in it. It is the
/// only irreversible thing on the pad, so it takes two presses, and every way
/// out of the armed state is pinned here: an arm that outlives its window, or a
/// cancel that fails to cancel, closes work nobody asked to close.
final class CloseTabArmTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func armed() -> (CloseTabArm, Date) {
        var arm = CloseTabArm()
        XCTAssertEqual(arm.press(key: Pad.closeTabKeyID, now: t0), .arm)
        XCTAssertTrue(arm.isArmed(at: t0))
        return (arm, t0)
    }

    func testTheFirstPressArmsAndSendsNothing() {
        var arm = CloseTabArm()
        XCTAssertFalse(arm.isArmed(at: t0))
        XCTAssertEqual(arm.press(key: Pad.closeTabKeyID, now: t0), .arm)
        XCTAssertTrue(arm.isArmed(at: t0))
    }

    func testASecondPressInsideTheWindowConfirmsAndDisarms() {
        var (arm, now) = armed()
        let later = now.addingTimeInterval(CloseTabArm.window / 2)

        XCTAssertEqual(arm.press(key: Pad.closeTabKeyID, now: later), .confirm)
        XCTAssertFalse(arm.isArmed(at: later), "a confirmed arm must not stay armed")
    }

    /// The window closing has to disarm, not merely stop confirming: a press
    /// after it re-arms, so the two presses that close a tab are always the two
    /// presses you just made.
    func testAPressAfterTheWindowRearmsInsteadOfConfirming() {
        var (arm, now) = armed()
        let late = now.addingTimeInterval(CloseTabArm.window + 0.1)

        XCTAssertFalse(arm.isArmed(at: late))
        XCTAssertEqual(arm.press(key: Pad.closeTabKeyID, now: late), .arm)
        XCTAssertTrue(arm.isArmed(at: late))
    }

    /// The boundary belongs to the arm: a press at exactly the window still
    /// confirms, so a slow second press is never silently turned into a re-arm.
    func testTheWindowIsInclusive() {
        var (arm, now) = armed()
        let edge = now.addingTimeInterval(CloseTabArm.window)

        XCTAssertEqual(arm.press(key: Pad.closeTabKeyID, now: edge), .confirm)
    }

    /// Esc is the way out, and it must not also reach the terminal: an Esc
    /// posted into an agent mid-turn is its own kind of damage.
    func testEscCancelsAndIsSwallowed() {
        var (arm, now) = armed()

        XCTAssertEqual(arm.press(key: Pad.escKeyID, now: now), .cancel(swallow: true))
        XCTAssertFalse(arm.isArmed(at: now))
    }

    /// Nothing armed means Esc is just Esc. This is the pad's most-pressed key;
    /// if the arm ever swallowed it while idle, the key would look broken.
    func testEscIsUntouchedWhenNothingIsArmed() {
        var arm = CloseTabArm()
        XCTAssertEqual(arm.press(key: Pad.escKeyID, now: t0), .pass)
    }

    /// Any other key cancels, because several of them move Herdr's focus — arm,
    /// press an agent key, and a confirm would close a tab you never armed. The
    /// press still does its own job, so cancelling costs nothing but the arm.
    func testAnyOtherKeyCancelsAndStillRoutes() {
        for key in Pad.agentKeyIDs + [Pad.openWithKeyID, Pad.tabCycleKeyID, Pad.newTabKeyID] {
            var (arm, now) = armed()
            XCTAssertEqual(arm.press(key: key, now: now), .cancel(swallow: false),
                           "key \(key) must cancel the arm and still act")
            XCTAssertFalse(arm.isArmed(at: now))
        }
    }

    func testAnOtherKeyPassesWhenNothingIsArmed() {
        var arm = CloseTabArm()
        XCTAssertEqual(arm.press(key: Pad.tabCycleKeyID, now: t0), .pass)
    }

    /// The dial and joystick are not keys you press by mistake on the way to
    /// key 7, but they arrive through the same call, so they must not be a
    /// silent third way out.
    func testTheDialAndJoystickCancelTheArmToo() {
        var (arm, now) = armed()
        XCTAssertEqual(arm.press(key: Pad.dialUpID, now: now), .cancel(swallow: false))
        XCTAssertFalse(arm.isArmed(at: now))
    }

    /// The ring is red while armed, and the ring is also how you read whether an
    /// agent needs you. An arm that expires without a press has to give it back
    /// on its own, so `expire` reports the one transition worth a repaint.
    func testExpiryReportsWhetherItChangedAnything() {
        var (arm, now) = armed()

        XCTAssertFalse(arm.expire(now: now), "still inside the window")
        XCTAssertTrue(arm.isArmed(at: now))

        let late = now.addingTimeInterval(CloseTabArm.window + 0.1)
        XCTAssertTrue(arm.expire(now: late))
        XCTAssertFalse(arm.isArmed(at: late))
        XCTAssertFalse(arm.expire(now: late), "nothing left to expire")
    }
}
