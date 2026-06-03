import SwiftUI

/// Prominent header card that renders the full weekly recap markdown
/// (`AIReport.bodyMarkdown`) at the top of an expanded past-and-scored
/// week on `MatchupsView`. Acts as the primary surface for the
/// AI-generated weekly content — the per-matchup blurbs that sit under
/// each matchup card stay in place as a secondary detail surface.
///
/// Collapsible via `DisclosureGroup` (default collapsed) so the
/// expanded-week view doesn't drop a wall of recap markdown above
/// the actual matchup cards — the cards are what most users came
/// for. Tap to reveal the full recap.
///
/// Visual treatment mirrors `DraftRecapView.headerCard` +
/// `bodyCard` rolled into a single card: gold "WEEKLY RECAP" pill +
/// period label up top, then `AttributedString(markdown:)`-rendered
/// body. Defensive: if markdown parsing fails (malformed recap), falls
/// back to the raw string so the user still sees the content.
struct WeeklyRecapHeaderCard: View {
    let report: AIReport

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                    renderedMarkdown
                        .font(.body)
                        .foregroundStyle(XomperColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, XomperTheme.Spacing.sm)
            } label: {
                header
            }
            .tint(XomperColors.championGold)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .xomperShadow(.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weekly recap for \(report.period)")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("WEEKLY RECAP")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.bgDark)
                .padding(.horizontal, XomperTheme.Spacing.xs)
                .padding(.vertical, 2)
                .background(XomperColors.championGold)
                .clipShape(Capsule())

            Text(AIReportType.formattedPeriod(report.period))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .monospacedDigit()

            Spacer(minLength: XomperTheme.Spacing.xs)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Markdown

    private var renderedMarkdown: some View {
        StyledMarkdownView(markdown: report.bodyMarkdown)
    }
}

#Preview {
    WeeklyRecapHeaderCard(
        report: AIReport(
            id: "L1|REPORT#weekly#2025W09",
            leagueId: "L1",
            reportType: .weekly,
            period: "2025W09",
            bodyMarkdown: """
            ## Week 9 Recap

            **Tony Tigers** rolled to a **148.2 - 102.1** win over **Mighty Ducks**.

            - Top scorer: McCaffrey, 38.4
            - Bust of the week: Lamar, 6.2
            """,
            metadata: [:],
            createdAt: Date(),
            model: "claude-haiku-4-5",
            promptVersion: "f0-2025-10-15"
        )
    )
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
