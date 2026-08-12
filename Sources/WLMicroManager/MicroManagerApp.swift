import SwiftUI
import AppKit
import WLKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no app-switcher entry. The bundled app
        // also sets LSUIElement; this covers `swift run` during development.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@main
struct MicroManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var bridge = BridgeController()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(bridge)
                .task {
                    // Key 6 puts up the open-with strip, which is a window the
                    // bridge knows nothing about, so the two are joined here.
                    let openWith = OpenWithPanelController.shared
                    openWith.onVisibilityChange = { [weak bridge] open in
                        Task { await bridge?.setOpenWithPanelOpen(open) }
                    }
                    openWith.onError = { [weak bridge] message in
                        bridge?.noteError(message)
                    }
                    bridge.onOpenWithKey = { openWith.handleKey() }

                    // Key 7 closes a Herdr tab and needs nothing from the app:
                    // the bridge owns both presses and the light between them.
                    // Tower, which used to own the key, is still in the repo and
                    // still on key 6's picker.

                    let voice = VoiceController.shared
                    voice.onActiveChange = { [weak bridge] active in
                        Task { await bridge?.setVoiceActive(active) }
                    }
                    voice.onError = { [weak bridge] message in
                        bridge?.noteError(message)
                    }
                    bridge.onVoiceKey = { voice.handleVoiceKey() }

                    // Esc and Enter. The bridge decides which key means what;
                    // posting the event is the app's job, since it holds the
                    // Accessibility grant.
                    bridge.onSystemKey = { [weak bridge] tap in
                        Task {
                            do {
                                try await tap.post()
                            } catch {
                                bridge?.noteError(error.localizedDescription)
                            }
                        }
                    }

                    let tune = TuneController.shared
                    tune.onError = { [weak bridge] message in
                        bridge?.noteError(message)
                    }
                    tune.bindings = { [weak bridge] in
                        bridge?.keyBindings ?? KeyBindings()
                    }
                    bridge.onDial = { step in tune.handleDial(step) }
                    bridge.onDialPress = { tune.handleDialPress() }
                    // The joystick drives the radial menu, reading its whole
                    // position rather than four bound sectors.
                    // `tune.handleJoystick` and the model cycling behind it are
                    // intact and tested, just unwired — and on this pad they
                    // were dead anyway: its keymap reports the joystick as
                    // `type: VENDOR` with no sectors, so AG15–AG18 were never
                    // bound and no deflection ever reached them.
                    bridge.onAim = { angle, distance in
                        RadialMenuController.shared.handle(angle: angle, distance: distance)
                    }
                    PiModelPanelController.shared.onError = { [weak bridge] message in
                        bridge?.noteError(message)
                    }

                    // Choose the transport before starting: `useEmulator`
                    // rebuilds the device, so doing it after would tear down a
                    // connection we just made.
                    await bridge.useEmulator(BridgeSettings.emulate)

                    // Come back up in whatever state it was left in, so a
                    // login-item launch resumes rather than sitting idle.
                    // Defaults to on for a first run.
                    if BridgeSettings.enabled, !bridge.isRunning {
                        await bridge.start()
                    }
                }
        } label: {
            Image(nsImage: MenuBarIcon.image(for: MenuBarIcon.State.from(bridge)))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Persisted across launches.
enum BridgeSettings {
    private static let key = "bridgeEnabled"

    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private static let emulateKey = "emulatePad"

    /// Drive a virtual pad instead of the hardware. `WL_EMULATE=1` forces it on
    /// for a single run, which is what makes `swift run` useful with no device
    /// plugged in.
    static var emulate: Bool {
        get {
            if ProcessInfo.processInfo.environment["WL_EMULATE"] == "1" { return true }
            return UserDefaults.standard.bool(forKey: emulateKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: emulateKey) }
    }
}
