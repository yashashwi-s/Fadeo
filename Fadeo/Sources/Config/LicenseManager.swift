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
        // Free-giveaway keys carry a deadline: unused (never entered here) for 7 days
        // and they expire. Checked only at this first-activation moment, never again —
        // an already-saved key in init() is trusted permanently regardless of this date.
        if let deadline = payload.mustActivateBy, Date() > deadline {
            licenseError = "This free license expired unused (it had to be activated within 7 days of being issued). Contact support if you believe this is an error."
            return false
        }
        UserDefaults.standard.set(key, forKey: Self.licenseKeyDefaultsKey)
        status = .licensed(payload)
        licenseError = nil
        // Free-giveaway keys have a slot in the "first 100" pool; tell the server this one
        // was activated so its slot isn't reclaimed. Paid keys (no mustActivateBy) have no
        // slot to protect, so they never ping.
        if payload.mustActivateBy != nil { pingActivation(key) }
        return true
    }

    /// Best-effort, one-time, anonymous ping so the server leaves an activated giveaway key's
    /// slot claimed (see the promo reclaim sweep). Sends only the key itself, which the user
    /// already holds: no email, no usage, no personal data. Fire-and-forget, since activation
    /// is fully offline and must never depend on this succeeding.
    private func pingActivation(_ key: String) {
        guard let url = URL(string: "https://puremac.yashashwi.me/api/fadeo-activate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key])
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request).resume()
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
