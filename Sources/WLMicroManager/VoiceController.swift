import AppKit
import WLKit

/// The voice key: taps **right control**, which is bound to VoiceInk's
/// primary recording shortcut in its Hybrid mode.
///
/// VoiceInk types into whatever holds focus, so this does not care which agent
/// Herdr has focused, or whether Herdr is running at all.
///
/// A press sends two taps when no take is open and one when a take is. In
/// Hybrid mode a short tap starts a hands-free take and the next tap stops it.
/// VoiceInk ignores a press within 0.5s of the previous one, so the second tap
/// of the pair is dropped and the pair starts the take.
///
/// `takeOpen` only mirrors this key's presses. If you stop a take from the
/// keyboard, the light stays red and the next press sends one tap, which
/// starts a take. Press once more to stop it.
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
