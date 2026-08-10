import XCTest
@testable import WLKit

/// What the Tower key opens, and what it says when it cannot open anything.
///
/// The decision is split out of the launch so these outcomes are testable
/// without `NSWorkspace` and without a Herdr socket — the failures are the whole
/// point of the key: a press that silently does nothing is indistinguishable
/// from a dead key, which is a fault this pad has already shown once.
final class TowerTargetTests: XCTestCase {

    private let tower = URL(fileURLWithPath: "/Applications/Tower.app")

    func testItOpensTheAgentsWorkingDirectory() {
        let agent = HerdrAgent(status: "idle", cwd: "/Users/webb/src/micro-manager", focused: true)

        let target = Tower.target(agent: agent, towerURL: tower)

        XCTAssertEqual(target, .open(directory: URL(fileURLWithPath: "/Users/webb/src/micro-manager"),
                                     tower: tower))
    }

    /// `foreground_cwd` follows a `cd` inside the pane and `cwd` is only where
    /// the pane started, so the directory the agent is working in now is the one
    /// that gets opened.
    func testItFollowsTheAgentOutOfTheDirectoryItStartedIn() {
        let agent = HerdrAgent(
            status: "idle",
            cwd: "/Users/webb/src/micro-manager",
            foregroundCwd: "/Users/webb/src/herdr",
            focused: true
        )

        let target = Tower.target(agent: agent, towerURL: tower)

        XCTAssertEqual(target, .open(directory: URL(fileURLWithPath: "/Users/webb/src/herdr"),
                                     tower: tower))
    }

    func testNothingFocusedIsReported() {
        let target = Tower.target(agent: nil, towerURL: tower)

        XCTAssertEqual(target, .problem("Nothing has focus in Herdr right now."))
    }

    func testAnAgentWithNoDirectoryIsReported() {
        let agent = HerdrAgent(status: "idle", focused: true)

        let target = Tower.target(agent: agent, towerURL: tower)

        XCTAssertEqual(target,
                       .problem("Herdr did not report a working directory for this agent."))
    }

    /// A missing Tower beats every other message. It is true whatever has focus,
    /// and "nothing has focus" would send you looking at Herdr instead of at the
    /// app that is not installed.
    func testAMissingTowerIsReportedBeforeAnythingElse() {
        let target = Tower.target(agent: nil, towerURL: nil)

        XCTAssertEqual(target, .problem("Tower is not installed."))
    }
}
