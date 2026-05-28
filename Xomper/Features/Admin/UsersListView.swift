import SwiftUI

/// Admin → Tables → Users (F4).
///
/// Lists every row from `whitelisted_users` (via
/// `GET /admin/users-list`). Each row surfaces the display name,
/// email, and role + status chips so the admin can scan permissions
/// at a glance. Tap → push `.adminTablesUserEdit(userId:)`.
struct UsersListView: View {
    var store: AdminTablesStore
    var router: AppRouter

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Users")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.users.isEmpty {
                    await store.loadUsers()
                }
            }
            .refreshable {
                await store.loadUsers()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingUsers && store.users.isEmpty {
            LoadingView(message: "Loading users…")
        } else if let error = store.usersError, store.users.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't load users",
                message: error
            )
        } else if store.users.isEmpty {
            EmptyStateView(
                icon: "person.3",
                title: "No users",
                message: "Whitelisted users will appear here once they're added in Supabase."
            )
        } else {
            ScrollView {
                VStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(store.users) { user in
                        UserRow(user: user) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            router.navigate(to: .adminTablesUserEdit(userId: user.updateKey))
                        }
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        }
    }
}

// MARK: - Row

private struct UserRow: View {
    let user: WhitelistedUser
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XomperTheme.Spacing.md) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 36, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(user.resolvedDisplayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    Text(user.email.isEmpty ? "(no email)" : user.email)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.xs) {
                        chip(
                            text: user.isAdmin ? "Admin" : "Member",
                            color: user.isAdmin ? XomperColors.championGold : XomperColors.textMuted
                        )
                        chip(
                            text: user.isActive ? "Active" : "Inactive",
                            color: user.isActive ? XomperColors.successGreen : XomperColors.errorRed
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(XomperColors.championGold.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.resolvedDisplayName), \(user.isAdmin ? "admin" : "member"), \(user.isActive ? "active" : "inactive")")
        .accessibilityHint("Double tap to edit")
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, XomperTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
