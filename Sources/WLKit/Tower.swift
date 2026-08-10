import AppKit
import Foundation

/// Opens the focused agent's working directory in Tower.
///
/// Tower is asked to open the directory through `NSWorkspace` rather than by
/// running `gittower`, and not only to save a process. A GUI-launched app
/// inherits `/usr/bin:/bin:/usr/sbin:/sbin`, so `/usr/local/bin/gittower` — the
/// binary your terminal finds instantly — is invisible here. `GitButler.swift`
/// carries a whole search of Homebrew, Cargo and the login shell to work around
/// exactly that for `but`. `NSWorkspace` needs no PATH, no shell, and no CLI
/// installed, and it brings Tower forward as part of opening it.
public enum Tower {

    public static let bundleID = "com.fournova.Tower3"

    /// What a press resolves to. The failures are values rather than silence:
    /// a key that does nothing at all cannot be told from a dead key, which is
    /// a fault this pad has already shown once.
    public enum Target: Equatable {
        case open(directory: URL, tower: URL)
        case problem(String)
    }

    /// Where Tower is, or nil when it is not installed — so the key reports
    /// rather than assumes, the way the Inspector button does.
    public static var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The whole decision, with no I/O in it, so every message it can produce is
    /// testable without Tower installed and without a Herdr socket.
    ///
    /// A missing Tower is reported ahead of everything else: it is true whatever
    /// has focus, and "nothing has focus" would send you looking at Herdr
    /// instead of at the app that is not there.
    public static func target(agent: HerdrAgent?, towerURL: URL?) -> Target {
        guard let towerURL else { return .problem("Tower is not installed.") }
        guard let agent else { return .problem("Nothing has focus in Herdr right now.") }
        guard let directory = agent.workingDirectory else {
            return .problem("Herdr did not report a working directory for this agent.")
        }
        return .open(directory: URL(fileURLWithPath: directory), tower: towerURL)
    }

    /// Asks Herdr what has focus and opens that directory in Tower. Every way
    /// this can fail goes to `onError`, which is where the bridge's own errors
    /// already surface in the menu panel.
    public static func launch(onError: @escaping (String) -> Void) {
        Task {
            let agent: HerdrAgent?
            do {
                agent = try await HerdrClient.focusedAgent()
            } catch {
                onError(error.localizedDescription)
                return
            }

            switch target(agent: agent, towerURL: url) {
            case .problem(let message):
                onError(message)
            case .open(let directory, let tower):
                open(directory, in: tower, onError: onError)
            }
        }
    }

    private static func open(
        _ directory: URL,
        in tower: URL,
        onError: @escaping (String) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: tower,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                onError("Could not open Tower: \(error.localizedDescription)")
            }
        }
    }
}
