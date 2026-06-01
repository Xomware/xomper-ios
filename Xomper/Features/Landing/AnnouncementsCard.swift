import SwiftUI

/// Renders the league announcements list as a stacked set of compact
/// cards. v2 reads from `AnnouncementsStore.announcements` (backed by
/// Supabase via `/announcements`). Expired entries (`expiresAt < now`)
/// are filtered out client-side as a defensive guard against
/// stale-cache rendering; the backend already applies the same filter.
///
/// When the filtered list is empty, the card renders zero-height —
/// the Landing page collapses around it instead of showing an empty
/// state. Announcements are an opportunistic surface, not a required
/// one.
///
/// Body text is rendered via `AttributedString(markdown:)` so the
/// admin can bold key dates / italicise + add links. Falls back to
/// plain `Text` on parse failure.
struct AnnouncementsCard: View {
    var store: AnnouncementsStore

    /// Filtered + sorted list. Computed at render time so date-based
    /// expiry kicks in without any timers / observers.
    private var visible: [LeagueAnnouncement] {
        let now = Date()
        return store.announcements
            .filter { entry in
                guard entry.isActive else { return false }
                guard let expiresAt = entry.expiresAt else { return true }
                return expiresAt > now
            }
            .sorted { a, b in
                // critical (priority order 0) before info (1), then by
                // display_order ascending within a priority bucket.
                let aOrder = priorityOrder(a.priority)
                let bOrder = priorityOrder(b.priority)
                if aOrder != bOrder { return aOrder < bOrder }
                return a.displayOrder < b.displayOrder
            }
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                    sectionHeader

                    VStack(spacing: XomperTheme.Spacing.sm) {
                        ForEach(visible) { entry in
                            AnnouncementRow(announcement: entry)
                        }
                    }
                }
            }
        }
        .task {
            await store.load()
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Image(systemName: "megaphone.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
            Text("ANNOUNCEMENTS")
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.xs)
        .accessibilityHidden(true)
    }

    private func priorityOrder(_ priority: LeagueAnnouncement.Priority) -> Int {
        switch priority {
        case .critical: 0
        case .info:     1
        }
    }
}

/// Single announcement row. Critical entries get a 3pt-wide red left
/// edge accent; info entries are plain `bgCard`. Body renders as
/// markdown when parseable; otherwise falls back to plain text.
private struct AnnouncementRow: View {
    let announcement: LeagueAnnouncement

    var body: some View {
        HStack(spacing: 0) {
            if announcement.priority == .critical {
                Rectangle()
                    .fill(XomperColors.accentRed)
                    .frame(width: 3)
            }

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    if announcement.priority == .critical {
                        Text("CRITICAL")
                            .font(.caption2.weight(.bold))
                            .tracking(0.5)
                            .foregroundStyle(XomperColors.accentRed)
                    }
                    Text(announcement.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(2)
                    Spacer()
                }

                bodyText
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(announcement.priority == .critical ? "Critical: " : "")\(announcement.title). \(announcement.body)")
    }

    /// Markdown-aware body. `AttributedString(markdown:)` honours
    /// **bold**, _italic_, [links](url), and inline code. On parse
    /// failure (malformed input), fall back to plain `Text` so a
    /// single bad row doesn't blank the card.
    @ViewBuilder
    private var bodyText: some View {
        if let attributed = try? AttributedString(
            markdown: announcement.body,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
        } else {
            Text(announcement.body)
        }
    }
}

#Preview {
    AnnouncementsCard(store: AnnouncementsStore())
        .padding()
        .background(XomperColors.bgDark)
        .preferredColorScheme(.dark)
}
