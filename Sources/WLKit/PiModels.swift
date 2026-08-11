import Foundation

/// The dial's model picker for pi panes: read pi's own list, show it, and walk
/// it with the one chord we can trust to arrive.
///
/// Split the way `OpenWith` is, and for the same reason: what to offer, what to
/// refuse, where the highlight goes and how many presses reach it are all pure,
/// so every outcome is testable without a Herdr socket, without a device, and
/// without a pi running on the machine the tests run on.
///
/// Three facts about pi shape everything here, all of them read out of
/// `pi-coding-agent` rather than assumed:
///
///   - **`ctrl+p` walks `enabledModels`, in file order, wrapping.** At startup
///     `main.js` resolves that array into the session's scoped models, and
///     `_cycleScopedModel` steps through it. So the list and its order are
///     already written down; the pad must not keep a second copy.
///   - **Writing `settings.json` would not switch a running pane.**
///     `defaultModel` is read once, at startup, and nothing watches the file.
///     The only way into a live session is its input.
///   - **`cycleModel` is async and unserialised.** It awaits an auth check for
///     every scoped model before applying the change, so two chords delivered
///     together can both read the same current model and land one step short.
///     Hence `advance`: one press, then confirmation, then the next.
///
/// Backward (`shift+ctrl+p`) is deliberately unused. Pi can tell it apart —
/// `pi-tui` negotiates the Kitty keyboard protocol and falls back to
/// `modifyOtherKeys` — but whether Herdr encodes the shift on its way in is
/// unverified, and wrapping forward reaches every model regardless.
public enum PiModels {

    /// One entry of `enabledModels`, already split. `id` is what pi prints in
    /// its footer, which is the only part we can read back off a pane.
    public struct Entry: Equatable, Sendable {
        public let provider: String
        public let id: String

        public init(provider: String, id: String) {
            self.provider = provider
            self.id = id
        }

        /// The canonical `provider/id` pi would accept, or the bare id when the
        /// entry carried no provider.
        public var reference: String { provider.isEmpty ? id : "\(provider)/\(id)" }
    }

    /// Whether a turn opens a panel, and if not, what to say about it.
    ///
    /// A refusal is a value rather than silence, exactly as in `OpenWith`:
    /// nothing appears on screen, but the reason reaches the menu panel, so a
    /// dial that is dead for a real reason can be told from a dial with nothing
    /// to offer.
    public enum Start: Equatable, Sendable {
        case show(Picker)
        case refuse(String)
    }

    /// What the panel is showing. `current` is where pi says it is, and is nil
    /// when pi is on something outside the list — a pane started with `--model`.
    /// The highlight still moves in that case; only committing is impossible.
    public struct Picker: Equatable, Sendable {
        public let entries: [Entry]
        public let current: Int?
        public private(set) var selection: Int

        public init(entries: [Entry], current: Int?) {
            precondition(!entries.isEmpty, "a picker with nothing in it is a refusal, not a window")
            self.entries = entries
            self.current = current
            self.selection = current ?? 0
        }

        public var selected: Entry { entries[selection] }

        /// Moves the highlight by `step` detents, wrapping. Detents are never
        /// accumulated into anything: they move this, and the distance is worked
        /// out at commit time from what pi actually reports.
        public mutating func move(_ step: Int) {
            let count = entries.count
            let next = (selection + step) % count
            selection = next < 0 ? next + count : next
        }

        /// Forward presses of `ctrl+p` from where pi is to the highlight, or nil
        /// when there is no known position to count from.
        public var steps: Int? {
            guard let current else { return nil }
            return (selection - current + entries.count) % entries.count
        }
    }

    /// Where pi keeps its settings. `PI_CODING_AGENT_DIR` is pi's own override
    /// (`config.js`), honoured for symmetry — though a login-item launch never
    /// sees your shell environment, so in practice the default is what runs.
    public static func settingsPath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let directory = environment["PI_CODING_AGENT_DIR"].flatMap { value -> String? in
            value.isEmpty ? nil : (value as NSString).expandingTildeInPath
        }
        let base = directory ?? (("~/.pi/agent" as NSString).expandingTildeInPath)
        return (base as NSString).appendingPathComponent("settings.json")
    }

    /// Pi's thinking suffixes, which decorate an entry without changing how many
    /// presses reach it.
    private static let thinkingLevels: Set<String> = [
        "off", "minimal", "low", "medium", "high", "xhigh", "max",
    ]

    /// `enabledModels` in file order. Anything that is not a string is dropped;
    /// glob patterns are kept, because refusing them is `start`'s job and the
    /// message needs to name the pattern.
    public static func enabledModels(in settings: [String: Any]) -> [Entry] {
        guard let patterns = settings["enabledModels"] as? [String] else { return [] }
        return patterns.compactMap { pattern in
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            var body = trimmed
            if let colon = body.lastIndex(of: ":"),
               thinkingLevels.contains(String(body[body.index(after: colon)...]).lowercased()) {
                body = String(body[body.startIndex..<colon])
            }
            guard let slash = body.firstIndex(of: "/") else {
                return Entry(provider: "", id: body)
            }
            return Entry(
                provider: String(body[body.startIndex..<slash]),
                id: String(body[body.index(after: slash)...])
            )
        }
    }

    /// The whole decision, with no I/O in it.
    public static func start(entries: [Entry], paneText: String?) -> Start {
        guard entries.count > 1 else {
            return .refuse(
                "Pi needs at least two models in enabledModels for the dial to pick between them."
            )
        }
        if let glob = entries.first(where: { $0.reference.contains(where: isGlob) }) {
            return .refuse(
                "enabledModels contains the pattern \(glob.reference), which pi expands to as many "
                + "models as it matches. The dial cannot count presses through a glob."
            )
        }
        var seen = Set<String>()
        for entry in entries where !seen.insert(entry.id).inserted {
            return .refuse(
                "Two enabled models are both called \(entry.id), so pi's footer cannot say which "
                + "one it is on."
            )
        }
        return .show(
            Picker(entries: entries, current: currentIndex(paneText: paneText ?? "", entries: entries))
        )
    }

    private static func isGlob(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    /// Which entry pi's footer names, or nil.
    ///
    /// Pi prints `(provider) id • thinking` on the right of its stats line, drops
    /// the provider when only one is available, and truncates the whole side in a
    /// narrow pane — so the id is the only part worth matching. The last mention
    /// wins, because the footer is at the bottom and the scrollback above it is
    /// full of models being discussed rather than used.
    public static func currentIndex(paneText: String, entries: [Entry]) -> Int? {
        var found: Int?
        for line in paneText.split(separator: "\n", omittingEmptySubsequences: false) {
            let tokens = line.split(whereSeparator: isSeparator)
            for token in tokens {
                if let index = entries.firstIndex(where: { $0.id == token }) { found = index }
            }
        }
        return found
    }

    /// Whitespace and pi's own furniture. Splitting on these is what makes the
    /// match whole-token, so `claude` cannot answer for `claude-5`.
    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || "()•|,".contains(character)
    }

    // MARK: - Committing

    public enum Advance: Equatable, Sendable {
        case landed
        case failed(String)
    }

    /// Walks pi to the highlighted model, one chord at a time, confirming each
    /// step against the pane before sending the next.
    ///
    /// Not a burst: `cycleModel` is async and unserialised inside pi, so several
    /// chords arriving together can be collapsed into one change, and the pad
    /// would report success one model short. Every step is therefore read back,
    /// and anything unexpected — a press that moves nothing, a jump past the
    /// target — stops the walk and is described rather than swallowed.
    ///
    /// `send`, `read` and `pause` are injected so the interesting failures can be
    /// tested without a pane: pi is the one deciding whether a press landed.
    public static func advance(
        _ picker: Picker,
        send: () async throws -> Void,
        read: () async throws -> String,
        pause: () async -> Void,
        pollsPerStep: Int = 8
    ) async -> Advance {
        guard var position = picker.current else {
            return .failed("Could not tell which model pi is on, so there is nothing to count from.")
        }
        let target = picker.selection
        let limit = picker.entries.count - 1
        var sent = 0

        while position != target {
            guard sent < limit else {
                return .failed(
                    "Pi stopped at \(picker.entries[position].id) after \(sent) presses instead of "
                    + "reaching \(picker.entries[target].id)."
                )
            }
            do {
                try await send()
                sent += 1
                var moved: Int?
                for _ in 0..<pollsPerStep {
                    await pause()
                    let text = try await read()
                    if let now = currentIndex(paneText: text, entries: picker.entries),
                       now != position {
                        moved = now
                        break
                    }
                }
                guard let now = moved else {
                    return .failed(
                        "Pi did not move off \(picker.entries[position].id) after a ctrl+p."
                    )
                }
                position = now
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        return .landed
    }
}
