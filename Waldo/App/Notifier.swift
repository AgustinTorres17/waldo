import Foundation
import UserNotifications

/// Shows errors and results as user notifications. Never touches the user's text.
@MainActor
enum Notifier {
    private static var hasRequestedAuthorization = false

    static func show(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            if !hasRequestedAuthorization {
                hasRequestedAuthorization = true
                _ = try? await center.requestAuthorization(options: [.alert])
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    static func showError(_ error: Error) {
        show(title: "Waldo couldn't process the text", body: error.localizedDescription)
    }
}
