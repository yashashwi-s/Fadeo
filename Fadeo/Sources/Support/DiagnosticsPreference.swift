import Foundation

/// The opt-in preference for sharing a coarse, anonymous usage summary
/// (UsageStats.shareableSummary). Separate from local usage tracking itself, which
/// always runs because it's useful to the user directly (see UsageStore). No actual
/// network submission exists yet, there is nowhere to send it to (see PLAN.md's
/// deferred PureMac hub) — this stores the preference and is the seam where sending
/// will attach once that exists. Never sends anything without this being true.
enum DiagnosticsPreference {
    private static let key = "fadeo.diagnostics.optIn"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
