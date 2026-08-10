import XCTest
@testable import WLKit

/// Uses a real keymap read off a device, so the double-encoded envelope and the
/// layer layout are exercised against genuine data rather than a fixture I
/// invented to match my own parser. It is the stock F-key map, straight from
/// `fs.read` — keep it that way, because half these tests assert on what an
/// *unmodified* device looks like.
final class KeymapManagerTests: XCTestCase {

    private func backupKeymap() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WLKitTests
            .appendingPathComponent("Fixtures/stock-keymap.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try KeymapManager.parse(raw)
    }

    func testParsesTheDoubleEncodedEnvelope() throws {
        let config = try backupKeymap()
        XCTAssertNotNil(config["profiles"], "inner JSON string must be decoded")
    }

    func testStockKeymapIsNotAgentBound() throws {
        let config = try backupKeymap()
        XCTAssertFalse(
            KeymapManager.isAgentKeymapApplied(config),
            "the backup is the stock F-key map"
        )
        XCTAssertEqual(KeymapManager.activeLayerKeymap(config)?[0], ["KC_F13", "KC_F14"])
    }

    /// The whole pad is managed now — every key must carry its own AG code,
    /// each key's code matching its index so lights and presses line up.
    func testApplyingBindsEveryKeyToItsOwnCode() throws {
        let config = try backupKeymap()
        let next = try KeymapManager.withAgentKeymap(config)
        XCTAssertTrue(KeymapManager.isAgentKeymapApplied(next))

        let keymap = try XCTUnwrap(KeymapManager.activeLayerKeymap(next))
        XCTAssertEqual(Set(Pad.boundKeyIDs).count, Pad.keyCount, "every key is managed")
        for key in Pad.boundKeyIDs {
            let at = try XCTUnwrap(Pad.position(of: key))
            XCTAssertEqual(keymap[at.row][at.column], KeymapManager.agCodes[key])
        }
    }

    /// A pad bound the old way — six agent keys, stack key still on its F-key —
    /// has to report as *not* applied, or the rebind never happens.
    func testAgentOnlyKeymapIsNotConsideredApplied() throws {
        var config = try backupKeymap()
        var profiles = try XCTUnwrap(config["profiles"] as? [[String: Any]])
        var layers = try XCTUnwrap(profiles[0]["layers"] as? [[String: Any]])
        var layout = try XCTUnwrap(layers[0]["layout"] as? [String: Any])
        var keymap = try XCTUnwrap(layout["keymap"] as? [[String]])
        keymap[0] = ["KV_OAI_AG00", "KV_OAI_AG01"]
        keymap[1] = ["KV_OAI_AG02", "KV_OAI_AG03", "KV_OAI_AG04", "KV_OAI_AG05"]
        layout["keymap"] = keymap
        layers[0]["layout"] = layout
        profiles[0]["layers"] = layers
        config["profiles"] = profiles

        XCTAssertFalse(KeymapManager.isAgentKeymapApplied(config))
        XCTAssertTrue(KeymapManager.isAgentKeymapApplied(try KeymapManager.withAgentKeymap(config)))
    }

    /// The dial's rotations become AG codes; its press keeps its keycode.
    func testApplyingBindsTheDialButNotItsPress() throws {
        let config = try backupKeymap()
        let next = try KeymapManager.withAgentKeymap(config)

        let original = try XCTUnwrap(KeymapManager.activeLayerLayout(config))
        let layout = try XCTUnwrap(KeymapManager.activeLayerLayout(next))
        let dial = try XCTUnwrap((layout["encoders"] as? [[String]])?.first)
        let originalDial = try XCTUnwrap((original["encoders"] as? [[String]])?.first)
        XCTAssertEqual(dial[0], "KV_OAI_AG13")
        XCTAssertEqual(dial[1], "KV_OAI_AG14")
        XCTAssertEqual(dial[2], originalDial[2], "the press is not ours to take")
    }

    /// The joystick's four cardinal sectors become AG codes; diagonals keep
    /// whatever they had.
    func testApplyingBindsTheJoystickCardinals() throws {
        let config = try backupKeymap()
        let next = try KeymapManager.withAgentKeymap(config)

        let layout = try XCTUnwrap(KeymapManager.activeLayerLayout(next))
        let joystick = try XCTUnwrap(layout["joystick"] as? [String: Any])
        let sectors = try XCTUnwrap(joystick["sectors"] as? [[String: Any]])

        var cardinals: [Double: String] = [:]
        var diagonals = 0
        for sector in sectors {
            let a1 = try XCTUnwrap(sector["a1"] as? Double)
            let a2 = try XCTUnwrap(sector["a2"] as? Double)
            let centre = KeymapManager.sectorCentre(a1, a2)
            if let code = sector["k"] as? String, code.hasPrefix("KV_OAI_AG") {
                cardinals[centre] = code
            } else {
                diagonals += 1
            }
        }
        XCTAssertEqual(cardinals[0.25], "KV_OAI_AG15")
        XCTAssertEqual(cardinals[0.50], "KV_OAI_AG16")
        XCTAssertEqual(cardinals[0.75], "KV_OAI_AG17")
        XCTAssertEqual(cardinals[0.00], "KV_OAI_AG18")
        XCTAssertEqual(diagonals, 4, "the diagonal sectors keep their keycodes")
    }

    func testApplyingIsIdempotent() throws {
        let once = try KeymapManager.withAgentKeymap(try backupKeymap())
        let twice = try KeymapManager.withAgentKeymap(once)
        XCTAssertTrue(KeymapManager.isAgentKeymapApplied(twice))
    }

    func testEverythingElseSurvivesTheRewrite() throws {
        let config = try backupKeymap()
        let next = try KeymapManager.withAgentKeymap(config)

        let profiles = try XCTUnwrap(next["profiles"] as? [[String: Any]])
        let layers = try XCTUnwrap(profiles[0]["layers"] as? [[String: Any]])
        XCTAssertEqual(layers.count, 3, "the other layers are preserved")

        let layout = try XCTUnwrap(layers[0]["layout"] as? [String: Any])
        XCTAssertNotNil(layout["encoders"], "encoders survive")
        XCTAssertNotNil(layout["joystick"], "joystick survives")
        XCTAssertNotNil(layers[0]["lights"], "per-layer lighting survives")
    }

    func testMalformedInputIsRejectedRatherThanSilentlyAccepted() {
        XCTAssertThrowsError(try KeymapManager.parse(["nope": 1]))
        XCTAssertThrowsError(try KeymapManager.parse(["data": "not json"]))
        XCTAssertFalse(KeymapManager.isAgentKeymapApplied([:]))
    }
}

// MARK: - Verification must mirror the write

extension KeymapManagerTests {

    /// This pad's joystick is `type: VENDOR` with an empty `sectors` list.
    /// `withAgentKeymap` rewrites only the sectors that exist, so an empty list
    /// means nothing to write — but the check demanded all four cardinal codes
    /// be present, which no empty list can satisfy. The two disagreed forever:
    /// `apply()` wrote the keymap, then reported `notAccepted`, and because the
    /// early return could never fire it rewrote flash on every single start.
    func testAnEmptyJoystickSectorListIsAlreadySatisfied() throws {
        var config = try backupKeymap()
        config = try KeymapManager.withAgentKeymap(config)
        config = try emptyingJoystickSectors(config)

        XCTAssertTrue(
            KeymapManager.isAgentKeymapApplied(config),
            "a joystick with no sectors has nothing left to bind"
        )
    }

    /// The point of the fix: a second apply must be a no-op, so a bridge restart
    /// does not spend a flash write proving what it already knows.
    func testApplyingIsIdempotentOnAPadWithNoJoystickSectors() throws {
        var config = try backupKeymap()
        config = try emptyingJoystickSectors(config)
        XCTAssertFalse(KeymapManager.isAgentKeymapApplied(config), "stock map still needs binding")

        let next = try KeymapManager.withAgentKeymap(config)
        XCTAssertTrue(KeymapManager.isAgentKeymapApplied(next),
                      "what the writer produces, the checker must accept")
    }

    /// A sector that *is* present and carries the wrong code still fails, or the
    /// check would wave through a joystick that steers nothing.
    func testAWrongSectorCodeIsStillCaught() throws {
        var config = try KeymapManager.withAgentKeymap(try backupKeymap())
        var layout = try XCTUnwrap(KeymapManager.activeLayerLayout(config))
        var joystick = try XCTUnwrap(layout["joystick"] as? [String: Any])
        var sectors = try XCTUnwrap(joystick["sectors"] as? [[String: Any]])
        try XCTSkipIf(sectors.isEmpty, "fixture has no sectors to corrupt")

        sectors[0]["k"] = "KC_NONE"
        joystick["sectors"] = sectors
        layout["joystick"] = joystick
        config = replacingLayout(config, with: layout)

        XCTAssertFalse(KeymapManager.isAgentKeymapApplied(config))
    }

    // MARK: helpers

    private func emptyingJoystickSectors(_ config: [String: Any]) throws -> [String: Any] {
        var layout = try XCTUnwrap(KeymapManager.activeLayerLayout(config))
        layout["joystick"] = ["type": "VENDOR", "sectors": [[String: Any]]()]
        return replacingLayout(config, with: layout)
    }

    private func replacingLayout(
        _ config: [String: Any],
        with layout: [String: Any]
    ) -> [String: Any] {
        var next = config
        let index = next["activeProfileId"] as? Int ?? 0
        guard var profiles = next["profiles"] as? [[String: Any]], !profiles.isEmpty
        else { return next }
        let profileIndex = index < profiles.count ? index : 0
        var profile = profiles[profileIndex]
        guard var layers = profile["layers"] as? [[String: Any]], !layers.isEmpty
        else { return next }
        var layer = layers[0]
        layer["layout"] = layout
        layers[0] = layer
        profile["layers"] = layers
        profiles[profileIndex] = profile
        next["profiles"] = profiles
        return next
    }
}
