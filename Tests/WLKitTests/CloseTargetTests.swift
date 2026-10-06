import XCTest
@testable import WLKit

final class CloseTargetTests: XCTestCase {

    // MARK: - Decision

    /// Two panes share a tab; the focused one is closed, the other survives.
    func testClosesTheFocusedPaneWhenItsTabHasMoreThanOne() {
        let panes = [
            HerdrPane(paneID: "w1:p1", tabID: "w1:t1", focused: true),
            HerdrPane(paneID: "w1:p2", tabID: "w1:t1"),
        ]
        XCTAssertEqual(HerdrClient.closeTarget(panes: panes), .pane("w1:p1"))
    }

    /// The last pane in a tab takes the tab with it.
    func testClosesTheTabWhenTheFocusedPaneIsAlone() {
        let panes = [
            HerdrPane(paneID: "w1:p1", tabID: "w1:t1", focused: true),
        ]
        XCTAssertEqual(HerdrClient.closeTarget(panes: panes), .tab("w1:t1"))
    }

    /// Panes in other tabs do not add to the count: a focused pane alone in its
    /// tab still closes the tab, even with neighbours elsewhere.
    func testPanesInOtherTabsDoNotCount() {
        let panes = [
            HerdrPane(paneID: "w1:p1", tabID: "w1:t1", focused: true),
            HerdrPane(paneID: "w2:p1", tabID: "w2:t1"),
            HerdrPane(paneID: "w2:p2", tabID: "w2:t1"),
        ]
        XCTAssertEqual(HerdrClient.closeTarget(panes: panes), .tab("w1:t1"))
    }

    func testNoFocusedPaneClosesNothing() {
        let panes = [
            HerdrPane(paneID: "w1:p1", tabID: "w1:t1"),
            HerdrPane(paneID: "w1:p2", tabID: "w1:t1"),
        ]
        XCTAssertNil(HerdrClient.closeTarget(panes: panes))
    }

    func testEmptyListClosesNothing() {
        XCTAssertNil(HerdrClient.closeTarget(panes: []))
    }

    // MARK: - Decode

    /// `pane.list` elements carry `pane_id`, `tab_id` and `focused`. `focused`
    /// is absent on a pane that does not have it, and reads as false.
    func testPaneDecodeReadsTheThreeFields() {
        let pane = HerdrPane(json: [
            "pane_id": "wX:p1",
            "tab_id": "wX:t1",
            "focused": true,
        ])
        XCTAssertEqual(pane.paneID, "wX:p1")
        XCTAssertEqual(pane.tabID, "wX:t1")
        XCTAssertTrue(pane.focused)
    }

    func testPaneDecodeDefaultsFocusedToFalse() {
        let pane = HerdrPane(json: ["pane_id": "wX:p1", "tab_id": "wX:t1"])
        XCTAssertFalse(pane.focused)
    }
}
