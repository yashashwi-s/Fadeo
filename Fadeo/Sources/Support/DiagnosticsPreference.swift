import Foundation

/// The opt-in preference for sharing a coarse, anonymous usage summary
/// (UsageStats.shareableSummary). Separate from local usage tracking itself, which
/// always runs because it's useful to the user directly (see UsageStore). When (and
/// only when) this is true, DiagnosticsUploader sends the summary to the PureMac hub,
/// at most once a day. Nothing is ever sent while this is false.
enum DiagnosticsPreference {
    private static let key = "fadeo.diagnostics.optIn"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
