import XCTest
@testable import FadeoCore

final class ConfigTests: XCTestCase {

    func testStarterRoundTrips() throws {
        let data = try ConfigCodec.encode(.starter)
        let back = try ConfigCodec.decode(data)
        XCTAssertEqual(back, .starter, "encode→decode must be lossless")
    }

    func testLenientPartialDecode() throws {
        // A hand-edited file with almost everything omitted should still load with defaults.
        let json = """
        { "workspaces": [ { "id": "focus", "match": { "apps": [ { "bundle": "com.apple.dt.Xcode" } ] } } ] }
        """
        let cfg = try ConfigCodec.decode(string: json)
        XCTAssertEqual(cfg.version, 1)
        XCTAssertEqual(cfg.settings.fallback, .keepCurrent)
        XCTAssertEqual(cfg.workspaces.count, 1)
        let w = cfg.workspaces[0]
        XCTAssertEqual(w.name, "focus")               // defaults to id
        XCTAssertTrue(w.enabled)
        XCTAssertFalse(w.isOverride)
        XCTAssertEqual(w.match.apps.first?.strength, .strong)   // strength defaults to strong
        XCTAssertEqual(w.sound.action, .play)
    }

    func testTimingResolvesOverDefaults() {
        let d = TimingDefaults(fadeInMs: 800, fadeOutMs: 800)
        let t = Timing(fadeInMs: 1200).resolved(over: d)
        XCTAssertEqual(t.fadeInMs, 1200)   // overridden
        XCTAssertEqual(t.fadeOutMs, 800)   // inherited
    }

    func testNormalizedTiebreakAlwaysEndsDeterministic() {
        let s = Settings(tiebreak: [.specificity, .priority])
        XCTAssertEqual(s.normalizedTiebreak.last, .stableId)
    }

    func testMeetingTriggerModes() {
        let both = Context(cameraActive: true, micActive: false)
        XCTAssertTrue(both.inMeeting(.cameraOrMic))
        XCTAssertFalse(both.inMeeting(.cameraAndMic))
        XCTAssertTrue(both.inMeeting(.cameraOnly))
        XCTAssertFalse(both.inMeeting(.micOnly))
    }
}

final class TimeWindowTests: XCTestCase {
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 10; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testSameDayWindow() {
        let w = TimeWindow(start: "09:00", end: "18:00")
        XCTAssertTrue(w.contains(at(12)))
        XCTAssertFalse(w.contains(at(8)))
        XCTAssertFalse(w.contains(at(18)))   // end exclusive
    }

    func testWrapAroundMidnight() {
        let w = TimeWindow(start: "18:00", end: "07:00")
        XCTAssertTrue(w.contains(at(20)))
        XCTAssertTrue(w.contains(at(2)))
        XCTAssertFalse(w.contains(at(12)))
    }

    func testDecodesFromArray() throws {
        let json = "[\"18:00\",\"07:00\"]"
        let w = try JSONDecoder().decode(TimeWindow.self, from: Data(json.utf8))
        XCTAssertEqual(w.start, "18:00")
        XCTAssertEqual(w.end, "07:00")
    }
}
