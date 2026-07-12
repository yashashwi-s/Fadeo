import XCTest
@testable import FadeoCore

final class DiagnosticsShapeTests: XCTestCase {
    private func w(_ id: String, source: String?, apps: [String] = [], spaces: [Int] = [],
                   meeting: Bool? = nil, enabled: Bool = true, override: Bool = false) -> Workspace {
        Workspace(id: id, name: id, enabled: enabled, isOverride: override, priority: 0,
                  match: Match(apps: apps.map { AppMembership(bundle: $0, strength: .strong) },
                               spaces: spaces, meeting: meeting),
                  sound: Sound(source: source, action: .play))
    }

    func testSourceKindCounts() {
        let cfg = Config(workspaces: [
            w("a", source: "internal:preset:brown-noise", apps: ["x"]),
            w("b", source: "internal:preset:rain", spaces: [1]),
            w("c", source: "internal:folder:/x"),
            w("d", source: "external:spotify:command"),
            w("e", source: "external:browser:playlist:https://youtube.com/x"),
            w("f", source: nil),
        ])
        let shape = cfg.diagnosticsShape
        XCTAssertEqual(shape.sourceKinds["noise"], 2)
        XCTAssertEqual(shape.sourceKinds["folder"], 1)
        XCTAssertEqual(shape.sourceKinds["spotify"], 1)
        XCTAssertEqual(shape.sourceKinds["browser"], 1)
        XCTAssertEqual(shape.sourceKinds["none"], 1)
    }

    func testPresetCounts() {
        let cfg = Config(workspaces: [
            w("a", source: "internal:preset:brown-noise"),
            w("b", source: "internal:preset:brown-noise"),
            w("c", source: "internal:preset:rain"),
        ])
        XCTAssertEqual(cfg.diagnosticsShape.presets["brown-noise"], 2)
        XCTAssertEqual(cfg.diagnosticsShape.presets["rain"], 1)
    }

    func testTriggerKindCounts() {
        let cfg = Config(workspaces: [
            w("a", source: "internal:preset:x", apps: ["x"], spaces: [1]),
            w("b", source: "internal:preset:x", meeting: true),
        ])
        let shape = cfg.diagnosticsShape
        XCTAssertEqual(shape.triggerKinds["app"], 1)
        XCTAssertEqual(shape.triggerKinds["space"], 1)
        XCTAssertEqual(shape.triggerKinds["meeting"], 1)
        XCTAssertNil(shape.triggerKinds["focus"])
    }

    func testEnabledAndOverrideCounts() {
        let cfg = Config(workspaces: [
            w("a", source: "internal:preset:x", enabled: true, override: true),
            w("b", source: "internal:preset:x", enabled: false),
            w("c", source: "internal:preset:x", enabled: true),
        ])
        let shape = cfg.diagnosticsShape
        XCTAssertEqual(shape.enabledCount, 2)
        XCTAssertEqual(shape.overrideCount, 1)
        XCTAssertEqual(shape.fallbackMode, cfg.settings.fallback.rawValue)
    }

    func testNoWorkspacesEmptyShape() {
        let shape = Config(workspaces: []).diagnosticsShape
        XCTAssertEqual(shape.enabledCount, 0)
        XCTAssertTrue(shape.sourceKinds.isEmpty)
    }
}
