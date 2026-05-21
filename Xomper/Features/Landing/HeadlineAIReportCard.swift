import SwiftUI

/// Hero variant of the AI Review card — the freshest report across all
/// types in a championGold-bordered card at the top of the Landing
/// page. Tapping switches the tray destination to `.aiReview` and
/// pushes the detail view in the same animation envelope.
///
/// When the store has no latest report (cold-start or pre-draft),
/// renders a dedicated placeholder card so the Landing hero slot is
/// never empty — empty space here would make the page feel broken.
struct HeadlineAIReportCard: View {
    let store: AIReviewStore
    let navStore: NavigationStore
    let router: AppRouter

    var body: some View {
        if let report = store.mostRecentLatest {
            reportCard(report: report)
        } else {
            placeholderCard
        }
    }

    // MARK: - Populated hero card

    private func reportCard(report: AIReport) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Switch tray to AI Review, then push detail. The two
            // happen inside the same navStore animation envelope.
            navStore.select(.aiReview, router: router)
            router.navigate(to: .aiReportDetail(reportId: report.id))
        } label: {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                headerRow(report: report)

                Text(report.displayTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !report.previewSnippet.isEmpty {
                    Text(report.previewSnippet)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                readMoreRow
            }
            .padding(XomperTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(XomperColors.championGold.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest AI report: \(report.displayTitle)")
        .accessibilityHint("Double tap to read")
    }

    private func headerRow(report: AIReport) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            typeChip(for: report)
            Text(report.period)
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
        }
    }

    private func typeChip(for report: AIReport) -> some View {
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
        .background(XomperColors.championGold)
        .clipShape(Capsule())
    }

    private var readMoreRow: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("Read report")
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.championGold)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
            Spacer()
        }
    }

    // MARK: - Cold-start placeholder

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(XomperColors.championGold.opacity(0.5))
                Text("AI REVIEWS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(XomperColors.textMuted)
                Spacer()
            }

            Text("First report drops after draft day")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)
                .multilineTextAlignment(.leading)

            Text("AI reviews land here once the season kicks off — check back after July 6.")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI reviews placeholder. First report drops after draft day.")
    }
}

#Preview("Populated") {
    HeadlineAIReportCard(
        store: AIReviewStore(),
        navStore: NavigationStore(),
        router: AppRouter()
    )
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    HeadlineAIReportCard(
        store: AIReviewStore(),
        navStore: NavigationStore(),
        router: AppRouter()
    )
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
