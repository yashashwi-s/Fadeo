import Foundation

/// Privacy-safe, config-derived aggregate counts for opt-in diagnostics. Contains no
/// names, app bundle IDs, or file paths -- only "how many workspaces use feature X" style
/// counts, so feature adoption is visible without exposing anyone's actual setup. Pure and
/// unit-tested; assembled into the shared payload by the app's DiagnosticsUploader.
public struct ConfigUsageShape: Codable, Sendable, Equatable {
    public var enabledCount: Int
    public var overrideCount: Int
    /// Keyed by source kind: noise, file, folder, playlist, spotify, appleMusic, browser, none.
    public var sourceKinds: [String: Int]
    /// Keyed by trigger kind: app, space, meeting, focus, time, weekday.
    public var triggerKinds: [String: Int]
    /// Keyed by ambient preset name (brown-noise, rain, ...), for the noise sources only.
    public var presets: [String: Int]
    public var fallbackMode: String

    public init(enabledCount: Int = 0, overrideCount: Int = 0, sourceKinds: [String: Int] = [:],
                triggerKinds: [String: Int] = [:], presets: [String: Int] = [:], fallbackMode: String = "") {
        self.enabledCount = enabledCount
        self.overrideCount = overrideCount
        self.sourceKinds = sourceKinds
        self.triggerKinds = triggerKinds
        self.presets = presets
        self.fallbackMode = fallbackMode
    }
}

public extension Config {
    /// Aggregate feature-adoption counts across all workspaces, privacy-safe (see
    /// `ConfigUsageShape`).
    var diagnosticsShape: ConfigUsageShape {
        var sourceKinds: [String: Int] = [:]
        var triggerKinds: [String: Int] = [:]
        var presets: [String: Int] = [:]
        var enabledCount = 0
        var overrideCount = 0
        for ws in workspaces {
            if ws.enabled { enabledCount += 1 }
            if ws.isOverride { overrideCount += 1 }
            let kind = Self.sourceKind(ws.sound.source)
            sourceKinds[kind, default: 0] += 1
            if kind == "noise", let preset = Self.presetName(ws.sound.source) {
                presets[preset, default: 0] += 1
            }
            if !ws.match.apps.isEmpty { triggerKinds["app", default: 0] += 1 }
            if !ws.match.spaces.isEmpty { triggerKinds["space", default: 0] += 1 }
            if ws.match.meeting != nil { triggerKinds["meeting", default: 0] += 1 }
            if !ws.match.focus.isEmpty { triggerKinds["focus", default: 0] += 1 }
            if ws.match.timeBetween != nil { triggerKinds["time", default: 0] += 1 }
            if !ws.match.weekdays.isEmpty { triggerKinds["weekday", default: 0] += 1 }
        }
        return ConfigUsageShape(
            enabledCount: enabledCount, overrideCount: overrideCount,
            sourceKinds: sourceKinds, triggerKinds: triggerKinds, presets: presets,
            fallbackMode: settings.fallback.rawValue
        )
    }

    private static func sourceKind(_ source: String?) -> String {
        guard let s = source else { return "none" }
        if s.hasPrefix("internal:preset:") { return "noise" }
        if s.hasPrefix("internal:file:") { return "file" }
        if s.hasPrefix("internal:folder:") { return "folder" }
        if s.hasPrefix("internal:playlist:") { return "playlist" }
        if s.hasPrefix("external:appleMusic") { return "appleMusic" }
        if s.hasPrefix("external:spotify") { return "spotify" }
        if s.hasPrefix("external:browser") { return "browser" }
        if s.hasPrefix("external:") { return "external" }
        return "none"
    }

    private static func presetName(_ source: String?) -> String? {
        let prefix = "internal:preset:"
        guard let s = source, s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }
}
