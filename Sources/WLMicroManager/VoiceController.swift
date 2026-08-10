import AppKit
import WLKit

/// The voice key: taps **right control**, which is Monologue's dictation
/// hotkey.
///
/// Monologue is system-wide and types into whatever holds focus, so this
/// deliberately does not care which agent Herdr has focused, or whether Herdr
/// is running at all.
///
/// Start and stop are *different gestures*, which is why this holds state.
/// From Monologue's own `HOTKEY_RECORDING_BEHAVIOR.md`, and the state machine
/// its binary logs (`idle -> pressAndHold -> doubleTapLock -> idle`):
///
///   - two taps inside its 1s window cancel the buffered stop and hold the
///     session open — hands-free, and the only way to *start* a take from a
///     single keypress;
///   - one more tap while locked ends the recording;
///   - a lone tap from idle, with no second tap, is discarded in silence: no
///     transcript, no error.
///
/// So a press sends two taps when no take is open and one when a take is. The
/// state drifts if you stop a take from the keyboard instead, and it heals in
/// one press: the stray single tap is the case Monologue throws away quietly,
/// and the press after it starts a recording properly.
@MainActor
final class VoiceController {

    static let shared = VoiceController()

    /// Mirrors an open take, for the key light.
    var onActiveChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private var takeOpen = false

    func handleVoiceKey() {
        // Two taps start and lock a recording; one tap stops the locked one.
        let tap: SystemKeyTap = takeOpen ? .rightControl : .rightControlDouble
        takeOpen.toggle()
        onActiveChange?(takeOpen)
        Task { [weak self] in
            do {
                try await tap.post()
            } catch {
                // The press never happened, so the light must not claim a take.
                self?.takeOpen = false
                self?.onActiveChange?(false)
                self?.onError?(error.localizedDescription)
            }
        }
    }
}
