import Foundation

/// The two-press guard on key 7.
///
/// Closing a Herdr tab kills whatever is running in it, including an agent
/// mid-turn, and a pad key is one unguarded press away at all times. So the
/// first press only arms: the underglow goes solid red and nothing is sent to
/// Herdr. A second press of the same key inside `window` closes the tab.
///
/// Everything about *when* the arm ends lives here, as a value with no clock and
/// no network of its own, because these are the rules that have to be exhaustive:
/// an arm that outlives its window, or a cancel that fails to cancel, closes
/// work nobody asked to close.
public struct CloseTabArm: Sendable, Equatable {

    /// What the caller should do with a press.
    public enum Outcome: Sendable, Equatable {
        /// Light the pad and wait. Nothing reaches Herdr.
        case arm
        /// Close the focused tab.
        case confirm
        /// The arm is over and nothing is closed. `swallow` says whether the
        /// press itself is consumed: Esc cancels and must *not* also reach the
        /// terminal, since an Esc posted into an agent mid-turn is its own kind
        /// of damage. Every other key cancels and still does its own job.
        case cancel(swallow: Bool)
        /// Nothing was armed; the press is none of this type's business.
        case pass
    }

    /// How long an arm lasts. Long enough to be a deliberate second press,
    /// short enough that the underglow — which is also how you read whether an
    /// agent needs you — is not held hostage.
    public static let window: TimeInterval = 5

    private var armedAt: Date?

    public init() {}

    public func isArmed(at now: Date) -> Bool {
        guard let armedAt else { return false }
        return now.timeIntervalSince(armedAt) <= Self.window
    }

    /// Routes one key press. Call this for *every* key, armed or not: keys that
    /// are nothing to do with closing a tab are exactly how an arm gets
    /// cancelled.
    public mutating func press(key: Int, now: Date) -> Outcome {
        let wasArmed = isArmed(at: now)
        armedAt = nil

        if key == Pad.closeTabKeyID {
            // An expired arm re-arms rather than confirming, so the two presses
            // that close a tab are always the two presses you just made.
            if wasArmed { return .confirm }
            armedAt = now
            return .arm
        }
        guard wasArmed else { return .pass }
        // Several of these move Herdr's focus — arm, press an agent key, and a
        // confirm would close a tab you never armed.
        return .cancel(swallow: key == Pad.escKeyID)
    }

    /// Drops an arm whose window has passed. Returns whether that changed
    /// anything, which is the one transition worth a repaint: the ring has to
    /// give itself back without a press.
    public mutating func expire(now: Date) -> Bool {
        guard armedAt != nil, !isArmed(at: now) else { return false }
        armedAt = nil
        return true
    }
}
