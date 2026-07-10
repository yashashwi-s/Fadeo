import Foundation

// MARK: - Serialization

/// Codec for the on-disk config. M0 uses pretty JSON (built-in, zero-dependency,
/// round-trips losslessly). A YAML front-end (Yams) slots in at M4 without touching
/// the model — everything here is plain `Codable`.
public enum ConfigCodec {
    public static func encode(_ config: Config) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(config)
    }

    public static func decode(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public static func decode(string: String) throws -> Config {
        try decode(Data(string.utf8))
    }
}

// MARK: - Starter config

public extension Config {
    /// A sensible, self-explanatory default written on first launch. Demonstrates every
    /// concept: an override (Meetings), strong + weak membership, a space rule, a time
    /// rule, and per-app overrides — all editable.
    static var starter: Config {
        Config(
            version: 1,
            settings: Settings(),
            workspaces: [
                Workspace(
                    id: "meetings",
                    name: "Meetings",
                    color: "#F2A65A",
                    isOverride: true,
                    priority: 100,
                    match: Match(meeting: true),
                    sound: Sound(action: .pause),
                    timing: Timing(fadeOutMs: 300)
                ),
                Workspace(
                    id: "deep-work",
                    name: "Deep Work",
                    color: "#67E4D2",
                    priority: 80,
                    match: Match(
                        apps: [
                            AppMembership(bundle: "com.apple.dt.Xcode", strength: .strong),
                            AppMembership(bundle: "com.microsoft.VSCode", strength: .strong),
                            AppMembership(bundle: "com.apple.Terminal", strength: .strong),
                            // Chat/notes don't yank you out of flow:
                            AppMembership(bundle: "com.tinyspeck.slackmacgap", strength: .weak),
                            AppMembership(bundle: "com.apple.Notes", strength: .weak),
                        ]
                    ),
                    sound: Sound(
                        source: "internal:preset:brown-noise",
                        volume: 0.6,
                        perApp: ["com.apple.dt.Xcode": PerAppOverride(volume: 0.7)]
                    ),
                    timing: Timing(fadeInMs: 1200, minDwellMs: 20000)
                ),
                Workspace(
                    id: "reading",
                    name: "Reading",
                    color: "#8AB4F8",
                    priority: 40,
                    match: Match(
                        apps: [
                            AppMembership(bundle: "com.apple.Safari"),
                            AppMembership(bundle: "com.google.Chrome"),
                            AppMembership(bundle: "com.apple.iBooksX"),
                        ]
                    ),
                    sound: Sound(source: "internal:preset:rain", volume: 0.45)
                ),
            ]
        )
    }
}
