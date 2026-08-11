import AppKit

/// What a key code means to a panel that has taken the keyboard.
///
/// Read from the key code rather than the characters: the arrow keys have no
/// sensible characters, and a layout that remaps letters must not move a
/// selection.
///
/// Unrecognised keys are `.ignore`, which a panel swallows so a stray letter
/// neither confirms anything nor beeps. Anything held with Command, Control or
/// Option is `.passThrough` instead: a panel has no business eating Cmd-Q or
/// Cmd-Tab just because it happens to be on screen.
///
/// Shared by the open-with strip, which reads left and right, and the model
/// picker, which reads up and down. A panel ignores the axis it does not use.
public enum PanelKey: Equatable, Sendable {
    case left
    case right
    case up
    case down
    case confirm
    case dismiss
    case ignore
    case passThrough

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        let held = modifiers.intersection(.deviceIndependentFlagsMask)
        if !held.isDisjoint(with: [.command, .control, .option]) {
            self = .passThrough
            return
        }
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        case 36, 76: self = .confirm   // Return, and the keypad's Enter
        case 53: self = .dismiss       // Esc
        default: self = .ignore
        }
    }
}
