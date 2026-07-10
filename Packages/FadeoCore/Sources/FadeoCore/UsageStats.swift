import Foundation

/// Accumulated usage for one workspace. This is genuinely useful to the user (their own
/// "screen time for sound"), not just diagnostics for the developer.
public struct WorkspaceUsage: Codable, Sendable, Equatable {
    public var totalSeconds: Double
    public var activationCount: Int
    public var lastActive: Date?

    public init(totalSeconds: Double = 0, activationCount: Int = 0, lastActive: Date? = nil) {
        self.totalSeconds = totalSeconds
        self.activationCount = activationCount
        self.lastActive = lastActive
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = try c.decodeIfPresent(Double.self, forKey: .totalSeconds) ?? 0
        activationCount = try c.decodeIfPresent(Int.self, forKey: .activationCount) ?? 0
        lastActive = try c.decodeIfPresent(Date.self, forKey: .lastActive)
    }
}

/// All local usage data, kept entirely on-device. `installID` is a random identifier with
/// no relation to any personal information, generated once and reused only so that if the
/// user opts in to sharing (Settings > Privacy), repeat submissions can be deduplicated
/// server-side without needing anything identifying.
public struct UsageStats: Codable, Sendable, Equatable {
    public var installID: String
    public var firstLaunch: Date
    public var totalSwitches: Int
    public var sessionCount: Int
    public var perWorkspace: [String: WorkspaceUsage]

    public init(
        installID: String = UUID().uuidString,
        firstLaunch: Date = Date(),
        totalSwitches: Int = 0,
        sessionCount: Int = 0,
        perWorkspace: [String: WorkspaceUsage] = [:]
    ) {
        self.installID = installID
        self.firstLaunch = firstLaunch
        self.totalSwitches = totalSwitches
        self.sessionCount = sessionCount
        self.perWorkspace = perWorkspace
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installID = try c.decodeIfPresent(String.self, forKey: .installID) ?? UUID().uuidString
        firstLaunch = try c.decodeIfPresent(Date.self, forKey: .firstLaunch) ?? Date()
        totalSwitches = try c.decodeIfPresent(Int.self, forKey: .totalSwitches) ?? 0
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        perWorkspace = try c.decodeIfPresent([String: WorkspaceUsage].self, forKey: .perWorkspace) ?? [:]
    }

    /// Pure accumulator: the workspace that was active for `elapsedSeconds` just ended
    /// (either a switch to another workspace, or the app is about to quit/sleep). No I/O,
    /// no dates read internally, so this is trivially unit-testable.
    public mutating func recordElapsed(workspaceID: String?, seconds: Double, endedAt: Date) {
        guard let workspaceID, seconds > 0 else { return }
        var usage = perWorkspace[workspaceID] ?? WorkspaceUsage()
        usage.totalSeconds += seconds
        usage.lastActive = endedAt
        perWorkspace[workspaceID] = usage
    }

    /// A workspace just became active (a genuine switch, not the very first evaluation).
    public mutating func recordActivation(workspaceID: String) {
        var usage = perWorkspace[workspaceID] ?? WorkspaceUsage()
        usage.activationCount += 1
        perWorkspace[workspaceID] = usage
        totalSwitches += 1
    }

    /// A coarse, non-identifying summary suitable for opt-in sharing: no workspace names,
    /// no app bundle IDs, no file paths, just shape-of-usage numbers.
    public var shareableSummary: ShareableUsageSummary {
        ShareableUsageSummary(
            installID: installID,
            daysSinceFirstLaunch: max(0, Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0),
            sessionCount: sessionCount,
            workspaceCount: perWorkspace.count,
            totalSwitches: totalSwitches,
            totalActiveSeconds: perWorkspace.values.reduce(0) { $0 + $1.totalSeconds }
        )
    }
}

/// What would actually be sent if the user opts in. Deliberately excludes anything
/// identifying: no workspace names, no app bundle IDs, no file paths, no config contents.
public struct ShareableUsageSummary: Codable, Sendable, Equatable {
    public var installID: String
    public var daysSinceFirstLaunch: Int
    public var sessionCount: Int
    public var workspaceCount: Int
    public var totalSwitches: Int
    public var totalActiveSeconds: Double
}
