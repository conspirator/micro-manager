import Foundation

/// The joystick's radial stream, turned into a menu selection.
///
/// The pad pushes `v.oai.rad` as `{a, d}` — an angle as a fraction of a turn
/// with 0 east and climbing counter-clockwise, and a distance from centre of 0
/// to 1. This turns that into four events: the menu waking, the aim moving
/// between slices, a selection committing, and the menu going away unused.
///
/// Two measured facts decide the whole design, both from the Inspector:
///
///   * **The pad reports on change.** Held hard against its stop it sent
///     nothing for 1.13s. So a gap in the stream means "unchanged", never
///     "released", and no timeout may stand in for a release — a 200ms silence
///     is a finger holding still, and committing under it would fire a
///     selection nobody finished making.
///   * **Release is reported exactly.** The stick coming back always lands a
///     clean `{"a":0,"d":0}`, 60ms after the last moving sample. So the release
///     is a real event and commit-on-release needs no cleverness at all.
///
/// Which is also why the centre cannot mean cancel: a stick held at centre and
/// a stick the spring returned are the same reading, and the hold is silent.
/// Cancel is a slice like any other — south, by choice — and this type is
/// deliberately ignorant of that. What a direction *means* belongs to the menu.
public struct RadialAim: Sendable {

    /// How far out the stick must go before it is pointing at anything.
    /// Below this the angle is noise: at a light touch the pad reported
    /// `a: 0.0299` with `d: 0.12`, an east nobody aimed at.
    public static let engage = 0.40

    /// What counts as back at centre. The pad's resting report is a hard zero
    /// on both fields, so this is a floor against float dust rather than a
    /// deadzone — a real deadzone here would make a slow release ambiguous,
    /// since the stick creeps back through 0.13 before dropping to 0.
    public static let rest = 0.005

    /// Where the pad's zero physically points, in turns, and which way its angle
    /// climbs.
    ///
    /// `docs/hacking.md`, from the vendor SDK, says "0 is east and the angle
    /// increases counter-clockwise". Half of that is true on this pad: zero is
    /// east — a hard right push reports `a` a hair above zero — but the angle
    /// climbs **clockwise**, so a push straight up reports about 0.75 rather than
    /// 0.25. East and west are unaffected, which is why the error shows up as
    /// north and south being swapped and nothing else.
    ///
    /// That is the second documented rotation direction in this repo to be
    /// backwards on the hardware; the dial's `[clockwise, counter-clockwise]`
    /// encoder order was the other way round too.
    ///
    /// One earlier mistake is worth keeping here, because it cost a rebuild: the
    /// indicator also appeared opposite the stick when the needle was rotating
    /// about the wrong anchor and drawing at twice the angle. Doubling puts a push
    /// left on the right and a push down-and-left at the top, which reads exactly
    /// like a half-turn offset. Two indicators disagreeing means one of them is
    /// drawn wrong, not that the device is.
    ///
    /// Correcting here keeps one convention downstream: sector names, labels and
    /// drawing all read the corrected angle, and only these two numbers know the
    /// pad's own.
    public static let zeroOffsetTurns = 0.0
    /// +1 if the pad's angle climbs counter-clockwise, -1 if it climbs clockwise.
    /// This pad climbs clockwise, measured by pushing the stick up and reading
    /// 0.75 off the panel.
    public static let handedness = -1.0

    /// A reported angle, mapped onto the compass this app draws: 0 east,
    /// climbing counter-clockwise.
    public static func compassTurns(_ reported: Double) -> Double {
        let turns = reported * handedness + zeroOffsetTurns
        return turns - floor(turns)
    }

    public enum Direction: Int, CaseIterable, Sendable {
        case east, northEast, north, northWest, west, southWest, south, southEast

        /// The sector an angle falls in. Eight sectors, centred on multiples of
        /// an eighth of a turn, named for where they physically are: this takes a
        /// **corrected** angle, so `.north` is the slice you get by pushing the
        /// stick up. See `compassTurns` for what the pad reports instead.
        ///
        /// `rounded()` is what handles the sector that wraps through zero: 0.97
        /// of a turn rounds to 8 eighths, and `% 8` brings it home to east.
        public init(angle: Double) {
            let turns = angle - floor(angle)
            let sector = Int((turns * 8).rounded()) % 8
            self = Direction(rawValue: sector) ?? .east
        }

        /// Where the slice sits, as a fraction of a turn.
        public var centreTurns: Double { Double(rawValue) / 8 }

        /// Compass names, because that is what the pad's geometry gives us.
        /// What each slice *does* is the menu's business.
        public var label: String {
            switch self {
            case .east: return "E"
            case .northEast: return "NE"
            case .north: return "N"
            case .northWest: return "NW"
            case .west: return "W"
            case .southWest: return "SW"
            case .south: return "S"
            case .southEast: return "SE"
            }
        }
    }

    public enum Event: Equatable, Sendable {
        /// The stick was touched. Put the menu up: this arrives before any
        /// direction is chosen, which is the difference between a menu and a
        /// receipt.
        case wake
        /// The aim moved to a slice, or arrived at its first one.
        case aim(Direction)
        /// Released while aiming. This is the selection.
        case commit(Direction)
        /// Released without ever aiming. Take the menu away; nothing was
        /// chosen.
        case sleep
    }

    private enum State: Equatable {
        case idle
        /// Touched, but not pushed far enough to point at anything.
        case awake
        case aiming(Direction)
    }

    private var state: State = .idle

    public init() {}

    /// The slice the stick is pointing at, if it is out past `engage`.
    public var aimed: Direction? {
        if case .aiming(let direction) = state { return direction }
        return nil
    }

    /// Whether the menu should be on screen.
    public var isAwake: Bool { state != .idle }

    /// Feeds one report in. Returns the events it caused, in order: a single
    /// report can both wake the menu and aim it, because a fast flick's first
    /// report can already be at full deflection.
    public mutating func update(angle: Double, distance: Double) -> [Event] {
        switch state {
        case .idle:
            guard distance > Self.rest else { return [] }
            state = .awake
            return [.wake] + engageIfPushed(angle: angle, distance: distance)

        case .awake:
            guard distance > Self.rest else {
                state = .idle
                return [.sleep]
            }
            return engageIfPushed(angle: angle, distance: distance)

        case .aiming(let current):
            guard distance > Self.rest else {
                state = .idle
                return [.commit(current)]
            }
            // Between the thresholds nothing happens: a release passes through
            // `d: 0.32` on its way down, and re-aiming at the angle it happens
            // to report there would change the answer as the stick comes home.
            guard distance >= Self.engage else { return [] }
            let direction = Direction(angle: angle)
            guard direction != current else { return [] }
            state = .aiming(direction)
            return [.aim(direction)]
        }
    }

    private mutating func engageIfPushed(angle: Double, distance: Double) -> [Event] {
        guard distance >= Self.engage else { return [] }
        let direction = Direction(angle: angle)
        state = .aiming(direction)
        return [.aim(direction)]
    }
}
