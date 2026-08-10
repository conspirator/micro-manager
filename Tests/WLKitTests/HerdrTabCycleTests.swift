import XCTest
@testable import WLKit

final class HerdrTabCycleTests: XCTestCase {

    func testAdvancesToTheNextTabByNumber() {
        let tabs = [
            HerdrTab(tabID: "t1", number: 1, focused: true),
            HerdrTab(tabID: "t2", number: 2),
            HerdrTab(tabID: "t3", number: 3),
        ]
        XCTAssertEqual(HerdrClient.nextTab(in: tabs)?.tabID, "t2")
    }

    func testWrapsFromTheLastTabToTheFirst() {
        let tabs = [
            HerdrTab(tabID: "t1", number: 1),
            HerdrTab(tabID: "t2", number: 2, focused: true),
        ]
        XCTAssertEqual(HerdrClient.nextTab(in: tabs)?.tabID, "t1")
    }

    /// `tab.list` order is not guaranteed to be display order; `number` is.
    func testCyclesInNumberOrderNotListOrder() {
        let tabs = [
            HerdrTab(tabID: "t3", number: 3),
            HerdrTab(tabID: "t1", number: 1, focused: true),
            HerdrTab(tabID: "t2", number: 2),
        ]
        XCTAssertEqual(HerdrClient.nextTab(in: tabs)?.tabID, "t2")
    }

    func testStaysInsideTheFocusedWorkspace() {
        let tabs = [
            HerdrTab(tabID: "a1", workspaceID: "a", number: 1),
            HerdrTab(tabID: "a2", workspaceID: "a", number: 2, focused: true),
            HerdrTab(tabID: "b1", workspaceID: "b", number: 1),
            HerdrTab(tabID: "b2", workspaceID: "b", number: 2),
        ]
        XCTAssertEqual(HerdrClient.nextTab(in: tabs)?.tabID, "a1")
    }

    func testSingleTabHasNowhereToGo() {
        XCTAssertNil(HerdrClient.nextTab(in: [HerdrTab(tabID: "t1", number: 1, focused: true)]))
    }

    func testNoFocusedTabDoesNothing() {
        let tabs = [
            HerdrTab(tabID: "t1", number: 1),
            HerdrTab(tabID: "t2", number: 2),
        ]
        XCTAssertNil(HerdrClient.nextTab(in: tabs))
    }
}

// MARK: - Creating a tab

extension HerdrTabCycleTests {

    /// `tab.create` opens the tab wherever the server defaults to unless it is
    /// told otherwise, and returns it *unfocused* unless asked. The key wants
    /// the tab beside the agent you were looking at, and wants to land in it.
    func testCreateTabAsksForTheFocusedAgentsWorkspaceAndDirectory() {
        let agent = HerdrAgent(
            status: "idle",
            paneID: "w1:p1",
            workspaceID: "w1",
            cwd: "/Users/webb/src/micro-manager",
            foregroundCwd: "/Users/webb/src/micro-manager/docs",
            focused: true
        )
        let params = HerdrClient.createTabParams(beside: agent)
        XCTAssertEqual(params["workspace_id"] as? String, "w1")
        XCTAssertEqual(params["cwd"] as? String, "/Users/webb/src/micro-manager/docs",
                       "the tab opens where the agent is working, not where its pane started")
        XCTAssertEqual(params["focus"] as? Bool, true)
    }

    /// Nothing focused is not a failure: a new tab is still a reasonable thing
    /// to ask for. Omit the fields rather than sending empty ones, so Herdr
    /// applies its own defaults.
    func testCreateTabWithNothingFocusedStillAsksForFocus() {
        let params = HerdrClient.createTabParams(beside: nil)
        XCTAssertNil(params["workspace_id"])
        XCTAssertNil(params["cwd"])
        XCTAssertEqual(params["focus"] as? Bool, true)
    }

    func testCreateTabIgnoresAnAgentWithNoWorkspace() {
        let agent = HerdrAgent(status: "idle", paneID: "p1", focused: true)
        let params = HerdrClient.createTabParams(beside: agent)
        XCTAssertNil(params["workspace_id"])
        XCTAssertNil(params["cwd"])
    }
}
