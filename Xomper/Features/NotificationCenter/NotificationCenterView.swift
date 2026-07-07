import SwiftUI

struct NotificationCenterView: View {
    @Environment(NotificationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.notifications.isEmpty {
                    emptyState
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if !store.notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Mark All as Read") {
                                store.markAllAsRead()
                            }
                            Button("Clear All", role: .destructive) {
                                store.clearAll()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Notifications",
            systemImage: "bell.slash",
            description: Text("You're all caught up!")
        )
    }

    private var notificationList: some View {
        List {
            ForEach(store.notifications) { notification in
                NotificationRow(notification: notification)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.delete(notification.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !notification.isRead {
                            Button {
                                store.markAsRead(notification.id)
                            } label: {
                                Label("Read", systemImage: "checkmark")
                            }
                            .tint(.blue)
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    @Environment(NotificationStore.self) private var store
    @Environment(PushNotificationManager.self) private var pushManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Unread indicator
                Circle()
                    .fill(notification.isRead ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundStyle(notification.isRead ? .secondary : .primary)

                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(notification.receivedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleTap() {
        store.markAsRead(notification.id)

        // Parse and set deep link
        if let linkString = notification.deepLink,
           let url = URL(string: linkString),
           let deepLink = NotificationDeepLink.from(url: url) {
            pushManager.pendingDeepLink = deepLink
            dismiss()
        } else if let category = notification.category,
                  let deepLink = NotificationDeepLink.from(userInfo: ["category": category]) {
            pushManager.pendingDeepLink = deepLink
            dismiss()
        }
    }
}

#Preview {
    NotificationCenterView()
        .environment(NotificationStore.shared)
        .environment(PushNotificationManager.shared)
}
