import Foundation

// MARK: - Context (what's happening right now)

/// Which OS signal a match / sensor depends on. Used to compute the *lazy activation
/// set*: a sensor whose field no enabled workspace references is never started.
public enum ContextField: String, Codable, Sendable, CaseIterable {
    case app, space, meeting, camera, mic, focus, time, weekday, idle
}

/// A reference to a virtual desktop / Space. `index` is the 1-based desktop number and
/// may be `nil` if the private CGS shim degraded on a future macOS.
public struct SpaceRef: Codable, Sendable, Equatable {
    public var display: String
    public var index: Int?
    public var uuid: String?

    public init(display: String = "main", index: Int? = nil, uuid: String? = nil) {
        self.display = display
        self.index = index
        self.uuid = uuid
    }
}

/// One merged snapshot the resolver reasons over. A pure value; sensors fill subsets.
public struct Context: Sendable, Equatable {
    public var frontmostApp: String?
    public var frontmostWindowTitle: String?
    public var activeSpace: SpaceRef?
    public var cameraActive: Bool
    public var micActive: Bool
    public var focusMode: String?
    public var localTime: Date
    public var idleSeconds: TimeInterval?
    public var stamp: Date

    public init(
        frontmostApp: String? = nil,
        frontmostWindowTitle: String? = nil,
        activeSpace: SpaceRef? = nil,
        cameraActive: Bool = false,
        micActive: Bool = false,
        focusMode: String? = nil,
        localTime: Date = Date(),
        idleSeconds: TimeInterval? = nil,
        stamp: Date = Date()
    ) {
        self.frontmostApp = frontmostApp
        self.frontmostWindowTitle = frontmostWindowTitle
        self.activeSpace = activeSpace
        self.cameraActive = cameraActive
        self.micActive = micActive
        self.focusMode = focusMode
        self.localTime = localTime
        self.idleSeconds = idleSeconds
        self.stamp = stamp
    }

    /// Whether we consider the user "in a meeting", per the configured trigger.
    public func inMeeting(_ trigger: MeetingTrigger) -> Bool {
        switch trigger {
        case .cameraOrMic:  return cameraActive || micActive
        case .cameraAndMic: return cameraActive && micActive
        case .cameraOnly:   return cameraActive
        case .micOnly:      return micActive
        }
    }
}

// MARK: - Workspace match

public enum MembershipStrength: String, Codable, Sendable {
    /// Presence of this app *activates* the workspace (default).
    case strong
    /// This app never changes anything — it only *preserves* the current workspace,
    /// so tabbing to it won't yank you between contexts.
    case weak
}

public struct AppMembership: Codable, Sendable, Equatable {
    public var bundle: String
    public var strength: MembershipStrength

    public init(bundle: String, strength: MembershipStrength = .strong) {
        self.bundle = bundle
        self.strength = strength
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bundle = try c.decode(String.self, forKey: .bundle)
        self.strength = try c.decodeIfPresent(MembershipStrength.self, forKey: .strength) ?? .strong
    }
}

/// How the specified dimensions of a match combine.
public enum MatchCombine: String, Codable, Sendable { case all, any }

/// "HH:mm"–"HH:mm" window, wrap-around aware (e.g. 18:00–07:00 spans midnight).
public struct TimeWindow: Codable, Sendable, Equatable {
    public var start: String
    public var end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    public init(from decoder: any Decoder) throws {
        // Accept either ["09:00","18:00"] or {start,end}.
        if var arr = try? decoder.unkeyedContainer() {
            self.start = try arr.decode(String.self)
            self.end = try arr.decode(String.self)
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.start = try c.decode(String.self, forKey: .start)
            self.end = try c.decode(String.self, forKey: .end)
        }
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let s = Self.minutes(start), let e = Self.minutes(end) else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let now = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if s == e { return true }                 // full day
        if s < e { return now >= s && now < e }   // same-day window
        return now >= s || now < e                // wraps past midnight
    }
}

/// The conditions that activate a workspace. Only *specified* dimensions participate;
/// an empty match is a catch-all (always true).
public struct Match: Codable, Sendable, Equatable {
    public var apps: [AppMembership]
    public var spaces: [Int]
    public var focus: [String]
    public var meeting: Bool?
    public var timeBetween: TimeWindow?
    public var weekdays: [Int]           // 1=Sun ... 7=Sat (Calendar convention)
    public var combine: MatchCombine

    public init(
        apps: [AppMembership] = [],
        spaces: [Int] = [],
        focus: [String] = [],
        meeting: Bool? = nil,
        timeBetween: TimeWindow? = nil,
        weekdays: [Int] = [],
        combine: MatchCombine = .all
    ) {
        self.apps = apps
        self.spaces = spaces
        self.focus = focus
        self.meeting = meeting
        self.timeBetween = timeBetween
        self.weekdays = weekdays
        self.combine = combine
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.apps = try c.decodeIfPresent([AppMembership].self, forKey: .apps) ?? []
        self.spaces = try c.decodeIfPresent([Int].self, forKey: .spaces) ?? []
        self.focus = try c.decodeIfPresent([String].self, forKey: .focus) ?? []
        self.meeting = try c.decodeIfPresent(Bool.self, forKey: .meeting)
        self.timeBetween = try c.decodeIfPresent(TimeWindow.self, forKey: .timeBetween)
        self.weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        self.combine = try c.decodeIfPresent(MatchCombine.self, forKey: .combine) ?? .all
    }
}

// MARK: - Sound (what a workspace does)

public enum SoundAction: String, Codable, Sendable {
    case play, pause, stop, setVolume, duck, resumePrevious, doNothing
}

public struct PerAppOverride: Codable, Sendable, Equatable {
    public var volume: Double?
    public var source: String?

    public init(volume: Double? = nil, source: String? = nil) {
        self.volume = volume
        self.source = source
    }
}

public struct Sound: Codable, Sendable, Equatable {
    /// e.g. "internal:preset:brown-noise", "external:spotify:playlist:<id>". `nil` for pause/stop.
    public var source: String?
    public var action: SoundAction
    public var volume: Double
    public var perApp: [String: PerAppOverride]

    public init(
        source: String? = nil,
        action: SoundAction = .play,
        volume: Double = 1.0,
        perApp: [String: PerAppOverride] = [:]
    ) {
        self.source = source
        self.action = action
        self.volume = volume
        self.perApp = perApp
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.action = try c.decodeIfPresent(SoundAction.self, forKey: .action) ?? .play
        self.volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        self.perApp = try c.decodeIfPresent([String: PerAppOverride].self, forKey: .perApp) ?? [:]
    }
}

// MARK: - Timing

/// Per-workspace timing overrides. `nil` means "inherit the global default".
public struct Timing: Codable, Sendable, Equatable {
    public var fadeInMs: Int?
    public var fadeOutMs: Int?
    public var crossfadeMs: Int?
    public var enterDelayMs: Int?
    public var exitDelayMs: Int?
    public var minDwellMs: Int?

    public init(
        fadeInMs: Int? = nil, fadeOutMs: Int? = nil, crossfadeMs: Int? = nil,
        enterDelayMs: Int? = nil, exitDelayMs: Int? = nil, minDwellMs: Int? = nil
    ) {
        self.fadeInMs = fadeInMs; self.fadeOutMs = fadeOutMs; self.crossfadeMs = crossfadeMs
        self.enterDelayMs = enterDelayMs; self.exitDelayMs = exitDelayMs; self.minDwellMs = minDwellMs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fadeInMs = try c.decodeIfPresent(Int.self, forKey: .fadeInMs)
        fadeOutMs = try c.decodeIfPresent(Int.self, forKey: .fadeOutMs)
        crossfadeMs = try c.decodeIfPresent(Int.self, forKey: .crossfadeMs)
        enterDelayMs = try c.decodeIfPresent(Int.self, forKey: .enterDelayMs)
        exitDelayMs = try c.decodeIfPresent(Int.self, forKey: .exitDelayMs)
        minDwellMs = try c.decodeIfPresent(Int.self, forKey: .minDwellMs)
    }

    /// Resolve against global defaults into a concrete timing.
    public func resolved(over d: TimingDefaults) -> ResolvedTiming {
        ResolvedTiming(
            fadeInMs: fadeInMs ?? d.fadeInMs,
            fadeOutMs: fadeOutMs ?? d.fadeOutMs,
            crossfadeMs: crossfadeMs ?? d.crossfadeMs,
            enterDelayMs: enterDelayMs ?? d.enterDelayMs,
            exitDelayMs: exitDelayMs ?? d.exitDelayMs,
            minDwellMs: minDwellMs ?? d.minDwellMs
        )
    }
}

public struct ResolvedTiming: Sendable, Equatable {
    public var fadeInMs: Int
    public var fadeOutMs: Int
    public var crossfadeMs: Int
    public var enterDelayMs: Int
    public var exitDelayMs: Int
    public var minDwellMs: Int
}

// MARK: - Workspace

public struct Workspace: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var color: String?
    public var enabled: Bool
    /// Override band: while this matches it pre-empts every non-override workspace.
    public var isOverride: Bool
    public var priority: Int
    public var match: Match
    public var sound: Sound
    public var timing: Timing

    enum CodingKeys: String, CodingKey {
        case id, name, color, enabled
        case isOverride = "override"
        case priority, match, sound, timing
    }

    public init(
        id: String, name: String, color: String? = nil, enabled: Bool = true,
        isOverride: Bool = false, priority: Int = 0,
        match: Match, sound: Sound, timing: Timing = Timing()
    ) {
        self.id = id; self.name = name; self.color = color; self.enabled = enabled
        self.isOverride = isOverride; self.priority = priority
        self.match = match; self.sound = sound; self.timing = timing
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        color = try c.decodeIfPresent(String.self, forKey: .color)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isOverride = try c.decodeIfPresent(Bool.self, forKey: .isOverride) ?? false
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        match = try c.decodeIfPresent(Match.self, forKey: .match) ?? Match()
        sound = try c.decodeIfPresent(Sound.self, forKey: .sound) ?? Sound()
        timing = try c.decodeIfPresent(Timing.self, forKey: .timing) ?? Timing()
    }
}

// MARK: - Settings

public enum TiebreakStrategy: String, Codable, Sendable, CaseIterable {
    case stickiness, specificity, priority, recency, stableId
}

public enum Fallback: String, Codable, Sendable {
    case keepCurrent, resumePrevious, silence
}

public enum MeetingTrigger: String, Codable, Sendable {
    case cameraOrMic, cameraAndMic, cameraOnly, micOnly
}

public struct TimingDefaults: Codable, Sendable, Equatable {
    public var fadeInMs: Int
    public var fadeOutMs: Int
    public var crossfadeMs: Int
    public var enterDelayMs: Int
    public var exitDelayMs: Int
    public var minDwellMs: Int

    public init(
        fadeInMs: Int = 800, fadeOutMs: Int = 800, crossfadeMs: Int = 1200,
        enterDelayMs: Int = 1200, exitDelayMs: Int = 400, minDwellMs: Int = 15000
    ) {
        self.fadeInMs = fadeInMs; self.fadeOutMs = fadeOutMs; self.crossfadeMs = crossfadeMs
        self.enterDelayMs = enterDelayMs; self.exitDelayMs = exitDelayMs; self.minDwellMs = minDwellMs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fadeInMs = try c.decodeIfPresent(Int.self, forKey: .fadeInMs) ?? 800
        fadeOutMs = try c.decodeIfPresent(Int.self, forKey: .fadeOutMs) ?? 800
        crossfadeMs = try c.decodeIfPresent(Int.self, forKey: .crossfadeMs) ?? 1200
        enterDelayMs = try c.decodeIfPresent(Int.self, forKey: .enterDelayMs) ?? 1200
        exitDelayMs = try c.decodeIfPresent(Int.self, forKey: .exitDelayMs) ?? 400
        minDwellMs = try c.decodeIfPresent(Int.self, forKey: .minDwellMs) ?? 15000
    }
}

public struct Settings: Codable, Sendable, Equatable {
    public var evaluationDebounceMs: Int
    public var tiebreak: [TiebreakStrategy]
    public var fallback: Fallback
    public var fallbackFadeMs: Int
    public var meeting: MeetingTrigger
    public var defaults: TimingDefaults

    public init(
        evaluationDebounceMs: Int = 300,
        tiebreak: [TiebreakStrategy] = [.stickiness, .specificity, .priority, .recency, .stableId],
        fallback: Fallback = .keepCurrent,
        fallbackFadeMs: Int = 1500,
        meeting: MeetingTrigger = .cameraOrMic,
        defaults: TimingDefaults = TimingDefaults()
    ) {
        self.evaluationDebounceMs = evaluationDebounceMs
        self.tiebreak = tiebreak
        self.fallback = fallback
        self.fallbackFadeMs = fallbackFadeMs
        self.meeting = meeting
        self.defaults = defaults
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        evaluationDebounceMs = try c.decodeIfPresent(Int.self, forKey: .evaluationDebounceMs) ?? 300
        tiebreak = try c.decodeIfPresent([TiebreakStrategy].self, forKey: .tiebreak)
            ?? [.stickiness, .specificity, .priority, .recency, .stableId]
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .keepCurrent
        fallbackFadeMs = try c.decodeIfPresent(Int.self, forKey: .fallbackFadeMs) ?? 1500
        meeting = try c.decodeIfPresent(MeetingTrigger.self, forKey: .meeting) ?? .cameraOrMic
        defaults = try c.decodeIfPresent(TimingDefaults.self, forKey: .defaults) ?? TimingDefaults()
    }

    /// Ensure the tiebreak chain always ends deterministically.
    public var normalizedTiebreak: [TiebreakStrategy] {
        tiebreak.contains(.stableId) ? tiebreak : tiebreak + [.stableId]
    }
}

// MARK: - Config (top-level, the serialized source of truth)

public struct Config: Codable, Sendable, Equatable {
    public var version: Int
    public var settings: Settings
    public var workspaces: [Workspace]

    public init(version: Int = 1, settings: Settings = Settings(), workspaces: [Workspace] = []) {
        self.version = version
        self.settings = settings
        self.workspaces = workspaces
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
    }
}
