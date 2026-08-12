import XCTest
@testable import WLKit

/// The joystick's radial stream, turned into a menu selection.
///
/// Every threshold here was measured off the pad rather than chosen: see the
/// traces quoted in the cases below. The two facts the whole model rests on are
/// that the pad reports **on change** — it went silent for 1.13s while the stick
/// was held hard against its stop — and that it always reports a clean
/// `{"a":0,"d":0}` when the stick comes back. So a gap in the stream means
/// nothing at all, and release is an event we can trust.
final class RadialAimTests: XCTestCase {

    // MARK: - Sectors

    /// Eight sectors, centred on multiples of an eighth of a turn, with 0 east
    /// and the angle climbing counter-clockwise. That is the pad's own
    /// convention — the stock keymap puts `KC_P7` at 0.125 and it is the NE key
    /// — so nothing has to be converted between here and the keymap.
    func testEachSectorCentreNamesItsDirection() {
        let expected: [(Double, RadialAim.Direction)] = [
            (0.000, .east),
            (0.125, .northEast),
            (0.250, .north),
            (0.375, .northWest),
            (0.500, .west),
            (0.625, .southWest),
            (0.750, .south),
            (0.875, .southEast),
        ]
        for (angle, direction) in expected {
            XCTAssertEqual(
                RadialAim.Direction(angle: angle), direction,
                "angle \(angle) should be \(direction)"
            )
        }
    }

    /// The east sector wraps through zero — the stock keymap writes it
    /// `a1: 0.9375, a2: 0.0625` — so an angle just short of a full turn is east
    /// and not some ninth direction off the end of the list.
    func testTheEastSectorWrapsThroughZero() {
        XCTAssertEqual(RadialAim.Direction(angle: 0.97), .east)
        XCTAssertEqual(RadialAim.Direction(angle: 0.9376), .east)
        XCTAssertEqual(RadialAim.Direction(angle: 1.0), .east)
    }

    /// Between two sectors the answer is the next one round, not a crash and not
    /// a nil. A boundary that returned nothing would drop the aim at exactly the
    /// moment the user is choosing between two slices.
    func testSectorBoundariesLandOnTheHigherSector() {
        XCTAssertEqual(RadialAim.Direction(angle: 0.0625), .northEast)
        XCTAssertEqual(RadialAim.Direction(angle: 0.1875), .north)
    }

    // MARK: - Waking

    /// The pad's first report of a touch was `d: 0.0096`, long before any
    /// direction was chosen. That is the cue to put the compass on screen: a
    /// menu you see while deciding, rather than a receipt after the fact.
    func testTheFirstTouchWakesTheMenuWithoutAiming() {
        var aim = RadialAim()
        XCTAssertEqual(aim.update(angle: 0.049188, distance: 0.009606), [.wake])
        XCTAssertNil(aim.aimed)
    }

    /// A resting stick reads exactly zero on both fields, and it is the state
    /// the pad sits in whenever nobody is touching it. Nothing may come out of
    /// that, or the menu would be permanently on screen.
    func testARestingStickSaysNothing() {
        var aim = RadialAim()
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [])
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [])
    }

    /// Touched and let go without a real push: the menu appears and goes away
    /// again having chosen nothing. No `commit` may escape, because the user
    /// never pointed at anything.
    func testATouchWithNoDeflectionSelectsNothing() {
        var aim = RadialAim()
        XCTAssertEqual(aim.update(angle: 0.049, distance: 0.0096), [.wake])
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [.sleep])
        XCTAssertNil(aim.aimed)
    }

    /// Below the engage threshold the angle is noise: at rest the pad reported
    /// `a: 0.0299` with `d: 0.12`, an east it was never pointing at. A partial
    /// deflection must therefore wake the menu and aim nothing.
    func testAngleIsIgnoredUntilTheStickIsPushedPastEngage() {
        var aim = RadialAim()
        XCTAssertEqual(aim.update(angle: 0.25, distance: 0.2), [.wake])
        XCTAssertNil(aim.aimed)
    }

    // MARK: - Aiming and committing

    func testPushingPastEngageAims() {
        var aim = RadialAim()
        XCTAssertEqual(aim.update(angle: 0.25, distance: 0.9), [.wake, .aim(.north)])
        XCTAssertEqual(aim.aimed, .north)
    }

    /// Already aiming, and still in the same sector: no repeat event. The view
    /// would flash the wedge on every one of the 30ms-apart reports a slow
    /// movement produces.
    func testStayingInASectorDoesNotReaim() {
        var aim = RadialAim()
        _ = aim.update(angle: 0.25, distance: 0.9)
        XCTAssertEqual(aim.update(angle: 0.26, distance: 0.95), [])
    }

    /// Sliding round the rim re-aims, and only where you let go counts. This is
    /// what makes the menu correctable: an overshoot is fixed by carrying on.
    func testSlidingRoundTheRimReaimsAndTheLastOneWins() {
        var aim = RadialAim()
        _ = aim.update(angle: 0.0, distance: 1)
        XCTAssertEqual(aim.update(angle: 0.125, distance: 1), [.aim(.northEast)])
        XCTAssertEqual(aim.update(angle: 0.25, distance: 1), [.aim(.north)])
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [.commit(.north)])
        XCTAssertNil(aim.aimed)
    }

    /// The hysteresis band, from the real trace: a release passes through
    /// `d: 0.32` on its way to zero. That is below engage, so it must not
    /// re-aim at the angle it happens to be reporting, and it is above release,
    /// so it must not commit either.
    func testTheBandBetweenTheThresholdsNeitherAimsNorCommits() {
        var aim = RadialAim()
        _ = aim.update(angle: 0.25, distance: 1)
        XCTAssertEqual(aim.update(angle: 0.5, distance: 0.323), [])
        XCTAssertEqual(aim.aimed, .north)
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [.commit(.north)])
    }

    /// A second release changes nothing. The pad repeats `{"a":0,"d":0}` and a
    /// second commit would fire an action the user asked for once.
    func testReleasingTwiceCommitsOnce() {
        var aim = RadialAim()
        _ = aim.update(angle: 0.25, distance: 1)
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [.commit(.north)])
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [])
    }

    // MARK: - The traces

    /// Hard right and release, exactly as the Inspector logged it. Four reports
    /// for a whole gesture, and the one that decides the answer is the second.
    func testTheHardRightTraceCommitsEastOnce() {
        var aim = RadialAim()
        var events: [RadialAim.Event] = []
        for (angle, distance) in [
            (0.040622, 0.047699),
            (0.007185, 1.0),
            (0.017692, 0.323347),
            (0.0, 0.0),
        ] {
            events += aim.update(angle: angle, distance: distance)
        }
        XCTAssertEqual(events, [.wake, .aim(.east), .commit(.east)])
    }

    /// The slow return, all 21 reports of it. The stick creeps back through the
    /// band a report every 25ms and then drops to a hard zero; the answer is
    /// still one east, and the wobble on the way down must not produce a second
    /// aim or an early commit.
    func testTheSlowReturnTraceStillCommitsEastOnce() {
        var aim = RadialAim()
        var events: [RadialAim.Event] = []
        for (angle, distance) in [
            (0.049188, 0.009606), (0.009150, 0.728566), (0.007961, 1.0),
            (0.006833, 0.981531), (0.007496, 1.0), (0.006943, 0.989618),
            (0.007339, 0.976518), (0.007900, 0.941045), (0.019703, 0.272560),
            (0.018831, 0.254323), (0.022487, 0.225437), (0.024453, 0.197103),
            (0.021541, 0.183353), (0.025660, 0.172521), (0.023376, 0.182780),
            (0.026863, 0.174127), (0.025671, 0.154479), (0.028436, 0.148461),
            (0.026115, 0.134829), (0.0, 0.0),
        ] {
            events += aim.update(angle: angle, distance: distance)
        }
        XCTAssertEqual(events, [.wake, .aim(.east), .commit(.east)])
    }

    // MARK: - Cancel

    /// South is the cancel slice. The model still reports it as a commit like
    /// any other direction — what a direction *means* belongs to the menu, not
    /// to the geometry — so this is really a check that nothing special-cases
    /// it down here.
    func testSouthCommitsLikeAnyOtherDirection() {
        var aim = RadialAim()
        _ = aim.update(angle: 0.75, distance: 1)
        XCTAssertEqual(aim.update(angle: 0, distance: 0), [.commit(.south)])
    }

    // MARK: - Which way round the pad is

    /// Zero is east on this pad, as documented, but the angle climbs
    /// **clockwise**, which the documentation has the other way round. So a push
    /// straight up reports about 0.75 and has to come back as north. East and west
    /// are the same either way, which is why the error appeared as north and south
    /// swapped and nothing else.
    func testTheCorrectionFlipsThePadsClockwiseAngle() {
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0)), .east)
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.5)), .west)
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.75)), .north)
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.25)), .south)
    }

    /// The diagonals go with them: the pad's 0.125 is physically south-east, so
    /// the vendor's own `KC_P7` sitting at that angle is not the NE key its name
    /// suggests. Nothing here depends on those names, but the next person to read
    /// the sector table will assume they line up.
    func testTheCorrectionFlipsTheDiagonalsToo() {
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.125)), .southEast)
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.375)), .southWest)
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.625)), .northWest)
        XCTAssertEqual(RadialAim.Direction(angle: RadialAim.compassTurns(0.875)), .northEast)
    }

    /// The correction stays inside one turn whatever it is handed, including the
    /// angles that wrap past a full turn once shifted.
    func testTheCorrectionStaysWithinOneTurn() {
        for reported in stride(from: 0.0, through: 1.0, by: 0.05) {
            let turns = RadialAim.compassTurns(reported)
            XCTAssertGreaterThanOrEqual(turns, 0)
            XCTAssertLessThan(turns, 1)
        }
    }
}
