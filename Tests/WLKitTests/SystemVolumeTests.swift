import IOKit.hidsystem
import XCTest
@testable import WLKit

/// What the dial asks of the system volume, decided without touching the Mac's
/// audio.
final class SystemVolumeTests: XCTestCase {

    func testTurningRightRaisesTheVolume() {
        XCTAssertEqual(SystemVolume.actions(forTurn: 1, muted: false), [.raise])
    }

    func testTurningLeftLowersTheVolume() {
        XCTAssertEqual(SystemVolume.actions(forTurn: -1, muted: false), [.lower])
    }

    /// The volume-down key leaves macOS muted, so a turn must clear the mute
    /// itself before it steps. Otherwise a left turn changes a volume nobody hears.
    func testTurningEitherWayWhileMutedUnmutesFirst() {
        XCTAssertEqual(SystemVolume.actions(forTurn: 1, muted: true), [.unmute, .raise])
        XCTAssertEqual(SystemVolume.actions(forTurn: -1, muted: true), [.unmute, .lower])
    }

    func testANoStepTurnDoesNothingEvenWhenMuted() {
        XCTAssertEqual(SystemVolume.actions(forTurn: 0, muted: true), [])
    }

    /// A media key carries its key type in the top half of `data1` and its state
    /// in the next byte. The system ignores a key with any other layout.
    func testTheMediaKeyEventLayout() {
        XCTAssertEqual(SystemVolume.MediaKey.volumeUp.data1(down: true),
                       Int(NX_KEYTYPE_SOUND_UP) << 16 | 0x0A00)
        XCTAssertEqual(SystemVolume.MediaKey.volumeDown.data1(down: false),
                       Int(NX_KEYTYPE_SOUND_DOWN) << 16 | 0x0B00)
        XCTAssertEqual(SystemVolume.MediaKey.mute.data1(down: true),
                       Int(NX_KEYTYPE_MUTE) << 16 | 0x0A00)
    }
}
