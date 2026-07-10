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
@MainActor
final class LicenseManager: ObservableObject {
    static let trialDays = 14

    @Published private(set) var status: LicenseStatus
    @Published var licenseError: String?

    private static let firstLaunchKey = "firstLaunchDate"
    private static let licenseKeyDefaultsKey = "fadeo.license.key"

    init() {
        // Anchor in Keychain (survives delete+reinstall) rather than UserDefaults.
        let anchor: Date
        if let raw = KeychainStore.read(Self.firstLaunchKey), let stored = ISO8601DateFormatter().date(from: raw) {
            anchor = stored
        } else {
            anchor = Date()
            KeychainStore.write(Self.firstLaunchKey, value: ISO8601DateFormatter().string(from: anchor))
        }

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
