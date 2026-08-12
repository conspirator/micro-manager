import XCTest
@testable import WLKit

/// The layout table fails silently in two different ways, and both are here.
///
/// A wrong key code posts a real chord to the wrong Raycast hotkey, so the
/// window moves somewhere nobody asked for. A missing `secondaryFn` bit posts a
/// chord Raycast ignores outright: measured on this machine, ctrl+opt+cmd+left
/// without fn leaves the window exactly where it was and reports nothing at all.
/// Neither failure is visible from the pad — the slice lights up as committed
/// either way.
final class WindowLayoutTests: XCTestCase {

    /// The five slices, their Raycast layout, and the key each one presses.
    /// Measured by posting each chord and reading the window frame back: halves
    /// land at 1280 wide, the thirds at 1706, almost maximize inset to
    /// 2304x1268.
    private let table: [(RadialAim.Direction, CGKeyCode, String)] = [
        (.west, 0x7B, "Left Half"),
        (.east, 0x7C, "Right Half"),
        (.northWest, 0x7E, "First Two Thirds"),
        (.northEast, 0x7D, "Last Two Thirds"),
        (.north, 0x79, "Almost Maximize"),
    ]

    func testEachBoundSliceCarriesItsOwnKeyCodeAndName() {
        for (direction, keyCode, name) in table {
            let layout = WindowLayout.forDirection(direction)
            XCTAssertEqual(layout?.tap.keyCode, keyCode, "\(direction) presses the wrong key")
            XCTAssertEqual(layout?.name, name, "\(direction) is labelled wrong")
        }
    }

    /// The bit that cost eight probes. Raycast records the flags a real press
    /// carries when you assign the hotkey, and every key in this table — the
    /// four arrows and Page Down — is a function key, so a real press sets fn.
    /// A chord without it looks like one no keyboard could produce, and Raycast
    /// discards it.
    func testEveryChordSetsTheFunctionBit() {
        for (direction, _, name) in table {
            let flags = WindowLayout.forDirection(direction)?.tap.flags
            XCTAssertEqual(
                flags?.contains(.maskSecondaryFn), true,
                "\(name) without fn is a chord Raycast ignores in silence"
            )
        }
    }

    func testEveryChordHoldsControlOptionAndCommand() {
        for (direction, _, name) in table {
            guard let flags = WindowLayout.forDirection(direction)?.tap.flags else {
                return XCTFail("\(name) has no layout")
            }
            for (flag, label) in [
                (CGEventFlags.maskControl, "control"),
                (.maskAlternate, "option"),
                (.maskCommand, "command"),
            ] {
                XCTAssertTrue(flags.contains(flag), "\(name) is missing \(label)")
            }
            XCTAssertFalse(flags.contains(.maskShift), "\(name) holds a shift nobody asked for")
        }
    }

    func testChordsAreSingleTaps() {
        for (direction, _, name) in table {
            XCTAssertEqual(WindowLayout.forDirection(direction)?.tap.taps, 1,
                           "\(name) should fire once")
        }
    }

    /// Two keys pressing the same chord would be a slice quietly doing another
    /// slice's job — the mistake row 3 of the keymap already made once, where
    /// two matrix positions were bound to the same action.
    func testNoTwoSlicesPressTheSameKey() {
        let codes = table.compactMap { WindowLayout.forDirection($0.0)?.tap.keyCode }
        XCTAssertEqual(Set(codes).count, codes.count, "two slices share a key code")
    }

    /// South is cancel and the two lower diagonals are unbound. The menu draws
    /// all three as slices that do nothing, and it reads that from here, so a
    /// binding added later cannot show up in one place and not the other.
    func testUnboundDirectionsHaveNoLayout() {
        for direction in [RadialAim.Direction.south, .southEast, .southWest] {
            XCTAssertNil(WindowLayout.forDirection(direction),
                         "\(direction) must stay unbound")
        }
    }

    func testEveryDirectionIsAccountedFor() {
        let bound = table.map(\.0)
        let unbound: [RadialAim.Direction] = [.south, .southEast, .southWest]
        XCTAssertEqual(
            Set(bound).union(unbound).count, RadialAim.Direction.allCases.count,
            "a direction is neither bound nor deliberately unbound"
        )
    }
}
