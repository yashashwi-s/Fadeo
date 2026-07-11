import Foundation

// MARK: - Decision (resolver output)

public struct AudioTarget: Sendable, Equatable {
    public var source: String?
    public var action: SoundAction
    public var volume: Double
    /// Only meaningful for multi-file internal sources (folder/playlist).
    public var order: PlaybackOrder
    public var repeatMode: RepeatMode
    /// True only for a transient "nothing matches right now" fallback (Band 4): tells the
    /// Reconciler to hold the session open in a resumable pause rather than fully
    /// tearing down, since the same workspace reappearing a moment later (a menu-bar
    /// click, a glance at Mission Control, briefly tabbing away) should resume in place,
    /// not restart. Never set by a workspace's own configured sound action.
    public var resumable: Bool

    public init(
        source: String? = nil, action: SoundAction = .doNothing, volume: Double = 1.0,
        order: PlaybackOrder = .sequential, repeatMode: RepeatMode = .all, resumable: Bool = false
    ) {
        self.source = source
        self.action = action
        self.volume = volume
        self.order = order
        self.repeatMode = repeatMode
        self.resumable = resumable
    }
}

public struct Transition: Sendable, Equatable {
    public var timing: ResolvedTiming
    public init(timing: ResolvedTiming) { self.timing = timing }
}

/// Which band of the resolution pipeline produced the decision.
public enum ResolutionBand: String, Sendable {
    case override        // Band 1: a pre-emptive override workspace matched
    case single          // Band 2: exactly one candidate
    case tiebreak        // Band 3: multiple candidates, a strategy decided
    case fallback        // Band 4: no candidate
}

/// A human-legible trace of *why* a workspace won — powers the dashboard "why" line
/// and the Conflict Simulator.
public struct ResolutionTrace: Sendable, Equatable {
    public var band: ResolutionBand
    public var winner: String?
    public var deciding: TiebreakStrategy?
    public var candidates: [String]
    public var weakOnly: [String]
    public var explanation: String
}

public struct Decision: Sendable, Equatable {
    public var activeWorkspace: String?
    public var target: AudioTarget
    public var transition: Transition
    public var reason: ResolutionTrace
}

// MARK: - Resolver state (carried between evaluations)

public struct ResolverState: Sendable, Equatable {
    /// The workspace currently considered active (for stickiness).
    public var activeWorkspace: String?
    /// Last time each workspace was active (for the `recency` strategy).
    public var lastActive: [String: Date]

    public init(activeWorkspace: String? = nil, lastActive: [String: Date] = [:]) {
        self.activeWorkspace = activeWorkspace
        self.lastActive = lastActive
    }
}

// MARK: - Match evaluation

/// The outcome of testing one workspace against a context.
struct MatchResult {
    var matched: Bool
    var strong: Bool       // false => matched only via a `weak` app (won't activate, only preserves)
    var specificity: Int   // number of matched dimensions; higher = more intentional
}

// MARK: - The resolver (pure)

public struct Resolver {
    public init() {}

    /// The whole ballgame: `(Context, Config, State) -> Decision`, pure and deterministic.
    public func resolve(context: Context, config: Config, state: ResolverState = ResolverState()) -> Decision {
        let enabled = config.workspaces.filter { $0.enabled }

        // ---- Band 1: override (pre-emptive) ----
        let overrides = enabled.filter { $0.isOverride && test($0, context, config.settings).matched }
        if !overrides.isEmpty {
            let (win, strat) = pick(overrides, chain: config.settings.normalizedTiebreak, context: context, config: config, state: state)
            return decide(win, context: context, config: config, band: .override,
                          deciding: overrides.count == 1 ? nil : strat,
                          candidates: overrides.map(\.id), weakOnly: [],
                          explanation: overrides.count == 1
                            ? "‘\(win.name)’ pre-empts as an override (\(matchSummary(win, context, config.settings)))."
                            : "‘\(win.name)’ pre-empts as an override, won by \(strat?.rawValue ?? "order") over \(others(overrides, win)).")
        }

        // ---- Band 2/3: candidates ----
        var strong: [Workspace] = []
        var weak: [Workspace] = []
        for ws in enabled where !ws.isOverride {
            let r = test(ws, context, config.settings)
            guard r.matched else { continue }
            if r.strong { strong.append(ws) } else { weak.append(ws) }
        }

        if !strong.isEmpty {
            // Stickiness: if we're already in a strongly-matching workspace, don't move.
            if config.settings.normalizedTiebreak.contains(.stickiness),
               let cur = state.activeWorkspace, let curWS = strong.first(where: { $0.id == cur }) {
                return decide(curWS, context: context, config: config,
                              band: strong.count == 1 ? .single : .tiebreak,
                              deciding: strong.count == 1 ? nil : .stickiness,
                              candidates: strong.map(\.id), weakOnly: weak.map(\.id),
                              explanation: strong.count == 1
                                ? "‘\(curWS.name)’ is the only match."
                                : "kept ‘\(curWS.name)’ (stickiness) over \(others(strong, curWS)).")
            }
            let (win, strat) = pick(strong, chain: config.settings.normalizedTiebreak, context: context, config: config, state: state)
            return decide(win, context: context, config: config,
                          band: strong.count == 1 ? .single : .tiebreak,
                          deciding: strong.count == 1 ? nil : strat,
                          candidates: strong.map(\.id), weakOnly: weak.map(\.id),
                          explanation: strong.count == 1
                            ? "‘\(win.name)’ is the only match."
                            : "‘\(win.name)’ won by \(strat?.rawValue ?? "order") over \(others(strong, win)).")
        }

        // ---- No strong candidates ----
        // A `weak` match means "don't disrupt": preserve the current workspace and
        // suppress the fallback. Weak matches never *start* audio on their own.
        if !weak.isEmpty {
            if let cur = state.activeWorkspace,
               let curWS = config.workspaces.first(where: { $0.id == cur && $0.enabled }) {
                return decide(curWS, context: context, config: config, band: .fallback,
                              deciding: nil, candidates: [], weakOnly: weak.map(\.id),
                              explanation: "kept ‘\(curWS.name)’ — only weak matches (\(weak.map(\.name).joined(separator: ", "))) present.")
            }
            // Nothing active: weak apps stay silent.
            return fallbackDecision(context: context, config: config, forceKeepNil: true,
                                    weakOnly: weak.map(\.id),
                                    note: "only weak matches; nothing active, so no change.")
        }

        // ---- Band 4: fallback (no match at all) ----
        return fallbackDecision(context: context, config: config, forceKeepNil: false, weakOnly: [], note: nil)
    }

    // MARK: Match testing

    func test(_ ws: Workspace, _ ctx: Context, _ settings: Settings) -> MatchResult {
        let m = ws.match
        var present = 0, matched = 0
        var appMatchedStrong = false
        var appMatchedWeak = false
        var nonAppMatched = false

        if !m.apps.isEmpty {
            present += 1
            if let app = ctx.frontmostApp {
                let entries = m.apps.filter { $0.bundle == app }
                if !entries.isEmpty {
                    matched += 1
                    // A bundle listed twice (once weak, once strong) should activate: the
                    // strong entry wins rather than whichever happened to be listed first.
                    if entries.contains(where: { $0.strength == .strong }) {
                        appMatchedStrong = true
                    } else {
                        appMatchedWeak = true
                    }
                }
            }
        }
        if !m.spaces.isEmpty {
            present += 1
            if let idx = ctx.activeSpace?.index, m.spaces.contains(idx) { matched += 1; nonAppMatched = true }
        }
        if !m.focus.isEmpty {
            present += 1
            if let f = ctx.focusMode, m.focus.contains(f) { matched += 1; nonAppMatched = true }
        }
        if let wantMeeting = m.meeting {
            present += 1
            if ctx.inMeeting(settings.meeting) == wantMeeting { matched += 1; nonAppMatched = true }
        }
        if let win = m.timeBetween {
            present += 1
            if win.contains(ctx.localTime) { matched += 1; nonAppMatched = true }
        }
        if !m.weekdays.isEmpty {
            present += 1
            let wd = Calendar.current.component(.weekday, from: ctx.localTime)
            if m.weekdays.contains(wd) { matched += 1; nonAppMatched = true }
        }

        // A match with no conditions never activates: candidacy requires at least one
        // matched dimension (PLAN.md §5). A freshly created workspace must stay inert
        // until the user gives it a condition.
        if present == 0 { return MatchResult(matched: false, strong: false, specificity: 0) }

        let didMatch = (m.combine == .all) ? (matched == present) : (matched > 0)
        // "strong" unless the *only* thing that got us in was a weak app.
        let strong = didMatch && (appMatchedStrong || nonAppMatched || (!appMatchedWeak))
        return MatchResult(matched: didMatch, strong: strong, specificity: matched)
    }

    // MARK: Tiebreak

    /// Narrow `candidates` down to a single winner following the strategy chain.
    func pick(_ candidates: [Workspace], chain: [TiebreakStrategy], context: Context,
              config: Config, state: ResolverState) -> (Workspace, TiebreakStrategy?) {
        var pool = candidates
        for strat in chain {
            if pool.count <= 1 { break }
            switch strat {
            case .stickiness:
                if let cur = state.activeWorkspace, let hit = pool.first(where: { $0.id == cur }) {
                    return (hit, .stickiness)
                }
            case .specificity:
                let best = pool.map { test($0, context, config.settings).specificity }.max() ?? 0
                let narrowed = pool.filter { test($0, context, config.settings).specificity == best }
                if narrowed.count < pool.count { pool = narrowed; if pool.count == 1 { return (pool[0], .specificity) } }
            case .priority:
                let best = pool.map(\.priority).max() ?? 0
                let narrowed = pool.filter { $0.priority == best }
                if narrowed.count < pool.count { pool = narrowed; if pool.count == 1 { return (pool[0], .priority) } }
            case .recency:
                let dates = pool.map { state.lastActive[$0.id] ?? .distantPast }
                // All candidates equally (usually never-)active: recency has no signal to
                // offer here, so fall through to the next strategy instead of picking
                // whichever happened to be first in the array and mislabeling it "recency".
                guard let first = dates.first, !dates.allSatisfy({ $0 == first }) else { continue }
                if let n = pool.max(by: { (state.lastActive[$0.id] ?? .distantPast) < (state.lastActive[$1.id] ?? .distantPast) }) {
                    return (n, .recency)
                }
            case .stableId:
                if let n = pool.min(by: { $0.id < $1.id }) { return (n, .stableId) }
            }
        }
        // Deterministic safety net.
        let win = pool.min(by: { $0.id < $1.id }) ?? candidates[0]
        return (win, pool.count == candidates.count ? nil : .stableId)
    }

    // MARK: Decision building

    private func decide(_ ws: Workspace, context: Context, config: Config, band: ResolutionBand,
                        deciding: TiebreakStrategy?, candidates: [String], weakOnly: [String],
                        explanation: String) -> Decision {
        let override = ws.sound.perApp[context.frontmostApp ?? ""]
        let target = AudioTarget(
            source: override?.source ?? ws.sound.source,
            action: ws.sound.action,
            volume: override?.volume ?? ws.sound.volume,
            order: ws.sound.order,
            repeatMode: ws.sound.repeatMode
        )
        let timing = ws.timing.resolved(over: config.settings.defaults)
        return Decision(
            activeWorkspace: ws.id,
            target: target,
            transition: Transition(timing: timing),
            reason: ResolutionTrace(band: band, winner: ws.id, deciding: deciding,
                                    candidates: candidates, weakOnly: weakOnly, explanation: explanation)
        )
    }

    private func fallbackDecision(context: Context, config: Config, forceKeepNil: Bool,
                                  weakOnly: [String], note: String?) -> Decision {
        let d = config.settings.defaults
        func trace(_ winner: String?, _ text: String) -> ResolutionTrace {
            ResolutionTrace(band: .fallback, winner: winner, deciding: nil,
                            candidates: [], weakOnly: weakOnly, explanation: note ?? text)
        }
        let fadeTiming = ResolvedTiming(fadeInMs: d.fadeInMs, fadeOutMs: config.settings.fallbackFadeMs,
                                        crossfadeMs: d.crossfadeMs, enterDelayMs: d.enterDelayMs,
                                        exitDelayMs: d.exitDelayMs, minDwellMs: d.minDwellMs)

        switch config.settings.fallback {
        case .keepCurrent where !forceKeepNil:
            return Decision(activeWorkspace: nil,
                            target: AudioTarget(action: .doNothing),
                            transition: Transition(timing: fadeTiming),
                            reason: trace(nil, "no workspace matches — keeping current audio."))
        case .resumePrevious where !forceKeepNil:
            return Decision(activeWorkspace: nil,
                            target: AudioTarget(action: .resumePrevious),
                            transition: Transition(timing: fadeTiming),
                            reason: trace(nil, "no workspace matches — resuming previous."))
        case .silence, .keepCurrent, .resumePrevious:
            // silence, or the forceKeepNil (nothing active) path. Marked resumable: this
            // is exactly the "nothing matches right now" transient state — a menu-bar
            // click, Mission Control, briefly tabbing away — where reappearing on the
            // same workspace a moment later should resume in place, not restart.
            return Decision(activeWorkspace: nil,
                            target: AudioTarget(action: .stop, volume: 0, resumable: true),
                            transition: Transition(timing: fadeTiming),
                            reason: trace(nil, note ?? "no workspace matches — fading to silence."))
        }
    }

    // MARK: Explanation helpers

    private func matchSummary(_ ws: Workspace, _ ctx: Context, _ s: Settings) -> String {
        var parts: [String] = []
        if let app = ctx.frontmostApp, ws.match.apps.contains(where: { $0.bundle == app }) { parts.append("app") }
        if let idx = ctx.activeSpace?.index, ws.match.spaces.contains(idx) { parts.append("space \(idx)") }
        if let f = ctx.focusMode, ws.match.focus.contains(f) { parts.append("focus \(f)") }
        if let want = ws.match.meeting, ctx.inMeeting(s.meeting) == want { parts.append("meeting") }
        return parts.isEmpty ? "catch-all" : parts.joined(separator: " + ")
    }

    private func others(_ list: [Workspace], _ win: Workspace) -> String {
        list.filter { $0.id != win.id }.map { "‘\($0.name)’" }.joined(separator: ", ")
    }
}
