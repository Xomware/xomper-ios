import SwiftUI

/// Inline render of the most recent `postDraft` AI report for a given
/// year. Lives as the third sub-tab on the Draft surface (current
/// season) and the second sub-tab on past seasons. No navigation
/// push — markdown body renders directly, matching the body card on
/// `AIReviewDetailView`.
///
/// Data flow:
/// 1. On appear / year change, lazy-load the dedicated postDraft
///    archive (`loadPostDraftArchive`) if it hasn't been pulled yet.
///    The dedicated fetch (`type=postDraft`) guarantees past-year
///    recaps are reachable even when the global archive's first 20
///    rows wouldn't include them.
/// 2. Filter `aiReviewStore.postDraftArchive` for
///    `reportType == .postDraft` AND `period.contains(year)`. The
///    archive is newest-first so `first(where:)` returns the most
///    recent match.
/// 3. Render header (period + createdAt) and body
///    (`AttributedString(markdown:)`).
///
/// Pull-to-refresh forces a postDraft archive reload via
/// `force: true`.
struct DraftRecapView: View {
    var aiReviewStore: AIReviewStore
    let year: String

    var body: some View {
        Group {
            if let report = matchingReport {
                reportContent(report)
            } else if aiReviewStore.isLoadingPostDraftArchive {
                LoadingView(message: "Loading \(year) draft recap…")
            } else {
                EmptyStateView(
                    icon: "sparkles",
                    title: "No Recap Yet",
                    message: "We haven't generated a post-draft report for \(year). Check back after the report runs."
                )
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: year) {
            await ensureArchiveLoaded()
        }
        .refreshable {
            await aiReviewStore.loadPostDraftArchive(force: true)
        }
    }

    // MARK: - Resolved report

    /// Resolves the matching report from the store's postDraft
    /// archive. Static peer (`Self.matchingReport`) holds the actual
    /// logic so tests can drive it directly.
    private var matchingReport: AIReport? {
        Self.matchingReport(in: aiReviewStore.postDraftArchive, year: year)
    }

    /// Pure filter: take the first `postDraft` report whose `period`
    /// string contains `year`. Period strings carry the year per the
    /// F0 wire format (`"2026"`, `"2026-POSTDRAFT"`, etc.) — combined
    /// with the type filter, the substring match is safe.
    ///
    /// Archive is newest-first sorted upstream, so `first` returns
    /// the most recent matching report.
    static func matchingReport(in archive: [AIReport], year: String) -> AIReport? {
        guard !year.isEmpty else { return nil }
        return archive.first { report in
            report.reportType == .postDraft && report.period.contains(year)
        }
    }

    // MARK: - Loading

    private func ensureArchiveLoaded() async {
        // Lazy-load the dedicated postDraft archive. The 12-hour
        // freshness guard inside `loadPostDraftArchive` short-circuits
        // any subsequent calls, so we don't need to gate on
        // `postDraftArchiveLoadedAt` here.
        await aiReviewStore.loadPostDraftArchive()
    }

    // MARK: - Report content

    private func reportContent(_ report: AIReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                headerCard(report)
                bodyCard(report)
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    private func headerCard(_ report: AIReport) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text("RECAP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                Text(report.period)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Spacer()
                Text(formattedDate(report.createdAt))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }
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

    private func bodyCard(_ report: AIReport) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            renderedMarkdown(report)
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

    /// iOS 17 `AttributedString(markdown:)` with full interpreted
    /// syntax (headings, lists, bold). Falls back to plain text if
    /// the markdown is malformed.
    @ViewBuilder
    private func renderedMarkdown(_ report: AIReport) -> some View {
        let reflowed = MarkdownReflow.paragraphs(report.bodyMarkdown)
        if let attributed = try? AttributedString(
            markdown: reflowed,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
        ) {
            Text(attributed)
                .lineSpacing(4)
        } else {
            Text(reflowed)
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
