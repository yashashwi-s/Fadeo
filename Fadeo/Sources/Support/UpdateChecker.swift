import Foundation
import AppKit

/// Lightweight stand-in for an in-app auto-updater (Sparkle was removed — it broke the
/// window on the macOS beta, see PLAN.md §15). Checks the GitHub "latest release" tag
/// against the running version at most once/day and, if a newer one exists, posts a
/// notification linking to the release page. Just a URLSession call — no framework, no
/// window interference. Users install updates via Homebrew (`brew upgrade`) or the page.
enum UpdateChecker {
    private static let latestAPI = URL(string: "https://api.github.com/repos/yashashwi-s/Fadeo/releases/latest")!
    private static let releasePage = URL(string: "https://github.com/yashashwi-s/Fadeo/releases/latest")!
    private static let lastCheckKey = "fadeo.update.lastCheckAt"
    private static let minInterval: TimeInterval = 20 * 60 * 60

    static func checkIfDue() {
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < minInterval { return }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: latestAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard isNewer(latest, than: current) else { return }
            Task { @MainActor in
                Notifier.shared.notify(
                    title: "Fadeo \(latest) is available",
                    body: "You're on \(current). Click to view the release, or run brew upgrade if you installed via Homebrew.",
                    url: releasePage,
                    id: "fadeo.update.\(latest)"
                )
            }
        }.resume()
    }

    /// Dotted numeric compare (e.g. 0.3.0 vs 0.2.1); non-numeric parts count as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
