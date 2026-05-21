import SwiftUI

/// Renders the hardcoded `LeagueAnnouncements.current` list as a
/// stacked set of compact cards. Expired entries (`expiresAt < now`)
/// are filtered out; remaining entries sort critical-first, then by
/// the order they appear in the source array.
///
/// When the filtered list is empty, the card renders zero-height —
/// the Landing page collapses around it instead of showing an empty
/// state. Announcements are an opportunistic surface, not a required
/// one.
struct AnnouncementsCard: View {
    /// Filtered + sorted list. Computed at render time so date-based
    /// expiry kicks in without any timers / observers.
    private var visible: [LeagueAnnouncement] {
        let now = Date()
        return LeagueAnnouncements.current
            .filter { entry in
                guard let expiresAt = entry.expiresAt else { return true }
                return expiresAt > now
            }
            .sorted { a, b in
                // critical (priority order 0) before info (1)
                priorityOrder(a.priority) < priorityOrder(b.priority)
            }
    }

    var body: some View {
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
/// edge accent; info entries are plain `bgCard`.
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

                Text(announcement.body)
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
}

#Preview {
    AnnouncementsCard()
        .padding()
        .background(XomperColors.bgDark)
        .preferredColorScheme(.dark)
}
