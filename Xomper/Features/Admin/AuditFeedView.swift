import SwiftUI

/// Admin → Audit (F4).
///
/// Replaces F1's `AuditStubView`. Lists rows from the Supabase
/// `admin_audit` table via `GET /admin/audit-list` — every mutating
/// admin action (F1 test email, F3 reports flag, F4 user/league
/// update) writes one row. Cursor-paginated; infinite-scrolls on
/// the last visible row.
///
/// When the backend signals `tableMissing: true` (Supabase migration
/// not yet applied), the view shows a dedicated explanatory empty
/// state rather than the generic "no entries" message.
struct AuditFeedView: View {
    var store: AdminTablesStore
    var router: AppRouter

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Audit")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if store.auditEntries.isEmpty && !store.auditTableMissing {
                    await store.loadAudit(reset: true)
                }
            }
            .refreshable {
                await store.loadAudit(reset: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingAudit && store.auditEntries.isEmpty && !store.auditTableMissing {
            LoadingView(message: "Loading audit…")
        } else if store.auditTableMissing {
            EmptyStateView(
                icon: "clock.badge.exclamationmark",
                title: "Audit log not yet provisioned",
                message: "Admin needs to apply the Supabase migration to enable the audit feed."
            )
        } else if let error = store.auditError, store.auditEntries.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't load audit",
                message: error
            )
        } else if store.auditEntries.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No audit entries yet",
                message: "Admin actions will appear here as they happen."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(Array(store.auditEntries.enumerated()), id: \.element.id) { index, entry in
                        AuditRow(entry: entry) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            router.navigate(to: .adminAuditDetail(entryId: entry.id))
                        }
                        .onAppear {
                            // Trigger pagination when the user reaches the
                            // last entry and there's more to load.
                            if index == store.auditEntries.count - 1 && store.hasMoreAudit {
                                Task { await store.loadMoreAudit() }
                            }
                        }
                    }

                    if store.isLoadingAudit && !store.auditEntries.isEmpty {
                        ProgressView()
                            .tint(XomperColors.championGold)
                            .padding(.vertical, XomperTheme.Spacing.md)
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        }
    }
}

// MARK: - Row

private struct AuditRow: View {
    let entry: AuditEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: XomperTheme.Spacing.md) {
                Image(systemName: entry.actionSymbol)
                    .font(.title3)
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 32, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(entry.actionDisplay)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    if let target = targetSummary {
                        Text(target)
                            .font(.caption)
                            .foregroundStyle(XomperColors.textSecondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                        Text(actorSummary)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                        Text(relativeTime)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                            .monospacedDigit()
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
        .accessibilityLabel("\(entry.actionDisplay) by \(actorSummary), \(relativeTime)")
        .accessibilityHint("Double tap to view before and after details")
    }

    private var targetSummary: String? {
        switch (entry.targetTable, entry.targetId) {
        case (let table?, let id?):
            return "\(table) · \(id)"
        case (let table?, nil):
            return table
        case (nil, let id?):
            return id
        default:
            return nil
        }
    }

    private var actorSummary: String {
        entry.actorUserId.isEmpty ? "system" : entry.actorUserId
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.createdAt, relativeTo: Date())
    }
}
