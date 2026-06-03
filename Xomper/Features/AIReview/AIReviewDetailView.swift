import SwiftUI

/// Full read of a single AI-generated league report. Renders the
/// markdown body natively via `AttributedString(markdown:)` (iOS 17
/// API — no extra SPM dep). Limited to inline styling (headings,
/// bold, lists); no tables. Per the F0 plan this is acceptable —
/// reports lean on those styles.
struct AIReviewDetailView: View {
    let report: AIReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.lg) {
                headerCard
                bodyCard
                footerMeta
            }
            .padding(XomperTheme.Spacing.md)
            .padding(.bottom, XomperTheme.Spacing.xxl)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle(report.reportType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                typeChip
                Spacer()
                Text(formattedDate(report.createdAt))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }

            Text(AIReportType.formattedPeriod(report.period))
                .font(.title2.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(report.reportType.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var typeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: report.reportType.systemImage)
                .font(.caption2.weight(.bold))
            Text(report.reportType.displayName.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .foregroundStyle(XomperColors.bgDark)
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(report.reportType.accentColor)
        .clipShape(Capsule())
    }

    // MARK: - Body

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            renderedMarkdown
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

    /// Hand-styled markdown renderer (blocks-based, mirrors email
    /// styling). See `StyledMarkdownView`.
    private var renderedMarkdown: some View {
        StyledMarkdownView(markdown: report.bodyMarkdown)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerMeta: some View {
        if report.model != nil || report.promptVersion != nil {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                if let model = report.model, !model.isEmpty {
                    metaRow(label: "Model", value: model)
                }
                if let version = report.promptVersion, !version.isEmpty {
                    metaRow(label: "Prompt", value: version)
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.sm)
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
                .tracking(0.5)
                .textCase(.uppercase)
            Text(value)
                .font(.caption2)
                .foregroundStyle(XomperColors.textSecondary)
                .monospaced()
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
