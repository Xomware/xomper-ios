import SwiftUI

/// Admin → Announcements list (announcements feature).
///
/// Lists every row from `league_announcements` via
/// `GET /admin/announcements-list` (active + inactive + expired). Each
/// row surfaces the title, priority chip, and status chips
/// (ACTIVE / INACTIVE / EXPIRED) so the admin can scan the state at
/// a glance. Tap a row → push `.adminAnnouncementEdit(id: row.id)`.
/// Top-trailing toolbar "+ New" → push
/// `.adminAnnouncementEdit(id: nil)` (empty form).
struct AnnouncementsListView: View {
    var store: AnnouncementsStore
    var router: AppRouter

    @State private var deleteCandidate: LeagueAnnouncement?

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Announcements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { newToolbar }
            .task {
                if store.adminAnnouncements.isEmpty {
                    await store.loadAdmin()
                }
            }
            .refreshable {
                await store.loadAdmin()
            }
            .alert(
                "Soft-delete this announcement?",
                isPresented: deleteAlertBinding,
                presenting: deleteCandidate
            ) { row in
                Button("Delete", role: .destructive) {
                    Task { await performDelete(id: row.id) }
                }
                Button("Cancel", role: .cancel) {
                    deleteCandidate = nil
                }
            } message: { row in
                Text("'\(row.title)' will be hidden from the Landing page. The row stays in Supabase so the audit trail is preserved — you can re-activate it from the edit form.")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoadingAdmin && store.adminAnnouncements.isEmpty {
            LoadingView(message: "Loading announcements…")
        } else if store.tableMissing {
            EmptyStateView(
                icon: "tablecells.badge.ellipsis",
                title: "Migration pending",
                message: "The Supabase 'league_announcements' table hasn't been created yet. Apply the migration from the backend repo, then refresh."
            )
        } else if let error = store.adminError, store.adminAnnouncements.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't load announcements",
                message: error
            )
        } else if store.adminAnnouncements.isEmpty {
            EmptyStateView(
                icon: "megaphone",
                title: "No announcements yet",
                message: "Tap + to create the first one."
            )
        } else {
            ScrollView {
                VStack(spacing: XomperTheme.Spacing.sm) {
                    if let lastWriteError = store.lastWriteError {
                        ErrorBanner(text: lastWriteError)
                    }
                    ForEach(store.adminAnnouncements) { row in
                        AnnouncementAdminRow(
                            announcement: row,
                            isPending: store.pendingIds.contains(row.id),
                            onTap: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                router.navigate(to: .adminAnnouncementEdit(id: row.id))
                            },
                            onDelete: {
                                deleteCandidate = row
                            }
                        )
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        }
    }

    // MARK: - New toolbar

    @ToolbarContentBuilder
    private var newToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                router.navigate(to: .adminAnnouncementEdit(id: nil))
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }
            .accessibilityLabel("New announcement")
        }
    }

    // MARK: - Alert binding

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { newValue in
                if !newValue { deleteCandidate = nil }
            }
        )
    }

    // MARK: - Delete

    private func performDelete(id: UUID) async {
        let generator = UINotificationFeedbackGenerator()
        do {
            try await store.delete(id: id)
            generator.notificationOccurred(.success)
        } catch {
            generator.notificationOccurred(.error)
        }
        deleteCandidate = nil
    }
}

// MARK: - Row

private struct AnnouncementAdminRow: View {
    let announcement: LeagueAnnouncement
    let isPending: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                if announcement.priority == .critical {
                    Rectangle()
                        .fill(XomperColors.accentRed)
                        .frame(width: 3)
                }

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Text(announcement.title)
                            .font(.headline)
                            .foregroundStyle(XomperColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer()
                        if isPending {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(XomperColors.championGold)
                                .accessibilityHidden(true)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(XomperColors.textMuted)
                            .accessibilityHidden(true)
                    }

                    if !announcement.body.isEmpty {
                        Text(announcement.body)
                            .font(.caption)
                            .foregroundStyle(XomperColors.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: XomperTheme.Spacing.xs) {
                        chip(
                            text: announcement.priority == .critical ? "CRITICAL" : "INFO",
                            color: announcement.priority == .critical ? XomperColors.accentRed : XomperColors.textMuted
                        )
                        chip(
                            text: announcement.isActive ? "ACTIVE" : "INACTIVE",
                            color: announcement.isActive ? XomperColors.successGreen : XomperColors.textMuted
                        )
                        if isExpired {
                            chip(text: "EXPIRED", color: XomperColors.errorRed)
                        }
                        Spacer()
                        Text("#\(announcement.displayOrder)")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }
                .padding(XomperTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(XomperColors.championGold.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to edit, swipe left to delete")
    }

    private var accessibilityLabel: String {
        var parts = [announcement.title]
        parts.append(announcement.priority == .critical ? "Critical" : "Info")
        parts.append(announcement.isActive ? "Active" : "Inactive")
        if isExpired { parts.append("Expired") }
        return parts.joined(separator: ", ")
    }

    private var isExpired: Bool {
        guard let expiresAt = announcement.expiresAt else { return false }
        return expiresAt <= Date()
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

// MARK: - Inline error banner

private struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(XomperColors.errorRed)
            Text(text)
                .font(.footnote)
                .foregroundStyle(XomperColors.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.errorRed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }
}
