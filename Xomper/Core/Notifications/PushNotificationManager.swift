import Foundation
import UserNotifications
import UIKit

@Observable
@MainActor
final class PushNotificationManager: NSObject, Sendable {

    // MARK: - State

    private(set) var deviceToken: String?
    private(set) var permissionGranted = false

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
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
