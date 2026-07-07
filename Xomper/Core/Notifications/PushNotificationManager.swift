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

    // MARK: - Token Waiters

    /// Continuations waiting for the APNs token to arrive
    private var tokenWaiters: [CheckedContinuation<String?, Never>] = []

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

    /// Request permission and wait for the APNs token (with timeout).
    /// Returns the hex token string or nil if permission denied / timeout.
    func requestPermissionAndToken(timeout: TimeInterval = 10) async -> String? {
        // If we already have a token, return it immediately
        if let existing = deviceToken {
            return existing
        }

        await requestPermission()

        guard permissionGranted else { return nil }

        // Wait for token with timeout
        return await withCheckedContinuation { continuation in
            tokenWaiters.append(continuation)

            // Timeout after specified seconds
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    // If this waiter is still pending, resume with nil
                    if let idx = tokenWaiters.firstIndex(where: { $0 == continuation }) {
                        tokenWaiters.remove(at: idx)
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: - Token Handling

    func registerDeviceToken(_ tokenData: Data) {
        let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = hexToken

        // Resume all waiting continuations
        let waiters = tokenWaiters
        tokenWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: hexToken)
        }
    }

    func handleRegistrationError(_ error: Error) {
        deviceToken = nil

        // Resume all waiting continuations with nil
        let waiters = tokenWaiters
        tokenWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Record to notification store for in-app center
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            NotificationStore.shared.recordNotification(
                title: notification.request.content.title,
                body: notification.request.content.body,
                userInfo: userInfo
            )
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        Task { @MainActor in
            // Parse deep link from payload
            if let deepLink = NotificationDeepLink.from(userInfo: userInfo) {
                pendingDeepLink = deepLink
            }
        }

        completionHandler()
    }
}

// MARK: - Deep Link

enum NotificationDeepLink: Equatable {
    case news
    case tradeCenter
    case matchups
    case mocks
    case myTeam
    case notificationCenter

    static func from(userInfo: [AnyHashable: Any]) -> NotificationDeepLink? {
        // Check for explicit link URL
        if let linkString = userInfo["link"] as? String,
           let url = URL(string: linkString) {
            return from(url: url)
        }

        // Check for category-based routing
        if let category = userInfo["category"] as? String {
            switch category {
            case "trade": return .tradeCenter
            case "weekly_recap", "news": return .news
            case "matchup": return .matchups
            case "draft", "mock": return .mocks
            default: return nil
            }
        }

        return nil
    }

    static func from(url: URL) -> NotificationDeepLink? {
        guard url.scheme == "xomper" else { return nil }

        switch url.host {
        case "news": return .news
        case "trade", "trades": return .tradeCenter
        case "matchups": return .matchups
        case "mocks", "draft": return .mocks
        case "team", "my-team": return .myTeam
        case "notifications": return .notificationCenter
        default: return nil
        }
    }
}
