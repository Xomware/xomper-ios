import SwiftUI

/// Admin portal — only visible when the signed-in
/// `whitelistedUser.isAdmin == true`. Two sections:
/// 1. **Test sender** — fire any of the production push/email
///    templates back to yourself so you can preview formatting +
///    confirm the channel is working.
/// 2. **Activity feed** — last 200 push + email send attempts
///    (success + failure), filterable by channel and status.
///
/// Backend gating is enforced server-side via the `is_admin` flag
/// on `whitelisted_users`; this view also hides the destination
/// for non-admins so they never see the menu entry.
struct AdminView: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    @State private var store = AdminStore()

    var body: some View {
        Group {
            if !isAdmin {
                EmptyStateView(
                    icon: "lock.shield",
                    title: "Admin only",
                    message: "Your account doesn't have admin permission. Ask the commissioner to flip your is_admin flag."
                )
            } else {
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: callerSleeperId) {
            await store.refresh(sleeperUserId: callerSleeperId)
        }
        .refreshable {
            await store.refresh(sleeperUserId: callerSleeperId)
        }
    }

    private var isAdmin: Bool {
        authStore.whitelistedUser?.isAdmin == true
    }

    private var callerSleeperId: String {
        authStore.sleeperUserId ?? ""
    }

    private var callerEmail: String? {
        authStore.session?.user.email
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                testSenderCard

                if let result = store.lastTestResult {
                    Text(result)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.hasPrefix("✓") ? XomperColors.successGreen : XomperColors.errorRed)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                }

                filterBar

                if store.isLoading && store.entries.isEmpty {
                    LoadingView(message: "Loading activity…")
                        .padding(.top, XomperTheme.Spacing.xl)
                } else if let error = store.lastError, store.entries.isEmpty {
                    ErrorView(message: error) {
                        Task { await store.refresh(sleeperUserId: callerSleeperId) }
                    }
                } else if store.entries.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "No activity",
                        message: "No push or email sends recorded in the last 7 days for the current filters."
                    )
                    .padding(.top, XomperTheme.Spacing.lg)
                } else {
                    ForEach(store.entries) { entry in
                        activityRow(entry)
                    }
                }
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    // MARK: - Test sender

    private var testSenderCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test sender")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text("Fire any production template back to your account. Push titles arrive prefixed with 🧪.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            ForEach(AdminTestKind.allCases) { kind in
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text(kind.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                    Spacer()

                    Button {
                        Task {
                            await store.sendTest(
                                kind: kind,
                                sleeperUserId: callerSleeperId,
                                email: kind.hasEmail ? callerEmail : nil,
                                channels: kind.hasEmail ? ["push", "email"] : ["push"]
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.hasEmail ? "paperplane.fill" : "iphone.gen3")
                                .font(.caption2)
                            Text(kind.hasEmail ? "Push + email" : "Push")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(minHeight: 32)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.pressableCard)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Activity · last 7 days")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)

            HStack(spacing: XomperTheme.Spacing.sm) {
                Picker("Channel", selection: $store.filterKind) {
                    ForEach(AdminStore.KindFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Status", selection: $store.filterStatus) {
                    ForEach(AdminStore.StatusFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            .onChange(of: store.filterKind) { _, _ in
                Task { await store.refresh(sleeperUserId: callerSleeperId) }
            }
            .onChange(of: store.filterStatus) { _, _ in
                Task { await store.refresh(sleeperUserId: callerSleeperId) }
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Activity row

    private func activityRow(_ entry: AdminNotificationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: entry.isPush ? "iphone.gen3" : "envelope.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.isPush ? Color.cyan : XomperColors.championGold)
                Text(entry.isPush ? "PUSH" : "EMAIL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .tracking(0.5)
                Text(entry.isSuccess ? "✓" : "✗")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(entry.isSuccess ? XomperColors.successGreen : XomperColors.errorRed)
                Spacer()
                Text(formattedTimestamp(entry.date))
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }

            if entry.isPush {
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                }
                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(2)
                }
                if let userId = entry.userId, !userId.isEmpty {
                    Text("user: \(userId)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                }
            } else {
                if let subject = entry.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                }
                if let recipient = entry.recipient, !recipient.isEmpty {
                    Text(recipient)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(1)
                }
                if let snippet = entry.bodySnippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .lineLimit(2)
                }
            }

            if let err = entry.error, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.errorRed)
                    .lineLimit(2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(
                    entry.isSuccess ? Color.clear : XomperColors.errorRed.opacity(0.4),
                    lineWidth: entry.isSuccess ? 0 : 1
                )
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss a"
        return formatter.string(from: date)
    }
}
