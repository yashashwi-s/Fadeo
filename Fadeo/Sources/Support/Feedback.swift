import Foundation

/// The user's 1-5 star rating, if they've rated. Stored locally and also included in the
/// opt-in diagnostics summary + sent immediately when they submit feedback.
enum RatingPreference {
    private static let key = "fadeo.rating"
    static var value: Int? {
        get { let v = UserDefaults.standard.integer(forKey: key); return (1...5).contains(v) ? v : nil }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: key) }
    }
}

/// Sends an in-app rating + optional written feedback to the PureMac hub so it shows up on
/// the diagnostics dashboard. Unlike the daily diagnostics ping this is sent immediately on
/// submit. Carries the same anonymous installID so ratings/feedback can be tied to an
/// install's usage shape without any personal data.
enum FeedbackSender {
    private static let endpoint = URL(string: "https://puremac.yashashwi.me/api/fadeo-feedback")!

    static func send(installID: String, rating: Int?, text: String, completion: @escaping (Bool) -> Void) {
        var payload: [String: Any] = [
            "installID": installID,
            "text": text,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        if let rating { payload["rating"] = rating }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { completion(false); return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
}
