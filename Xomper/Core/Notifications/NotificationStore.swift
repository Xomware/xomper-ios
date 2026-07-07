import Foundation

/// Persisted in-app notification for the notification center.
struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let category: String?
    let deepLink: String?
    let receivedAt: Date
    var isRead: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        category: String? = nil,
        deepLink: String? = nil,
        receivedAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.deepLink = deepLink
        self.receivedAt = receivedAt
        self.isRead = isRead
    }
}

/// Local store for in-app notification center. Persists to UserDefaults.
@Observable
@MainActor
final class NotificationStore {

    // MARK: - Singleton

    static let shared = NotificationStore()

    // MARK: - State

    private(set) var notifications: [AppNotification] = []

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Constants

    private let maxNotifications = 100
    private let storageKey = "xomper_app_notifications"

    // MARK: - Init

    private init() {
        loadFromStorage()
    }

    // MARK: - Public API

    func recordNotification(
        title: String,
        body: String,
        userInfo: [AnyHashable: Any]
    ) {
        let category = userInfo["category"] as? String
        let deepLink = userInfo["link"] as? String

        // Dedupe by title+body within last minute
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        if notifications.contains(where: {
            $0.title == title && $0.body == body && $0.receivedAt > oneMinuteAgo
        }) {
            return
        }

        let notification = AppNotification(
            title: title,
            body: body,
            category: category,
            deepLink: deepLink
        )

        notifications.insert(notification, at: 0)

        // Cap at max
        if notifications.count > maxNotifications {
            notifications = Array(notifications.prefix(maxNotifications))
        }

        saveToStorage()
    }

    func markAsRead(_ id: String) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[idx].isRead = true
        saveToStorage()
    }

    func markAllAsRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        saveToStorage()
    }

    func delete(_ id: String) {
        notifications.removeAll { $0.id == id }
        saveToStorage()
    }

    func clearAll() {
        notifications.removeAll()
        saveToStorage()
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AppNotification].self, from: data)
        else { return }
        notifications = decoded
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
