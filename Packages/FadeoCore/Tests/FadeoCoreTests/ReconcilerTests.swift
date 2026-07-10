import XCTest
@testable import FadeoCore

final class ReconcilerTests: XCTestCase {
    let r = Reconciler()
    let timing = Transition(timing: ResolvedTiming(
        fadeInMs: 800, fadeOutMs: 600, crossfadeMs: 1200,
        enterDelayMs: 0, exitDelayMs: 0, minDwellMs: 0))

    func target(_ action: SoundAction, _ source: String? = nil, _ vol: Double = 1.0) -> AudioTarget {
        AudioTarget(source: source, action: action, volume: vol)
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

    func testStopWhenPausing() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        XCTAssertEqual(r.reconcile(current: cur, target: target(.pause), transition: timing), .stop(fadeMs: 600))
    }

    func testStopWhenAlreadySilentIsNoOp() {
        XCTAssertEqual(r.reconcile(current: .silent, target: target(.stop), transition: timing), .none)
    }

    func testDoNothingKeepsPlaying() {
        let cur = AudioState(source: "internal:preset:brown-noise", volume: 0.6, playing: true)
        XCTAssertEqual(r.reconcile(current: cur, target: target(.doNothing), transition: timing), .none)
    }
}
