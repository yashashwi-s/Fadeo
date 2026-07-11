import XCTest
@testable import FadeoCore

final class ResolverTests: XCTestCase {
    let r = Resolver()

    // Helpers -----------------------------------------------------------------
    func ws(_ id: String, apps: [AppMembership] = [], spaces: [Int] = [],
            priority: Int = 0, override: Bool = false, meeting: Bool? = nil,
            action: SoundAction = .play, source: String? = "internal:preset:x",
            combine: MatchCombine = .all, enabled: Bool = true) -> Workspace {
        Workspace(id: id, name: id, enabled: enabled, isOverride: override, priority: priority,
                  match: Match(apps: apps, spaces: spaces, meeting: meeting, combine: combine),
                  sound: Sound(source: source, action: action))
    }
    func strong(_ b: String) -> AppMembership { AppMembership(bundle: b, strength: .strong) }
    func weak(_ b: String) -> AppMembership { AppMembership(bundle: b, strength: .weak) }
    func ctx(app: String? = nil, space: Int? = nil, camera: Bool = false) -> Context {
        Context(frontmostApp: app,
                activeSpace: space.map { SpaceRef(index: $0) },
                cameraActive: camera)
    }

    // Band 1: override --------------------------------------------------------
    func testOverridePreemptsEverything() {
        let cfg = Config(workspaces: [
            ws("deep", apps: [strong("X")], source: "internal:preset:brown"),
            ws("meet", override: true, meeting: true, action: .pause, source: nil),
        ])
        let d = r.resolve(context: ctx(app: "X", camera: true), config: cfg,
                          state: ResolverState(activeWorkspace: "deep"))
        XCTAssertEqual(d.activeWorkspace, "meet")
        XCTAssertEqual(d.target.action, .pause)
        XCTAssertEqual(d.reason.band, .override)
    }

    // Band 2: single candidate ------------------------------------------------
    func testSingleCandidate() {
        let cfg = Config(workspaces: [ws("deep", apps: [strong("X")])])
        let d = r.resolve(context: ctx(app: "X"), config: cfg)
        XCTAssertEqual(d.activeWorkspace, "deep")
        XCTAssertEqual(d.reason.band, .single)
    }

    // *** THE user's scenario: X ∈ {A,B}, coming from a third workspace C ***
    func testAppInTwoWorkspaces_specificityWins() {
        // A also pins Space 1 → more specific than B (app-only).
        let cfg = Config(workspaces: [
            ws("A", apps: [strong("X")], spaces: [1], priority: 10),
            ws("B", apps: [strong("X")], priority: 99),           // higher priority, but less specific
            ws("C", apps: [strong("Y")]),
        ])
        let d = r.resolve(context: ctx(app: "X", space: 1), config: cfg,
                          state: ResolverState(activeWorkspace: "C"))
        XCTAssertEqual(d.activeWorkspace, "A", "more specific match should win over higher priority")
        XCTAssertEqual(d.reason.deciding, .specificity)
        XCTAssertEqual(Set(d.reason.candidates), ["A", "B"])
    }

    func testAppInTwoWorkspaces_priorityBreaksTrueTie() {
        // Neither adds constraints → equal specificity → explicit priority decides.
        let cfg = Config(workspaces: [
            ws("A", apps: [strong("X")], priority: 20),
            ws("B", apps: [strong("X")], priority: 80),
            ws("C", apps: [strong("Y")]),
        ])
        let d = r.resolve(context: ctx(app: "X"), config: cfg,
                          state: ResolverState(activeWorkspace: "C"))
        XCTAssertEqual(d.activeWorkspace, "B")
        XCTAssertEqual(d.reason.deciding, .priority)
    }

    func testConstraintFiltersCandidate() {
        // On Space 2, A (requires Space 1) drops out → B is the lone candidate.
        let cfg = Config(workspaces: [
            ws("A", apps: [strong("X")], spaces: [1]),
            ws("B", apps: [strong("X")]),
        ])
        let d = r.resolve(context: ctx(app: "X", space: 2), config: cfg)
        XCTAssertEqual(d.activeWorkspace, "B")
        XCTAssertEqual(d.reason.band, .single)
    }

    // Band 3: stickiness ------------------------------------------------------
    func testStickinessKeepsCurrentOverHigherPriority() {
        let cfg = Config(workspaces: [
            ws("dw", apps: [strong("X")], priority: 10),
            ws("other", apps: [strong("X")], priority: 99),
        ])
        let d = r.resolve(context: ctx(app: "X"), config: cfg,
                          state: ResolverState(activeWorkspace: "dw"))
        XCTAssertEqual(d.activeWorkspace, "dw", "stickiness should keep current, beating priority")
        XCTAssertEqual(d.reason.deciding, .stickiness)
    }

    // Weak membership: shared apps don't yank you --------------------------------
    func testWeakAppPreservesCurrentWorkspace() {
        // In Deep Work; tab to Slack (weak everywhere, not a member of Deep Work).
        let cfg = Config(workspaces: [
            ws("deep", apps: [strong("Xcode")]),
            Workspace(id: "chatspace", name: "chatspace",
                      match: Match(apps: [weak("Slack")]),
                      sound: Sound(source: "internal:preset:lofi")),
        ])
        let d = r.resolve(context: ctx(app: "Slack"), config: cfg,
                          state: ResolverState(activeWorkspace: "deep"))
        XCTAssertEqual(d.activeWorkspace, "deep", "weak match must not pull you out of the active workspace")
        XCTAssertEqual(d.reason.band, .fallback)
        XCTAssertEqual(d.reason.weakOnly, ["chatspace"])
    }

    func testWeakAppWithNothingActiveStaysSilent() {
        let cfg = Config(settings: Settings(fallback: .silence), workspaces: [
            Workspace(id: "chatspace", name: "chatspace",
                      match: Match(apps: [weak("Slack")]), sound: Sound(source: "x")),
        ])
        let d = r.resolve(context: ctx(app: "Slack"), config: cfg)
        XCTAssertNil(d.activeWorkspace)
        XCTAssertEqual(d.target.action, .stop)
    }

    // Band 4: fallback --------------------------------------------------------
    func testFallbackKeepCurrent() {
        let cfg = Config(settings: Settings(fallback: .keepCurrent),
                         workspaces: [ws("deep", apps: [strong("X")])])
        let d = r.resolve(context: ctx(app: "Unrelated"), config: cfg,
                          state: ResolverState(activeWorkspace: "deep"))
        XCTAssertEqual(d.target.action, .doNothing)
        XCTAssertEqual(d.reason.band, .fallback)
    }

    func testFallbackSilence() {
        let cfg = Config(settings: Settings(fallback: .silence),
                         workspaces: [ws("deep", apps: [strong("X")])])
        let d = r.resolve(context: ctx(app: "Unrelated"), config: cfg,
                          state: ResolverState(activeWorkspace: "deep"))
        XCTAssertEqual(d.target.action, .stop)
        XCTAssertTrue(d.target.resumable, "a transient no-match fallback must be resumable, not a hard stop")
    }

    // Per-app override --------------------------------------------------------
    func testPerAppVolumeOverride() {
        let cfg = Config(workspaces: [
            Workspace(id: "deep", name: "deep",
                      match: Match(apps: [strong("Xcode"), strong("Terminal")]),
                      sound: Sound(source: "internal:preset:brown", volume: 0.6,
                                   perApp: ["Xcode": PerAppOverride(volume: 0.9)])),
        ])
        let inXcode = r.resolve(context: ctx(app: "Xcode"), config: cfg)
        XCTAssertEqual(inXcode.target.volume, 0.9, accuracy: 0.001)
        let inTerminal = r.resolve(context: ctx(app: "Terminal"), config: cfg)
        XCTAssertEqual(inTerminal.target.volume, 0.6, accuracy: 0.001)
    }

    // Determinism -------------------------------------------------------------
    func testResolutionIsDeterministic() {
        let cfg = Config(workspaces: [
            ws("A", apps: [strong("X")]), ws("B", apps: [strong("X")]),
        ])
        let first = r.resolve(context: ctx(app: "X"), config: cfg)
        for _ in 0..<50 {
            XCTAssertEqual(r.resolve(context: ctx(app: "X"), config: cfg).activeWorkspace,
                           first.activeWorkspace)
        }
    }

    // Empty match: inert, not a catch-all --------------------------------------
    func testEmptyMatchNeverMatches() {
        let cfg = Config(settings: Settings(fallback: .silence), workspaces: [ws("empty")])
        let d = r.resolve(context: ctx(app: "AnyApp"), config: cfg)
        XCTAssertNil(d.activeWorkspace)
        XCTAssertEqual(d.reason.band, .fallback)
    }

    func testEmptyMatchCannotStick() {
        let cfg = Config(workspaces: [ws("empty"), ws("appMatched", apps: [strong("X")])])
        let d = r.resolve(context: ctx(app: "X"), config: cfg,
                          state: ResolverState(activeWorkspace: "empty"))
        XCTAssertEqual(d.activeWorkspace, "appMatched")
    }

    // Override band -------------------------------------------------------------
    func testOverrideWithPlaySoundPlays() {
        let cfg = Config(workspaces: [
            ws("meet", override: true, meeting: true, action: .play, source: "internal:preset:brown"),
        ])
        let d = r.resolve(context: ctx(app: "X", camera: true), config: cfg)
        XCTAssertEqual(d.activeWorkspace, "meet")
        XCTAssertEqual(d.target.action, .play)
        XCTAssertEqual(d.target.source, "internal:preset:brown")
    }

    func testOverrideTieUsesChain() {
        // Two overrides with equal priority both match; the currently active one should
        // win via stickiness rather than an arbitrary priority/id tiebreak.
        let cfg = Config(workspaces: [
            ws("meetA", priority: 50, override: true, meeting: true),
            ws("meetB", priority: 50, override: true, meeting: true),
        ])
        let d = r.resolve(context: ctx(camera: true), config: cfg,
                          state: ResolverState(activeWorkspace: "meetB"))
        XCTAssertEqual(d.activeWorkspace, "meetB")
        XCTAssertEqual(d.reason.deciding, .stickiness)
    }

    // Nil context fields --------------------------------------------------------
    func testNilSpaceFailsCombineAll() {
        let cfg = Config(workspaces: [ws("dw", apps: [strong("X")], spaces: [1], combine: .all)])
        let d = r.resolve(context: ctx(app: "X", space: nil), config: cfg)
        XCTAssertNotEqual(d.activeWorkspace, "dw")
    }

    func testNilSpaceStillMatchesUnderAny() {
        let cfg = Config(workspaces: [ws("dw", apps: [strong("X")], spaces: [1], combine: .any)])
        let d = r.resolve(context: ctx(app: "X", space: nil), config: cfg)
        XCTAssertEqual(d.activeWorkspace, "dw")
    }

    // Weak preserve requires enabled ---------------------------------------------
    func testWeakPreserveRequiresEnabled() {
        let cfg = Config(settings: Settings(fallback: .silence), workspaces: [
            ws("deep", apps: [strong("Xcode")], enabled: false),
            Workspace(id: "chatspace", name: "chatspace",
                      match: Match(apps: [weak("Slack")]),
                      sound: Sound(source: "internal:preset:lofi")),
        ])
        let d = r.resolve(context: ctx(app: "Slack"), config: cfg,
                          state: ResolverState(activeWorkspace: "deep"))
        XCTAssertNil(d.activeWorkspace, "a disabled workspace must not be preserved by a weak match")
    }

    // Duplicate bundle entries ----------------------------------------------------
    func testDuplicateBundlePrefersStrong() {
        let cfg = Config(workspaces: [ws("dw", apps: [weak("X"), strong("X")])])
        let d = r.resolve(context: ctx(app: "X"), config: cfg)
        XCTAssertEqual(d.activeWorkspace, "dw", "a bundle listed both weak and strong should activate")
    }

    // Recency tiebreak ------------------------------------------------------------
    func testRecencySkipsWhenAllCold() {
        let cfg = Config(settings: Settings(tiebreak: [.recency, .stableId]), workspaces: [
            ws("B", apps: [strong("X")]), ws("A", apps: [strong("X")]),
        ])
        let d = r.resolve(context: ctx(app: "X"), config: cfg)
        XCTAssertEqual(d.reason.deciding, .stableId, "with no lastActive signal, recency must fall through")
        XCTAssertEqual(d.activeWorkspace, "A")
    }
}
