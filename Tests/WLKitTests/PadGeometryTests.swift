import XCTest
@testable import WLKit

/// Row 3 of the pad is three separate keycaps — the device keymap has three
/// codes there, `ACT10`, `ACT11`, `ACT12` — and the app used to model the first
/// two as one wide cap bound to a single action. A press on the right-hand key
/// then meant whatever the left-hand key meant, and no test could see it.
final class PadGeometryTests: XCTestCase {

    func testTheFourFlexibleKeysEachHaveOneRole() {
        XCTAssertEqual(Pad.newTabKeyID, 9)
        XCTAssertEqual(Pad.escKeyID, 10)
        XCTAssertEqual(Pad.voiceKeyID, 11)
        XCTAssertEqual(Pad.enterKeyID, 12)
        XCTAssertEqual(Pad.rebindableKeyIDs, [9, 10, 11, 12])
        XCTAssertEqual(Set(Pad.rebindableKeyIDs).count, Pad.rebindableKeyIDs.count,
                       "no key may hold two roles")
    }

    /// Row 3 reads open-with, tower, tabs, new tab; the bottom row starts with
    /// Esc. Pinned because every light and every press is addressed by these ids,
    /// so a swap that misses one place shows up as a key doing its neighbour's job.
    func testTheActionRowOrder() {
        XCTAssertEqual(Pad.openWithKeyID, 6)
        XCTAssertEqual(Pad.towerKeyID, 7)
        XCTAssertEqual(Pad.tabCycleKeyID, 8)
        XCTAssertEqual(Pad.newTabKeyID, 9)
        XCTAssertEqual(Pad.escKeyID, 10)
    }

    /// Only a key bound to `KV_OAI_AG*` can be lit or heard from, so every role
    /// has to sit on a bound key and no id may appear twice.
    func testEveryVisibleKeyIsBoundExactlyOnce() {
        XCTAssertEqual(Pad.boundKeyIDs.sorted(), Array(0..<Pad.keyCount))
        XCTAssertEqual(Set(Pad.boundKeyIDs).count, Pad.boundKeyIDs.count)
    }

    func testTheRolesDoNotCollideWithTheAgentKeysOrTheActionKeys() {
        for key in Pad.rebindableKeyIDs {
            XCTAssertNil(Pad.agentSlot(for: key), "key \(key) would answer as an agent first")
            XCTAssertNotEqual(key, Pad.openWithKeyID)
            XCTAssertNotEqual(key, Pad.tabCycleKeyID)
            XCTAssertNotEqual(key, Pad.towerKeyID)
        }
    }

    /// The dial and joystick share the key-id space with the keys. An overlap
    /// would turn a rotation into a keystroke.
    func testTheDialAndJoystickIDsSitAboveEveryKey() {
        for id in [Pad.dialUpID, Pad.dialDownID,
                   Pad.joyNorthID, Pad.joySouthID, Pad.joyEastID, Pad.joyWestID] {
            XCTAssertFalse(Pad.boundKeyIDs.contains(id))
            XCTAssertGreaterThanOrEqual(id, Pad.keyCount)
        }
    }

    func testTheBottomRowHasThreePositions() {
        XCTAssertEqual(Pad.rows.last, [10, 11, 12])
        XCTAssertEqual(Pad.position(of: Pad.voiceKeyID)?.column, 1,
                       "the voice key is the middle of the bottom row, not half of the first cap")
    }
}
