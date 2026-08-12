import CoreGraphics

/// A Raycast window layout, and the chord that asks for it.
///
/// The layouts themselves belong to Raycast. This app presses the same hotkeys
/// you press by hand, which is the point: there is one window manager on this
/// machine, and the pad cannot drift from what your fingers already know. There
/// is no library and no version to track here — the whole dependency is the five
/// key codes below, and if Raycast's hotkeys change you edit them.
///
/// The downside is worth writing down: nothing tells us whether Raycast acted.
/// If it is quit, or a hotkey is reassigned, the slice lights up as committed and
/// no window moves. That is the first thing to suspect when a slice appears to do
/// nothing.
public struct WindowLayout: Sendable, Equatable {

    /// Raycast's own name for the layout, which is also what the compass shows.
    public let name: String
    public let tap: SystemKeyTap

    /// ctrl+opt+cmd, plus **fn**.
    ///
    /// The fn bit is not decoration and its absence is invisible. Measured on
    /// this machine: ctrl+opt+cmd+left with plain modifier flags leaves the
    /// window exactly where it was and reports nothing, while the same chord with
    /// `.maskSecondaryFn` moves it. Raycast matches the flags a real press
    /// carries when you assign a hotkey, and every key here — the four arrows and
    /// Page Down — is a function key, so a real press always sets fn. A chord
    /// without it is one no keyboard could have produced, and Raycast discards
    /// it.
    ///
    /// Ruled out while finding that, so nobody re-tests them: the event source
    /// state (`.hidSystemState` and `.combinedSessionState` behave alike), the
    /// `numericPad` bit, the device-dependent left/right modifier bits, and
    /// posting `flagsChanged` events around the key rather than setting flags on
    /// the keydown.
    static let chord: CGEventFlags = [
        .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
    ]

    init(_ name: String, _ keyCode: CGKeyCode) {
        self.name = name
        self.tap = SystemKeyTap(keyCode: keyCode, flags: Self.chord)
    }

    /// The layout a slice of the radial menu asks for, or nil for a slice that
    /// does nothing.
    ///
    /// Three directions are deliberately nil. South is the menu's cancel — it has
    /// to be a slice rather than the centre, because a stick held at centre and
    /// a stick the spring returned read identically; see `RadialAim`. The two
    /// lower diagonals are simply unbound. The menu reads this table for its
    /// labels as well as its actions, so an unbound slice draws as one, and a
    /// slice cannot name one layout while pressing another.
    public static func forDirection(_ direction: RadialAim.Direction) -> WindowLayout? {
        switch direction {
        case .west: return WindowLayout("Left Half", 0x7B)          // left arrow
        case .east: return WindowLayout("Right Half", 0x7C)         // right arrow
        case .northWest: return WindowLayout("First Two Thirds", 0x7E)  // up arrow
        case .northEast: return WindowLayout("Last Two Thirds", 0x7D)   // down arrow
        case .north: return WindowLayout("Almost Maximize", 0x79)   // page down
        case .south, .southEast, .southWest: return nil
        }
    }
}
