import SwiftUI

/// Admin → Audit → Entry detail (F4).
///
/// Shows one `admin_audit` row with collapsible Before / After /
/// Metadata sections, each rendering pretty-printed JSON in a
/// monospaced block. v1 only — a polished diff visualisation is
/// deferred per the F4 plan once we see real audit volume.
///
/// Resolves the entry from `AdminTablesStore.auditEntries` rather
/// than re-fetching, because the list endpoint already returns
/// every blob (no separate detail endpoint needed).
struct AuditDetailView: View {
    let entryId: String
    var store: AdminTablesStore

    @State private var showBefore: Bool = true
    @State private var showAfter: Bool = true
    @State private var showMetadata: Bool = false

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Audit Entry")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var resolvedEntry: AuditEntry? {
        store.auditEntries.first(where: { $0.id == entryId })
    }

    @ViewBuilder
    private var content: some View {
        if let entry = resolvedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                    headerCard(entry)

                    DisclosureGroup(isExpanded: $showBefore) {
                        jsonBlock(entry.before)
                    } label: {
                        disclosureLabel("Before")
                    }

                    DisclosureGroup(isExpanded: $showAfter) {
                        jsonBlock(entry.after)
                    } label: {
                        disclosureLabel("After")
                    }

                    DisclosureGroup(isExpanded: $showMetadata) {
                        jsonBlock(entry.metadata)
                    } label: {
                        disclosureLabel("Metadata")
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
            }
        } else {
            EmptyStateView(
                icon: "clock.badge.questionmark",
                title: "Entry not found",
                message: "We couldn't find that audit entry. Go back and refresh the feed."
            )
        }
    }

    // MARK: - Header

    private func headerCard(_ entry: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: entry.actionSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .accessibilityHidden(true)
                Text(entry.actionDisplay)
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
            }

            metaRow(label: "Actor", value: entry.actorUserId.isEmpty ? "system" : entry.actorUserId)
            metaRow(label: "When", value: formattedDate(entry.createdAt))
            if let table = entry.targetTable {
                metaRow(label: "Table", value: table)
            }
            if let id = entry.targetId {
                metaRow(label: "Target", value: id)
            }
            metaRow(label: "Action", value: entry.action)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
            Text(label)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d yyyy · h:mm:ss a"
        return formatter.string(from: date)
    }

    // MARK: - Disclosure label

    private func disclosureLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(XomperColors.textPrimary)
    }

    // MARK: - JSON block

    @ViewBuilder
    private func jsonBlock(_ value: JSONValue?) -> some View {
        if let value {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(value.prettyPrintedString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(XomperColors.textPrimary)
                    .padding(XomperTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(XomperColors.bgDark.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .strokeBorder(XomperColors.textMuted.opacity(0.3), lineWidth: 1)
            )
            .padding(.top, XomperTheme.Spacing.xs)
        } else {
            Text("(none)")
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
                .padding(.top, XomperTheme.Spacing.xs)
        }
    }
}
