import XCTest
import Yams
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

    func testDecodesRealYAMLWithComments() throws {
        // The actual point of switching to YAML: a hand-edited file with comments must
        // parse exactly like the equivalent JSON would.
        let yaml = """
        # Fadeo config — hand-edited
        version: 1
        settings:
          fallback: silence   # fade out when nothing matches
        workspaces:
          - id: focus
            name: Focus
            match:
              apps:
                - bundle: com.apple.dt.Xcode   # inline comment
            sound:
              source: internal:preset:brown-noise
              volume: 0.5
        """
        let cfg = try ConfigCodec.decode(string: yaml)
        XCTAssertEqual(cfg.settings.fallback, .silence)
        XCTAssertEqual(cfg.workspaces.first?.sound.volume, 0.5)
        XCTAssertEqual(cfg.workspaces.first?.match.apps.first?.bundle, "com.apple.dt.Xcode")
    }

    func testSoundOrderAndRepeatDefaults() {
        let s = Sound(source: "internal:folder:/x")
        XCTAssertEqual(s.order, .sequential)
        XCTAssertEqual(s.repeatMode, .all)
    }

    func testLocalPlaylistRoundTrips() throws {
        let cfg = Config(localPlaylists: [LocalPlaylist(id: "focus", name: "Focus", paths: ["/a.mp3", "/b.wav"])])
        let data = try ConfigCodec.encode(cfg)
        let back = try ConfigCodec.decode(data)
        XCTAssertEqual(back.localPlaylists, cfg.localPlaylists)
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

    func testDecodesFromYAMLArray() throws {
        // Yams' unkeyed-container path must behave the same as JSONDecoder's here — this
        // is the trickiest custom decode logic in the model (array-or-object ambiguity).
        let w = try YAMLDecoder().decode(TimeWindow.self, from: "[\"18:00\", \"07:00\"]")
        XCTAssertEqual(w.start, "18:00")
        XCTAssertEqual(w.end, "07:00")
    }

    // MARK: Saved sounds

    func testSavedSoundsRoundTrip() throws {
        var cfg = Config()
        cfg.savedSounds = [
            SavedSound(id: "s1", name: "Janice STFU",
                       source: "external:appleMusic:playlist:https://music.apple.com/in/album/janice-stfu/6769568449?i=6769568596"),
            SavedSound(id: "s2", name: "Focus mix", source: "external:spotify:playlist:spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"),
        ]
        let back = try ConfigCodec.decode(try ConfigCodec.encode(cfg))
        XCTAssertEqual(back.savedSounds, cfg.savedSounds)
    }

    func testShareLinkSourceSurvivesYAMLRoundTrip() throws {
        // URLs carry ':', '?', '&', '#', '=' — every one a YAML-special character. The
        // emitter must quote so the exact string comes back; a truncated or mangled
        // source here is exactly the "my pasted link didn't save" bug class.
        let url = "external:appleMusic:playlist:https://music.apple.com/in/album/x/1?i=2&x=3#frag"
        var cfg = Config()
        cfg.workspaces = [Workspace(id: "w", name: "w", match: Match(), sound: Sound(source: url))]
        let back = try ConfigCodec.decode(try ConfigCodec.encode(cfg))
        XCTAssertEqual(back.workspaces[0].sound.source, url)
    }

    func testConfigWithoutSavedSoundsStillDecodes() throws {
        // Backward compatibility: every existing config.yaml lacks the key.
        let cfg = try ConfigCodec.decode(string: "{ \"workspaces\": [] }")
        XCTAssertEqual(cfg.savedSounds, [])
    }
}
