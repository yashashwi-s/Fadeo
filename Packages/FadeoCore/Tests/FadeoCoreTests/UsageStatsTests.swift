import XCTest
@testable import FadeoCore

final class UsageStatsTests: XCTestCase {
    func testRecordElapsedAccumulates() {
        var stats = UsageStats()
        stats.recordElapsed(workspaceID: "deep-work", seconds: 120, endedAt: Date())
        stats.recordElapsed(workspaceID: "deep-work", seconds: 30, endedAt: Date())
        XCTAssertEqual(stats.perWorkspace["deep-work"]?.totalSeconds, 150)
    }

    func testRecordActivationCountsSwitches() {
        var stats = UsageStats()
        stats.recordActivation(workspaceID: "deep-work")
        stats.recordActivation(workspaceID: "reading")
        stats.recordActivation(workspaceID: "deep-work")
        XCTAssertEqual(stats.totalSwitches, 3)
        XCTAssertEqual(stats.perWorkspace["deep-work"]?.activationCount, 2)
        XCTAssertEqual(stats.perWorkspace["reading"]?.activationCount, 1)
    }

    func testNilWorkspaceIgnored() {
        var stats = UsageStats()
        stats.recordElapsed(workspaceID: nil, seconds: 100, endedAt: Date())
        XCTAssertTrue(stats.perWorkspace.isEmpty)
    }

    func testShareableSummaryExcludesWorkspaceNames() throws {
        var stats = UsageStats()
        stats.recordActivation(workspaceID: "my-secret-project-workspace")
        stats.recordElapsed(workspaceID: "my-secret-project-workspace", seconds: 3600, endedAt: Date())
        let data = try JSONEncoder().encode(stats.shareableSummary)
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(string.contains("my-secret-project-workspace"))
    }

    func testRoundTrips() throws {
        var stats = UsageStats(installID: "abc", firstLaunch: Date(timeIntervalSince1970: 0))
        stats.recordActivation(workspaceID: "deep-work")
        stats.recordElapsed(workspaceID: "deep-work", seconds: 42, endedAt: Date(timeIntervalSince1970: 100))
        let data = try ConfigCodec_TestHelper.encode(stats)
        let back = try ConfigCodec_TestHelper.decode(data)
        XCTAssertEqual(back, stats)
    }
}

/// UsageStats uses the same Yams codec as Config but isn't itself part of Config, so this
/// tiny helper avoids exposing a second public codec just for a test round-trip.
private enum ConfigCodec_TestHelper {
    static func encode(_ stats: UsageStats) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(stats)
    }
    static func decode(_ data: Data) throws -> UsageStats {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(UsageStats.self, from: data)
    }
}
