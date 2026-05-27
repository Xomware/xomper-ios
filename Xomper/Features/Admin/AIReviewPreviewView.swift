import SwiftUI

/// F2 — pre-broadcast email preview list. Pushed from
/// `AIReviewSubScreen` after a successful dry-run trigger via
/// `router.navigate(to: .adminAIReviewPreview(reportType:))`.
///
/// Behavior:
/// - Header: report type + the number of rendered previews.
/// - "Broadcast to all" gold capsule at top. Tapping shows an
///   `.alert(...)` confirm dialog (destructive role) so single-tap
///   misfires can't happen.
/// - Scrolling list of `EmailPreviewRow`s; tapping a row presents an
///   `AIReviewPreviewDetailView` sheet with the full subject + body.
/// - Server pre-sorts by `display_name`; iOS does **not** re-sort.
///
/// Previews live in `AdminStore.lastPreviewsByType[reportType]`, which
/// is populated on each successful dry-run. The store is hoisted to
/// `MainShell` so this view reads the same instance as the trigger
/// card it was pushed from (F2 plan B5).
struct AIReviewPreviewView: View {
    let reportType: AIReportType
    var adminStore: AdminStore
    var router: AppRouter

    @State private var selectedPreview: EmailPreview?
    @State private var showBroadcastConfirm = false
    @State private var broadcastError: String?

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("\(reportType.displayName) Previews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedPreview) { preview in
                AIReviewPreviewDetailView(preview: preview)
            }
            .alert(
                "Broadcast \(reportType.displayName) to all \(previews.count)?",
                isPresented: $showBroadcastConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Broadcast", role: .destructive) {
                    Task { await broadcast() }
                }
            } message: {
                Text("This cannot be undone. Every preview you see will be sent for real.")
            }
    }

    // MARK: - Derived state

    private var previews: [EmailPreview] {
        adminStore.lastPreviewsByType[reportType] ?? []
    }

    private var isTriggerInFlight: Bool {
        switch reportType {
        case .postDraft: return adminStore.isTriggeringPostDraft
        case .preseason: return adminStore.isTriggeringPreseason
        case .weekly:    return adminStore.isTriggeringWeekly
        case .mock:      return false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if previews.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: "No previews yet",
                message: "Fire a dry-run from the AI Review screen first."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                    headerCard

                    broadcastButton

                    if let broadcastError {
                        Text("✗ \(broadcastError)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(XomperColors.errorRed)
                            .padding(.horizontal, XomperTheme.Spacing.md)
                    }

                    listHeader

                    LazyVStack(spacing: XomperTheme.Spacing.sm) {
                        ForEach(previews) { preview in
                            EmailPreviewRow(preview: preview) {
                                selectedPreview = preview
                            }
                        }
                    }
                    .padding(.horizontal, XomperTheme.Spacing.md)
                }
                .padding(.vertical, XomperTheme.Spacing.sm)
                .padding(.bottom, XomperTheme.Spacing.xl)
            }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: reportType.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(reportType.accentColor)
                Text(reportType.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }
            Text("\(previews.count) rendered \(previews.count == 1 ? "preview" : "previews"). Tap a row to read it in full.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(reportType.accentColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Broadcast button

    private var broadcastButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showBroadcastConfirm = true
        } label: {
            HStack(spacing: XomperTheme.Spacing.xs) {
                if isTriggerInFlight {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(XomperColors.bgDark)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2)
                }
                Text(isTriggerInFlight ? "Broadcasting…" : "Broadcast to all \(previews.count)")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(XomperColors.bgDark)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: XomperTheme.minTouchTarget)
            .background(isTriggerInFlight ? XomperColors.championGold.opacity(0.5) : XomperColors.championGold)
            .clipShape(Capsule())
        }
        .buttonStyle(.pressableCard)
        .disabled(isTriggerInFlight)
        .padding(.horizontal, XomperTheme.Spacing.md)
        .accessibilityLabel("Broadcast \(reportType.displayName) recap to all \(previews.count) recipients")
        .accessibilityHint("Opens a confirmation dialog before sending.")
    }

    // MARK: - List header

    private var listHeader: some View {
        Text("Recipients")
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.top, XomperTheme.Spacing.sm)
    }

    // MARK: - Broadcast

    /// Fires the same trigger endpoint with `dryRun=false, force=true`.
    /// Clears local previews + pops back on success. On failure we leave
    /// the previews intact and surface the error inline so the admin
    /// can retry.
    private func broadcast() async {
        broadcastError = nil
        do {
            switch reportType {
            case .postDraft:
                _ = try await adminStore.triggerPostDraft(dryRun: false, force: true)
            case .preseason:
                _ = try await adminStore.triggerPreseason(dryRun: false, force: true)
            case .weekly:
                _ = try await adminStore.triggerWeekly(
                    week: adminStore.weeklyWeekOverride,
                    dryRun: false,
                    force: true
                )
            case .mock:
                broadcastError = "Mock drafts can't be broadcast from this screen."
                return
            }
            adminStore.clearPreviews(for: reportType)
            router.path.removeLast()
        } catch {
            broadcastError = error.localizedDescription
        }
    }
}

// MARK: - Row

/// Single preview row. Surfaces display name + email + subject + a
/// 3-line excerpt of the text body so the admin can scan without
/// opening the sheet. Whole row is tappable.
struct EmailPreviewRow: View {
    let preview: EmailPreview
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Text(preview.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(XomperColors.championGold)
                            .lineLimit(1)
                        Text(preview.recipientEmail)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                            .lineLimit(1)
                    }
                    Text(preview.subject)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(snippet)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
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
                    .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview for \(preview.displayName), subject \(preview.subject)")
        .accessibilityHint("Double tap to read the full body.")
    }

    /// First non-blank line(s) of the text body, condensed for the row
    /// excerpt. Falls back to the raw start of `textBody` when there
    /// are no non-blank lines (defensive — shouldn't happen).
    private var snippet: String {
        let trimmed = preview.textBody
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(3)
            .joined(separator: " ")
        return trimmed.isEmpty
            ? String(preview.textBody.prefix(120))
            : trimmed
    }
}

// MARK: - Detail sheet

/// Detail sheet pushed via `.sheet(item:)` from the preview list.
/// Renders the full subject + plain-text body. Body is interpreted
/// as markdown via `AttributedString(markdown:)` (consistent with
/// `AIReviewDetailView` + `DraftRecapView`) so headings and bold
/// from the template render naturally.
struct AIReviewPreviewDetailView: View {
    let preview: EmailPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                    headerCard
                    bodyCard
                }
                .padding(XomperTheme.Spacing.md)
                .padding(.bottom, XomperTheme.Spacing.xxl)
            }
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(XomperColors.championGold)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(preview.displayName)
                .font(.title3.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
            Text(preview.recipientEmail)
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
                .textSelection(.enabled)
            Text(preview.subject)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .padding(.top, XomperTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            renderedBody
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    /// Best-effort markdown rendering. Falls back to the raw plain
    /// text when the markdown parser rejects the input — the wire
    /// `text_body` field is already plain text but happens to look
    /// like markdown for templates that include headings and lists.
    private var renderedBody: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: preview.textBody,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full
                )
            ) {
                Text(attributed)
            } else {
                Text(preview.textBody)
            }
        }
    }
}
