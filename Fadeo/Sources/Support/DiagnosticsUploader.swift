import Foundation
import FadeoCore

/// Sends the opt-in coarse usage summary (`UsageStats.shareableSummary`) to the PureMac
/// hub's ingestion endpoint. This is the seam `DiagnosticsPreference` was built for —
/// nothing is ever sent unless the user opted in, and even then at most once a day.
/// Fire-and-forget: no queue, no retry loop. A failed or skipped send just tries again
/// next launch, which keeps this from ever becoming a background poller (see CLAUDE.md's
/// efficiency contract).
enum DiagnosticsUploader {
    private static let endpoint = URL(string: "https://puremac.yashashwi.me/api/fadeo-diagnostics")!
    private static let lastSentKey = "fadeo.diagnostics.lastSentAt"
    private static let minInterval: TimeInterval = 20 * 60 * 60

    static func uploadIfDue(summary: ShareableUsageSummary) {
        guard DiagnosticsPreference.isEnabled else { return }
        if let lastSent = UserDefaults.standard.object(forKey: lastSentKey) as? Date,
           Date().timeIntervalSince(lastSent) < minInterval {
            return
        }

        let payload: [String: Any] = [
            "installID": summary.installID,
            "daysSinceFirstLaunch": summary.daysSinceFirstLaunch,
            "sessionCount": summary.sessionCount,
            "workspaceCount": summary.workspaceCount,
            "totalSwitches": summary.totalSwitches,
            "totalActiveSeconds": summary.totalActiveSeconds,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        // Recorded before the network call resolves: this is a best-effort ping, not a
        // guaranteed delivery, and treating it that way is what keeps a hub outage or a
        // temporarily offline Mac from turning into a retry-every-launch loop.
        UserDefaults.standard.set(Date(), forKey: lastSentKey)
        URLSession.shared.dataTask(with: request).resume()
    }
}
