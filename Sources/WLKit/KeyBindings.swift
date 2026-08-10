import Foundation

/// User-configurable text macros for the keys that have a rebindable role.
///
/// Read from `$XDG_CONFIG_HOME/micromanager/config.json`
/// (`~/.config/micromanager/config.json` by default):
///
///     {
///       "keys": {
///         "9": "Open PRs for all active GitButler branches",
///         "12": "Run but pull"
///       },
///       "claude": { "models": ["fable", "opus"], "efforts": ["low", "high"] },
///       "codex":  { "models": ["gpt-5.6-sol", "gpt-5.6-codex"] }
///     }
///
/// A bound string is injected into the focused agent's prompt, unsubmitted, in
/// place of what the key would otherwise do. Only `Pad.rebindableKeyIDs` are
/// listened to, and none of them has a default: every key on the pad now has a
/// role of its own, and a default string here would silently replace one.
public struct KeyBindings: Sendable, Equatable {

    public private(set) var texts: [Int: String]
    /// The models the joystick cycles through in Claude Code, in order.
    /// Overridable with a top-level `"claude": {"models": [...]}` object.
    public private(set) var claudeModels: [String]
    /// The effort ladder the dial climbs in Claude Code.
    public private(set) var claudeEfforts: [String]
    /// Codex's own `/model` menu, in the order it lists them, from a
    /// `"codex": {"models": [...]}` object. The joystick steers that menu
    /// rather than owning it, so this is the user's copy of what it offers —
    /// there is nothing to read it from, and no sensible default. Empty means
    /// the panel shows the steering guide alone.
    public private(set) var codexModels: [String]

    public static let defaults: [Int: String] = [:]
    public static let defaultClaudeModels = ["fable", "opus", "sonnet", "haiku"]
    public static let defaultClaudeEfforts = ["low", "medium", "high", "xhigh", "max"]

    public init(
        texts: [Int: String] = KeyBindings.defaults,
        claudeModels: [String] = KeyBindings.defaultClaudeModels,
        claudeEfforts: [String] = KeyBindings.defaultClaudeEfforts,
        codexModels: [String] = []
    ) {
        self.texts = texts
        self.claudeModels = claudeModels
        self.claudeEfforts = claudeEfforts
        self.codexModels = codexModels
    }

    /// The string bound to a key, or nil when the key does something else.
    public func text(for key: Int) -> String? {
        guard let text = texts[key], !text.isEmpty else { return nil }
        return text
    }

    public static func configPath() -> String {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        return (base as NSString).appendingPathComponent("micromanager/config.json")
    }

    public static func load() -> KeyBindings {
        guard let data = FileManager.default.contents(atPath: configPath()) else {
            return KeyBindings()
        }
        return parse(data)
    }

    /// A malformed file falls back to the defaults rather than a dead pad.
    static func parse(_ data: Data) -> KeyBindings {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return KeyBindings() }

        var texts = defaults
        if let keys = json["keys"] as? [String: Any] {
            for (name, value) in keys {
                guard let text = value as? String else { continue }
                for key in keyIDs(for: name) {
                    if text.isEmpty {
                        texts.removeValue(forKey: key)
                    } else {
                        texts[key] = text
                    }
                }
            }
        }

        let claude = json["claude"] as? [String: Any]
        let models = (claude?["models"] as? [String])?.filter { !$0.isEmpty }
        let efforts = (claude?["efforts"] as? [String])?.filter { !$0.isEmpty }
        let codex = json["codex"] as? [String: Any]
        let codexModels = (codex?["models"] as? [String])?.filter { !$0.isEmpty }
        return KeyBindings(
            texts: texts,
            claudeModels: models?.isEmpty == false ? models! : defaultClaudeModels,
            claudeEfforts: efforts?.isEmpty == false ? efforts! : defaultClaudeEfforts,
            codexModels: codexModels ?? []
        )
    }

    private static func keyIDs(for name: String) -> [Int] {
        // "10+11" used to address the wide keycap as one. There is no such cap:
        // row 3 is three separate keys, so a compound name would bind two of
        // them to one string without saying so.
        guard let id = Int(name) else { return [] }
        return [id]
    }
}
