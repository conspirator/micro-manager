import CoreGraphics
import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// A synthesised key press: what to press, how long to hold it, and how many
/// times.
///
/// Two details matter and both fail quietly.
///
///   1. A modifier carries its own flag, set on the way down and cleared on the
///      way up. Post a modifier without that and listeners see a key that never
///      releases, which leaves the whole machine holding it down.
///   2. The press has a length. Apps that tell a tap from a hold classify by
///      duration, so a down/up posted in the same instant is a different
///      gesture from one held for a moment — Monologue's threshold for "this is
///      a hold" is 0.4s, and the shell script this was ported from held for
///      30ms.
///
/// Posting needs the **Accessibility** grant, on top of the Input Monitoring
/// grant the pad itself needs. `post()` raises the system prompt the first time.
public struct SystemKeyTap: Sendable, Equatable {

    public var keyCode: CGKeyCode
    public var flags: CGEventFlags
    /// How long the key is held down, in seconds.
    public var hold: TimeInterval
    public var taps: Int
    /// The gap between the release of one tap and the press of the next.
    public var gap: TimeInterval

    public init(
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        hold: TimeInterval = 0.03,
        taps: Int = 1,
        gap: TimeInterval = 0.15
    ) {
        self.keyCode = keyCode
        self.flags = flags
        self.hold = hold
        self.taps = taps
        self.gap = gap
    }

    public static let escape = SystemKeyTap(keyCode: 0x35)
    public static let enter = SystemKeyTap(keyCode: 0x24)

    /// Right control. Its left twin is a different key code, and an app bound to
    /// one does not hear the other.
    public static let rightControl = SystemKeyTap(keyCode: 0x3E, flags: .maskControl)

    /// Two right-control taps 150ms apart, which is Monologue's hands-free
    /// lock: the second tap inside its 1s window cancels the buffered stop and
    /// keeps the recording open. A single tap with no partner is discarded in
    /// silence, so the two taps are what starts a take at all.
    public static let rightControlDouble = SystemKeyTap(
        keyCode: rightControl.keyCode,
        flags: rightControl.flags,
        taps: 2
    )

    /// The keys whose whole job is to be a keystroke. The voice key also posts
    /// events, but picks its gesture from whether a take is open, so it is not
    /// in this table.
    public static func forKey(_ id: Int) -> SystemKeyTap? {
        switch id {
        case Pad.escKeyID: return .escape
        case Pad.enterKeyID: return .enter
        default: return nil
        }
    }

    /// Posts the press. Async because the holds and gaps are real waits, and
    /// blocking the main thread for them would stall the UI mid-press.
    public func post() async throws {
        #if canImport(ApplicationServices)
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) else {
            throw Failure.accessibilityDenied
        }
        #endif

        let source = CGEventSource(stateID: .hidSystemState)
        for tap in 0..<max(taps, 1) {
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            else { throw Failure.eventFailed }

            down.flags = flags
            up.flags = []
            down.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            up.post(tap: .cghidEventTap)
            if tap < taps - 1 {
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
        }
    }

    public enum Failure: LocalizedError {
        case accessibilityDenied
        case eventFailed

        public var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                return "Pressing a key for you needs the Accessibility permission: "
                    + "System Settings → Privacy & Security → Accessibility → Micro Manager."
            case .eventFailed:
                return "Could not synthesise the key press."
            }
        }
    }
}
