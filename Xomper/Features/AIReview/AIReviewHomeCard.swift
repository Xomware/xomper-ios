import SwiftUI

/// Discoverable banner card for the most recent AI report. Lives at
/// the topmost position of the Home / Search surface. Tapping
/// switches the tray destination to `.aiReview` and pushes the
/// detail view in one motion.
///
/// Renders **nothing** (zero height) when the store has no latest
/// report — so empty-state Home is unchanged until the first report
/// lands.
struct AIReviewHomeCard: View {
    let store: AIReviewStore
    let navStore: NavigationStore
    let router: AppRouter

    var body: some View {
        if let report = store.mostRecentLatest {
            cardContent(report: report)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.top, XomperTheme.Spacing.md)
        } else {
            // Zero-height when no report exists yet. Empty-state Home
            // sees no change.
            EmptyView()
        }
    }

    private func cardContent(report: AIReport) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Switch tray to AI Review, then push detail. The two
            // happen inside the same navStore animation envelope.
            navStore.select(.aiReview, router: router)
            router.navigate(to: .aiReportDetail(reportId: report.id))
        } label: {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    typeChip(for: report)
                    Text(report.period)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }

                Text(report.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .lineLimit(1)

                if !report.previewSnippet.isEmpty {
                    Text(report.previewSnippet)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
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
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest AI report: \(report.displayTitle)")
        .accessibilityHint("Double tap to read")
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
}
