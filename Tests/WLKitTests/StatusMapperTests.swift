import XCTest
import SwiftUI
@testable import WLKit

/// Mirrors test/status.test.js so the two implementations cannot drift.
final class StatusMapperTests: XCTestCase {

    private func agent(_ status: String, pane: String = "w1:p1") -> HerdrAgent {
        HerdrAgent(status: status, paneID: pane)
    }

    // MARK: - Aggregate

    func testNoAgentsMeansNoState() {
        XCTAssertNil(StatusMapper.aggregate([]))
    }

    func testBlockedOutranksWorkingAndIdle() {
        let state = StatusMapper.aggregate([
            agent("idle", pane: "w1:p1"),
            agent("working", pane: "w1:p2"),
            agent("blocked", pane: "w1:p3"),
        ])
        XCTAssertEqual(state, "blocked")
        XCTAssertEqual(StatusMapper.zone(for: state)?.color, 0xFF2D2D)
    }

    func testWorkingOutranksIdleAndDone() {
        let state = StatusMapper.aggregate([agent("done"), agent("idle"), agent("working")])
        XCTAssertEqual(state, "working")
        XCTAssertEqual(StatusMapper.zone(for: state)?.color, 0xFFA000)
    }

    func testUnrecognisedStatusStillYieldsAState() {
        XCTAssertEqual(StatusMapper.aggregate([agent("wat")]), "unknown")
    }

    func testBlockedBreathesSoItReadsDifferently() {
        XCTAssertEqual(StatusMapper.zone(for: "blocked")?.effect, .breath)
        XCTAssertEqual(StatusMapper.zone(for: "working")?.effect, .solid)
    }

    // MARK: - Per-key

    func testEachAgentGetsItsOwnKeyInReadingOrder() {
        let threads = StatusMapper.threads(for: [
            agent("working"), agent("blocked"), agent("idle"),
        ])
        XCTAssertEqual(threads.count, 6, "one entry per agent key")
        // Key index is row-major from the top LEFT, and a key's thread id is
        // the same number its AG keycode reports, so slot N is simply key N.
        // An earlier version reversed the top row and lit the first agent on
        // the second key while the first key stayed dark.
        XCTAssertEqual(threads.map(\.id), [0, 1, 2, 3, 4, 5], "keys in reading order")
        XCTAssertEqual(threads[0].color, 0xFFA000)
        XCTAssertEqual(threads[1].color, 0xFF2D2D)
        XCTAssertEqual(threads[2].color, 0x00B0FF)
    }

    func testKeysWithNoAgentAreSwitchedOffNotLeftStale() {
        let threads = StatusMapper.threads(for: [agent("working")])
        for thread in threads.dropFirst() {
            XCTAssertEqual(thread.effect, .off)
            XCTAssertEqual(thread.brightness, 0)
            XCTAssertNil(thread.color, "no colour on an unused key")
        }
    }

    func testBlockedAgentBreathesOnItsOwnKey() {
        let threads = StatusMapper.threads(for: [agent("idle"), agent("blocked")])
        XCTAssertEqual(threads[0].effect, .solid)
        XCTAssertEqual(threads[1].effect, .breath)
    }

    func testMoreAgentsThanKeysDoesNotOverflow() {
        let many = (0..<9).map { _ in agent("working") }
        XCTAssertEqual(StatusMapper.threads(for: many).count, 6)
    }

    func testConfigOverridesAreHonoured() {
        var cfg = BridgeConfig()
        cfg.colors["working"] = 0x123456
        cfg.brightness = 0.3
        let thread = StatusMapper.threads(for: [agent("working")], cfg)[0]
        XCTAssertEqual(thread.color, 0x123456)
        XCTAssertEqual(thread.brightness, 0.3)
    }

    // MARK: - Wire encoding

    func testThreadWireUsesAbbreviatedKeysAndNumericEffect() {
        let wire = OAI.Thread(id: 0, color: 0xFF0000, brightness: 1, effect: .solid, speed: 0.5).wire
        XCTAssertEqual(wire["id"] as? Int, 0)
        XCTAssertEqual(wire["c"] as? Int, 0xFF0000)
        XCTAssertEqual(wire["b"] as? Double, 1)
        XCTAssertEqual(wire["e"] as? Int, 1, "effect is a NUMBER, not a string")
        XCTAssertEqual(wire["s"] as? Double, 0.5)
        XCTAssertNil(wire["color"], "full field names are ignored by the firmware")
    }

    func testUnsetThreadFieldsAreOmittedSoTheyStayUnchanged() {
        let wire = OAI.Thread(id: 3, brightness: 0, effect: .off).wire
        XCTAssertNil(wire["c"])
        XCTAssertNil(wire["s"])
    }

    func testColourRoundTrip() {
        XCTAssertEqual(packedRGB(fromHex: "#FF2D2D"), 0xFF2D2D)
        XCTAssertEqual(packedRGB(fromHex: "00C853"), 0x00C853)
        XCTAssertEqual(packedRGB(fromHex: "#0f0"), 0x00FF00)
        XCTAssertEqual(hexString(0xFF2D2D), "#FF2D2D")
    }

    /// Slots follow the pad's reading order, so a slot must always resolve to
    /// the key that lights it and back.
    func testAgentSlotAndKeyAreInverses() {
        for (slot, key) in Pad.agentKeyIDs.enumerated() {
            XCTAssertEqual(Pad.agentSlot(for: key), slot)
        }
        XCTAssertNil(Pad.agentSlot(for: Pad.stackKeyID))
        XCTAssertNil(Pad.agentSlot(for: Pad.towerKeyID))
    }

    // MARK: - AG key names

    func testAGNamesMapToKeyIndices() {
        XCTAssertEqual(OAI.agIndex("AG00"), 0)
        XCTAssertEqual(OAI.agIndex("AG05"), 5)
        XCTAssertEqual(OAI.agIndex("AG12"), 12)
        XCTAssertNil(OAI.agIndex("KC_F13"))
        XCTAssertNil(OAI.agIndex(nil))
    }
}

// MARK: - Status colours must stay distinguishable

extension StatusMapperTests {

    func testDoneAndIdleAreToldApartByColour() {
        // "done" means finished and not yet looked at; "idle" means finished
        // and seen. Different signals, so they must not share a colour.
        let cfg = BridgeConfig()
        XCTAssertNotEqual(
            cfg.color(for: "done"),
            cfg.color(for: "idle"),
            "a finished-but-unread agent must be distinguishable from a quiet one"
        )
        XCTAssertEqual(cfg.color(for: "idle"), 0x00B0FF)
        XCTAssertEqual(cfg.color(for: "done"), 0x00C853)
    }

    func testAttentionStatesAllHaveDistinctColours() {
        let cfg = BridgeConfig()
        var seen: [Int: String] = [:]
        for state in ["blocked", "working", "done", "idle"] {
            let color = cfg.color(for: state)
            XCTAssertNil(seen[color], "\(state) reuses the colour of \(seen[color] ?? "")")
            seen[color] = state
        }
    }

    func testDoneAndIdleAgentsGetDifferentKeys() {
        let threads = StatusMapper.threads(for: [
            HerdrAgent(status: "done", paneID: "w1:p1"),
            HerdrAgent(status: "idle", paneID: "w1:p2"),
        ])
        XCTAssertEqual(threads[0].color, 0x00C853)
        XCTAssertEqual(threads[1].color, 0x00B0FF)
    }

    /// Pins every status colour. These are the whole point of the pad — a
    /// silent change to one is a bug you find by looking at hardware, which is
    /// the slowest possible way to find it.
    func testEveryStatusColourIsPinned() {
        let cfg = BridgeConfig()
        XCTAssertEqual(cfg.color(for: "blocked"), 0xFF2D2D)
        XCTAssertEqual(cfg.color(for: "working"), 0xFFA000)
        XCTAssertEqual(cfg.color(for: "done"), 0x00C853)
        XCTAssertEqual(cfg.color(for: "idle"), 0x00B0FF)
        XCTAssertEqual(cfg.color(for: "unknown"), 0x00B0FF)
    }

    /// Green is the one colour that means "finished, go and read it". A status
    /// the app could not read is not that, so it must not borrow the colour —
    /// otherwise an unreachable Herdr looks like a row of completed work.
    func testUnknownDoesNotLookFinished() {
        let cfg = BridgeConfig()
        XCTAssertNotEqual(cfg.color(for: "unknown"), cfg.color(for: "done"))
        XCTAssertEqual(
            cfg.color(for: "unknown"),
            cfg.color(for: "idle"),
            "unknown reads as quiet, which is the safe assumption"
        )
    }
}

// MARK: - The four keys below the agent block

extension StatusMapperTests {

    /// These keys gave up the keystroke they used to send when they were bound
    /// to `KV_OAI_AG*`, so a dark one reads as broken hardware. Every one of
    /// them stays lit, and in its own colour, so the row is not one blur.
    func testEveryRoleKeyIsLitAndTellsItselfApart() {
        let cfg = BridgeConfig()
        let threads = [
            StatusMapper.systemKeyThread(id: Pad.escKeyID, cfg),
            StatusMapper.newTabThread(cfg),
            StatusMapper.voiceThread(id: Pad.voiceKeyID, active: false, cfg),
            StatusMapper.macroThread(id: Pad.enterKeyID, cfg),
        ]
        for thread in threads {
            XCTAssertGreaterThan(thread.brightness ?? 0, 0, "key \(thread.id) is dark")
            XCTAssertNotEqual(thread.effect, .off)
        }
        let colors = threads.compactMap(\.color)
        XCTAssertEqual(Set(colors).count, colors.count, "two roles share a colour")
    }

    func testTheSystemKeysShareOneColourAndSitOnTheRightIDs() {
        let esc = StatusMapper.systemKeyThread(id: Pad.escKeyID)
        let enter = StatusMapper.systemKeyThread(id: Pad.enterKeyID)
        XCTAssertEqual(esc.id, 10)
        XCTAssertEqual(enter.id, 12)
        XCTAssertEqual(esc.color, enter.color, "esc and enter are the same kind of key")
    }

    /// The new-tab key sits next to the tab-cycle key and does a related thing,
    /// so it must not be confusable with it at a glance.
    func testTheNewTabKeyIsNotTheTabCycleKeysColour() {
        XCTAssertEqual(StatusMapper.newTabThread().id, Pad.newTabKeyID)
        XCTAssertNotEqual(StatusMapper.newTabThread().color, StatusMapper.tabCycleThread().color)
    }

    /// The Tower key has no state to show — it opens a repository and that is
    /// all — so it sits dim and solid like the other stateless keys on its row.
    /// Dim, not dark: the key is bound to `KV_OAI_AG*`, and a bound key that
    /// never lights reads as broken hardware.
    func testTheTowerKeyIsDimSolidAndNotItsNeighboursColour() {
        let cfg = BridgeConfig()
        let tower = StatusMapper.towerThread(cfg)

        XCTAssertEqual(tower.id, Pad.towerKeyID)
        XCTAssertEqual(tower.effect, .solid)
        XCTAssertGreaterThan(tower.brightness ?? 0, 0, "a bound key that never lights reads as broken")
        XCTAssertLessThan(tower.brightness ?? cfg.brightness, cfg.brightness)
        XCTAssertNotEqual(tower.color, StatusMapper.tabCycleThread(cfg).color)
        XCTAssertNotEqual(tower.color, StatusMapper.stackThread(open: false, cfg).color)
    }

    /// An open take is the one state on this row you need to see from across
    /// the room: full brightness, breathing, and a different colour.
    func testTheVoiceKeyShowsAnOpenTake() {
        let idle = StatusMapper.voiceThread(id: Pad.voiceKeyID, active: false)
        let open = StatusMapper.voiceThread(id: Pad.voiceKeyID, active: true)
        XCTAssertEqual(open.effect, .breath)
        XCTAssertEqual(idle.effect, .solid)
        XCTAssertNotEqual(open.color, idle.color)
        XCTAssertGreaterThan(open.brightness ?? 0, idle.brightness ?? 1)
    }
}
