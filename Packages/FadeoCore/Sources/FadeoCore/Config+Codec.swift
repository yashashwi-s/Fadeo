import Foundation
import Yams

// MARK: - Serialization

/// Codec for the on-disk config. YAML (not JSON) is the format users actually hand-edit —
/// it supports comments, which matters for a rules file people are meant to tweak
/// (PLAN.md's "power user" surface). Everything here is plain `Codable`; Yams is the only
/// dependency FadeoCore has, and it's pure Swift with no OS calls.
public enum ConfigCodec {
    public static func encode(_ config: Config) throws -> Data {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        let yaml = try encoder.encode(config)
        return Data(yaml.utf8)
    }

    public static func decode(_ data: Data) throws -> Config {
        let string = String(decoding: data, as: UTF8.self)
        return try decode(string: string)
    }

    public static func decode(string: String) throws -> Config {
        try YAMLDecoder().decode(Config.self, from: string)
    }

    /// Generic YAML encode/decode for other on-disk models (e.g. UsageStats) that want
    /// the same format without each needing its own codec type.
    public static func encodeAny<T: Encodable>(_ value: T) throws -> Data {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        return Data(try encoder.encode(value).utf8)
    }

    public static func decodeAny<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try YAMLDecoder().decode(T.self, from: String(decoding: data, as: UTF8.self))
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
