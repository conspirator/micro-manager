import AppKit
import CoreAudio
import Foundation
import IOKit.hidsystem

#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// The dial as a volume knob: a turn steps the Mac's output volume, and a press
/// toggles mute.
///
/// Every step goes through the media keys, so macOS picks the step size and shows
/// its own volume indicator. Posting them needs the **Accessibility** grant, the
/// same one `SystemKeyTap` needs.
public enum SystemVolume {

    /// One thing a dial event does to the system volume, in order.
    public enum Action: Equatable, Sendable {
        case unmute
        case raise
        case lower
    }

    /// The actions for one detent. `step` is +1 for clockwise and -1 for
    /// counter-clockwise.
    ///
    /// A muted turn clears the mute itself. The volume-down key changes the level
    /// and leaves the Mac muted, so a left turn would otherwise be silent.
    public static func actions(forTurn step: Int, muted: Bool) -> [Action] {
        guard step != 0 else { return [] }
        return (muted ? [.unmute] : []) + [step > 0 ? .raise : .lower]
    }

    /// Steps the volume one detent, and unmutes first when the output is muted.
    @MainActor
    public static func turn(_ step: Int) throws {
        try requireAccessibility()
        for action in actions(forTurn: step, muted: isOutputMuted()) {
            switch action {
            case .unmute: setOutputMuted(false)
            case .raise: MediaKey.volumeUp.press()
            case .lower: MediaKey.volumeDown.press()
            }
        }
    }

    /// Toggles mute the way the keyboard's mute key does.
    @MainActor
    public static func toggleMute() throws {
        try requireAccessibility()
        MediaKey.mute.press()
    }

    // MARK: - Media keys

    /// A key from the keyboard's media row, posted as a system-defined event.
    enum MediaKey {
        case volumeUp
        case volumeDown
        case mute

        var keyType: Int32 {
            switch self {
            case .volumeUp: return NX_KEYTYPE_SOUND_UP
            case .volumeDown: return NX_KEYTYPE_SOUND_DOWN
            case .mute: return NX_KEYTYPE_MUTE
            }
        }

        /// The event's `data1`: the key type in bits 16 to 31, and the state in
        /// bits 8 to 15, where `0x0A` is down and `0x0B` is up.
        func data1(down: Bool) -> Int {
            Int(keyType) << 16 | (down ? 0x0A00 : 0x0B00)
        }

        func press() {
            for down in [true, false] {
                // Subtype 8 is `NX_SUBTYPE_AUX_CONTROL_BUTTONS`. The modifier
                // flags repeat the key state, as a real media key sets them.
                NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0x0A00 : 0x0B00),
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: data1(down: down),
                    data2: -1
                )?.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Mute state

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    /// False when the output device has no mute control. The volume keys still
    /// work on such a device, so a turn must not fail there.
    private static func isOutputMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    private static func setOutputMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    // MARK: - Permission

    private static func requireAccessibility() throws {
        #if canImport(ApplicationServices)
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) else {
            throw SystemKeyTap.Failure.accessibilityDenied
        }
        #endif
    }
}
