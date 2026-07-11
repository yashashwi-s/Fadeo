import XCTest
@testable import FadeoCore

final class ReconcilerTests: XCTestCase {
    let r = Reconciler()
    let timing = Transition(timing: ResolvedTiming(
        fadeInMs: 800, fadeOutMs: 600, crossfadeMs: 1200,
        enterDelayMs: 0, exitDelayMs: 0, minDwellMs: 0))

    func target(_ action: SoundAction, _ source: String? = nil, _ vol: Double = 1.0,
                repeatMode: RepeatMode = .all, resumable: Bool = false) -> AudioTarget {
        AudioTarget(source: source, action: action, volume: vol, repeatMode: repeatMode, resumable: resumable)
    }

    func testStartFromSilence() {
        let c = r.reconcile(current: .silent, target: target(.play, "internal:preset:brown-noise", 0.6), transition: timing)
        XCTAssertEqual(c, .start(source: "internal:preset:brown-noise", volume: 0.6, fadeMs: 800))
    }

    func testNoOpWhenAlreadyPlayingSame() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:preset:brown-noise", 0.6), transition: timing)
        XCTAssertEqual(c, .none)
    }

    func testCrossfadeOnSourceChange() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:preset:rain", 0.5), transition: timing)
        XCTAssertEqual(c, .crossfade(to: "internal:preset:rain", volume: 0.5, ms: 1200))
    }

    func testSetVolumeWhenOnlyVolumeChanges() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:preset:brown-noise", 0.9), transition: timing)
        XCTAssertEqual(c, .setVolume(0.9, ms: 800))
    }

    func testPauseActionIsResumable() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        XCTAssertEqual(r.reconcile(current: cur, target: target(.pause), transition: timing), .pause(fadeMs: 600),
                       "a workspace's own Pause action must be resumable, distinct from Stop")
    }

    func testStopActionIsHardStop() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        XCTAssertEqual(r.reconcile(current: cur, target: target(.stop), transition: timing), .stop(fadeMs: 600))
    }

    func testStopWhenAlreadySilentIsNoOp() {
        XCTAssertEqual(r.reconcile(current: .silent, target: target(.stop), transition: timing), .none)
    }

    func testDeliberateStopForcesTeardownFromAlreadyPausedState() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: false, paused: true)
        let c = r.reconcile(current: cur, target: target(.stop), transition: timing)
        XCTAssertEqual(c, .stop(fadeMs: 600), "a deliberate stop must tear down even a merely-paused session, not leave it open")
    }

    func testDoNothingKeepsPlaying() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        XCTAssertEqual(r.reconcile(current: cur, target: target(.doNothing), transition: timing), .none)
    }

    func testPlayNilSourceStopsWhenPlaying() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        XCTAssertEqual(r.reconcile(current: cur, target: target(.play, nil), transition: timing), .stop(fadeMs: 600))
    }

    // Finished (natural end of a play-once queue) --------------------------------
    func testFinishedRepeatOffDoesNotRestart() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.7, playing: false, finished: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:folder:/x", 0.7, repeatMode: .off), transition: timing)
        XCTAssertEqual(c, .none, "a finished play-once queue must not restart on a context tick")
    }

    func testFinishedRepeatAllRestarts() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.7, playing: false, finished: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:folder:/x", 0.7, repeatMode: .all), transition: timing)
        XCTAssertEqual(c, .start(source: "internal:folder:/x", volume: 0.7, fadeMs: 800))
    }

    func testFinishedDifferentSourceStarts() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.7, playing: false, finished: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:folder:/y", 0.7, repeatMode: .off), transition: timing)
        XCTAssertEqual(c, .start(source: "internal:folder:/y", volume: 0.7, fadeMs: 800))
    }

    // Duck --------------------------------------------------------------------
    func testDuckMapsToSetVolumeWhenPlaying() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.duck, "internal:preset:brown-noise", 0.2), transition: timing)
        XCTAssertEqual(c, .setVolume(0.2, ms: 800))
    }

    func testDuckNoneWhenSilent() {
        XCTAssertEqual(r.reconcile(current: .silent, target: target(.duck, nil, 0.2), transition: timing), .none)
    }

    // Resumable pause (transient fallback) -----------------------------------------
    func testResumableStopBecomesPause() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.stop, nil, 0, resumable: true), transition: timing)
        XCTAssertEqual(c, .pause(fadeMs: 600))
    }

    func testNonResumableStopStaysHardStop() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.stop, nil, 0, resumable: false), transition: timing)
        XCTAssertEqual(c, .stop(fadeMs: 600))
    }

    func testResumableNilSourcePlayBecomesPause() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.6, playing: true)
        let c = r.reconcile(current: cur, target: target(.play, nil, 0, resumable: true), transition: timing)
        XCTAssertEqual(c, .pause(fadeMs: 600))
    }

    func testPausedSameSourceResumesInPlace() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.6, playing: false, paused: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:folder:/x", 0.6), transition: timing)
        XCTAssertEqual(c, .resume(source: "internal:folder:/x", volume: 0.6, fadeMs: 800), "same source reappearing after a pause must resume, not restart")
    }

    func testPausedDifferentSourceStartsFresh() {
        let cur = AudioState(source: "internal:folder:/x", volume: 0.6, playing: false, paused: true)
        let c = r.reconcile(current: cur, target: target(.play, "internal:folder:/y", 0.6), transition: timing)
        XCTAssertEqual(c, .start(source: "internal:folder:/y", volume: 0.6, fadeMs: 800))
    }
}
