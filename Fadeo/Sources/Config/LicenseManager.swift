import Foundation
import FadeoCore

public enum LicenseStatus: Equatable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed(LicensePayload)
}

/// Trial anchoring and license verification. Never gates functionality (PLAN.md §13) —
/// this class only computes *status*; nothing in the audio pipeline reads it. It exists
/// purely to drive the soft nag and the About pane's license display.
///
/// The anchor deliberately does NOT use Keychain. Keychain was tried first ("survives
/// reinstall") and reverted: every access can raise the login-keychain password dialog
/// (always, for a re-signed binary — which is every dev build, and every update of an
/// ad-hoc-signed app). A scary system password prompt at first launch is a far worse
/// cost than a resettable trial for an app whose license never locks anything anyway —
/// resetting the trial by deleting app data is equivalent to just ignoring the soft nag.
@MainActor
final class LicenseManager: ObservableObject {
    static let trialDays = 14

    @Published private(set) var status: LicenseStatus
    @Published var licenseError: String?

    private static let firstLaunchDefaultsKey = "fadeo.trial.firstLaunch"
    private static let licenseKeyDefaultsKey = "fadeo.license.key"

    private static var anchorFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fadeo", isDirectory: true)
            .appendingPathComponent(".trial-anchor")
    }

    /// Earliest surviving record wins, so neither clearing defaults nor deleting the
    /// file alone restarts the clock; a fresh install writes both as "now".
    private static func loadOrCreateAnchor() -> Date {
        let formatter = ISO8601DateFormatter()
        var candidates: [Date] = []
        if let raw = UserDefaults.standard.string(forKey: firstLaunchDefaultsKey),
           let d = formatter.date(from: raw) {
            candidates.append(d)
        }
        if let raw = try? String(contentsOf: anchorFileURL, encoding: .utf8),
           let d = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            candidates.append(d)
        }
        let anchor = candidates.min() ?? Date()
        let encoded = formatter.string(from: anchor)
        UserDefaults.standard.set(encoded, forKey: firstLaunchDefaultsKey)
        try? FileManager.default.createDirectory(at: anchorFileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? encoded.write(to: anchorFileURL, atomically: true, encoding: .utf8)
        return anchor
    }

    init() {
        let anchor = Self.loadOrCreateAnchor()

        if let savedKey = UserDefaults.standard.string(forKey: Self.licenseKeyDefaultsKey),
           let payload = License.verify(savedKey) {
            status = .licensed(payload)
        } else {
            let elapsed = Calendar.current.dateComponents([.day], from: anchor, to: Date()).day ?? 0
            let remaining = Self.trialDays - elapsed
            status = remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
        }
    }

    /// Validates and, if valid, persists a pasted license key. Returns whether it worked
    /// so the UI can show immediate feedback.
    @discardableResult
    func activate(_ key: String) -> Bool {
        guard let payload = License.verify(key) else {
            licenseError = "That license key isn't valid. Check for typos, or contact support if you believe this is an error."
            return false
        }
        UserDefaults.standard.set(key, forKey: Self.licenseKeyDefaultsKey)
        status = .licensed(payload)
        licenseError = nil
        return true
    }

    var isLicensed: Bool {
        if case .licensed = status { return true }
        return false
    }

    var shouldShowNag: Bool {
        if case .trialExpired = status { return true }
        return false
    }
}
