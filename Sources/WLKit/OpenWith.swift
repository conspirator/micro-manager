import AppKit
import Foundation

/// The picker on key 6: opens the focused agent's working directory in Finder,
/// Zed or Tower.
///
/// Split the way `Tower.swift` is, and for the same reasons. The decision — what
/// to offer, what to refuse, where the selection goes — is pure, so every
/// outcome is testable without `NSWorkspace`, without a Herdr socket, and
/// without depending on which of the three apps the test machine has installed.
/// Only `launch` touches the system.
///
/// Opening goes through `NSWorkspace` rather than a CLI (`open`, `zed`,
/// `gittower`) because a GUI-launched app inherits
/// `/usr/bin:/bin:/usr/sbin:/sbin`, so the binaries your terminal finds
/// instantly are invisible here. `GitButler.swift` carries a whole search of
/// Homebrew, Cargo and the login shell to work around exactly that for `but`.
public enum OpenWith {

    /// The apps the strip offers, in the order it shows them.
    ///
    /// `all` is the only place that order is written down, and the order is the
    /// gesture: "6, right, Enter" means Zed for exactly as long as this reads
    /// Finder, Zed, Tower.
    public enum App: String, Sendable, CaseIterable {
        case finder
        case zed
        case tower

        public static let all: [App] = [.finder, .zed, .tower]

        public var bundleID: String {
            switch self {
            case .finder: return "com.apple.finder"
            case .zed: return "dev.zed.Zed"
            case .tower: return "com.fournova.Tower3"
            }
        }

        public var displayName: String {
            switch self {
            case .finder: return "Finder"
            case .zed: return "Zed"
            case .tower: return "Tower"
            }
        }
    }

    /// An app that is actually installed, with the URL of its bundle. Only
    /// these reach the strip: an icon you can select but not launch is a key
    /// press that fails for no visible reason.
    public struct Choice: Equatable, Sendable {
        public let app: App
        public let url: URL

        public init(app: App, url: URL) {
            self.app = app
            self.url = url
        }
    }

    public enum Direction: Sendable {
        case left
        case right
    }

    /// What the strip is showing. `selection` indexes `choices`, never `App.all`
    /// — with Zed uninstalled, position 1 is Tower in one list and Zed in the
    /// other — and `choices` is never empty, which is what lets `selected` be
    /// non-optional.
    public struct Strip: Equatable, Sendable {
        public let directory: URL
        public let choices: [Choice]
        public private(set) var selection: Int

        init(directory: URL, choices: [Choice]) {
            precondition(!choices.isEmpty, "a strip with nothing in it is a refusal, not a window")
            self.directory = directory
            self.choices = choices
            self.selection = 0
        }

        public var selected: Choice { choices[selection] }

        /// Wraps at both ends, as the macOS app switcher does. With three icons
        /// that is worth having: one Left from Finder reaches Tower, where two
        /// Rights would.
        public mutating func move(_ direction: Direction) {
            let count = choices.count
            switch direction {
            case .left: selection = (selection + count - 1) % count
            case .right: selection = (selection + 1) % count
            }
        }
    }

    /// Whether a press opens the strip, and if not, what to say about it.
    ///
    /// A refusal is a value rather than silence. Nothing appears on screen for
    /// it — an empty Herdr does not deserve a dialog — but it reaches
    /// `noteError`, so a key 6 that looks dead for a real reason can still be
    /// told apart from a key 6 with nothing to open.
    public enum Start: Equatable, Sendable {
        case show(Strip)
        case refuse(String)
    }

    /// The whole decision, with no I/O in it. `locate` is injected so tests do
    /// not depend on the machine they run on.
    ///
    /// The two failure strings are the Tower key's own words: one fault must not
    /// get two descriptions depending on which key you pressed.
    public static func start(agent: HerdrAgent?, locate: (App) -> URL?) -> Start {
        guard let agent else { return .refuse("Nothing has focus in Herdr right now.") }
        guard let directory = agent.workingDirectory else {
            return .refuse("Herdr did not report a working directory for this agent.")
        }
        let choices = App.all.compactMap { app in
            locate(app).map { Choice(app: app, url: $0) }
        }
        guard !choices.isEmpty else {
            return .refuse("Finder, Zed and Tower are all missing.")
        }
        return .show(Strip(directory: URL(fileURLWithPath: directory), choices: choices))
    }

    /// Where an installed app lives, or nil. The default `locate` for the app;
    /// tests pass their own.
    public static func locate(_ app: App) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
    }

    // MARK: - Keys

    /// The strip reads its keys through `PanelKey`, which every focus-taking
    /// panel here shares. It uses the horizontal axis and swallows the vertical
    /// one.
    public typealias Key = PanelKey

    // MARK: - Launching

    /// Opens `directory` in `choice`, bringing that app forward. The only part
    /// of this file that touches the system.
    ///
    /// This failure is not silent, unlike a refusal: you asked for something
    /// specific and it did not happen.
    public static func launch(
        _ choice: Choice,
        directory: URL,
        onError: @escaping (String) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: choice.url,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                onError("Could not open \(choice.app.displayName): \(error.localizedDescription)")
            }
        }
    }
}
