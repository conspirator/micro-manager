import XCTest
@testable import WLKit

final class PlaceholderTests: XCTestCase {
    func testPadGeometry() {
        XCTAssertEqual(Pad.rows.flatMap { $0 }.count, Pad.keyCount)
        // Reading order is plain row-major from the top left: the first agent
        // belongs on the first key.
        XCTAssertEqual(Pad.agentKeyIDs, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(Pad.displayRows.flatMap { $0 }.sorted(), Pad.rows.flatMap { $0 }.sorted())
        // Nothing is mirrored, so what the panel draws is what the keymap
        // addresses — the two orderings cannot drift apart again.
        XCTAssertEqual(Pad.displayRows, Pad.rows)
    }
}
