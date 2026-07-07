import Foundation
import UserNotifications
import UIKit

@Observable
@MainActor
final class PushNotificationManager: NSObject, Sendable {

    // MARK: - State

    private(set) var deviceToken: String?
    private(set) var permissionGranted = false

    /// Pending deep link from notification tap (consumed by MainShell)
    var pendingDeepLink: NotificationDeepLink?

    // MARK: - Shared Instance

    /// Shared instance used by AppDelegate for token forwarding.
    static let shared = PushNotificationManager()

    // MARK: - Permission

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            permissionGranted = granted

            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            permissionGranted = false
        }
    }

    // MARK: - Token Handling

    func registerDeviceToken(_ tokenData: Data) {
        let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = hexToken
    }

    func handleRegistrationError(_ error: Error) {
        deviceToken = nil
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound when app is in foreground
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract values from userInfo before crossing actor boundary
        let userInfo = response.notification.request.content.userInfo
        let category = userInfo["category"] as? String
        let linkString = userInfo["link"] as? String

        // Parse deep link on main actor
        Task { @MainActor in
            if let category {
                switch category {
                case "trade": self.pendingDeepLink = .tradeCenter
                case "weekly_recap", "news": self.pendingDeepLink = .news
                case "matchup": self.pendingDeepLink = .matchups
                case "draft", "mock": self.pendingDeepLink = .mocks
                default: break
                }
            } else if let linkString,
                      let url = URL(string: linkString),
                      let deepLink = NotificationDeepLink.from(url: url) {
                self.pendingDeepLink = deepLink
            }
        }

        completionHandler()
    }
}

// MARK: - Deep Link

enum NotificationDeepLink: Equatable, Sendable {
    case news
    case tradeCenter
    case matchups
    case mocks
    case myTeam

    static func from(url: URL) -> NotificationDeepLink? {
        guard url.scheme == "xomper" else { return nil }

        switch url.host {
        case "news": return .news
        case "trade", "trades": return .tradeCenter
        case "matchups": return .matchups
        case "mocks", "draft": return .mocks
        case "team", "my-team": return .myTeam
        default: return nil
        }
    }
}
