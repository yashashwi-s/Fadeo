import Foundation
import UserNotifications
import AppKit

/// The opt-out preference for local notifications. Default on; a single toggle in
/// Preferences flips it. Nothing is ever posted while this is false, and even when true the
/// user still has to grant the system notification permission.
enum NotificationsPreference {
    private static let key = "fadeo.notifications.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Thin wrapper over `UNUserNotificationCenter` for local (not push) notifications — free,
/// no Apple Developer entitlement. Used sparingly: an available update, and a config file
/// that failed to parse. Clicking a notification that carries a URL opens it.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private override init() { super.init() }

    /// Set the delegate and ask for permission once, after launch. Declining just means no
    /// notifications ever appear; the in-app opt-out is separate and also respected.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String, url: URL? = nil, id: String = UUID().uuidString) {
        guard NotificationsPreference.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show the banner even when Fadeo happens to be frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Open the carried URL (e.g. the release page) when the notification is clicked.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
