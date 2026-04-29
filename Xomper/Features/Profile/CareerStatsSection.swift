import SwiftUI

/// Career-stats grid for the Profile page. Renders six tiles derived
/// from `HistoryStore.careerStats(forUserId:)`. Pure presentation — the
/// section's parent (`MyProfileView`) owns the history-bootstrap.
struct CareerStatsSection: View {
    var historyStore: HistoryStore
    var userId: String

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Career Stats")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.leading, XomperTheme.Spacing.xs)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let stats = historyStore.careerStats(forUserId: userId)

        if !stats.hasGames {
            emptyCard
        } else {
            statsGrid(stats)
        }
    }

    // MARK: - Stats Grid

    private func statsGrid(_ stats: CareerStats) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: XomperTheme.Spacing.sm),
            GridItem(.flexible(), spacing: XomperTheme.Spacing.sm),
        ]

        return LazyVGrid(columns: columns, spacing: XomperTheme.Spacing.sm) {
            statTile(
                label: "Record",
                value: recordString(stats),
                accent: stats.winRate >= 0.5 ? XomperColors.successGreen : XomperColors.textPrimary
            )
            statTile(
                label: "Win %",
                value: percentString(stats.winRate),
                accent: stats.winRate >= 0.5 ? XomperColors.successGreen : XomperColors.textPrimary
            )
            statTile(
                label: "PF · Total",
                value: pointsString(stats.pointsFor),
                subtitle: "Avg \(pointsString(stats.averagePointsFor))",
                accent: XomperColors.championGold
            )
            statTile(
                label: "Highest Week",
                value: pointsString(stats.highestScore),
                subtitle: weekRefSubtitle(stats.highestScoreWeek),
                accent: XomperColors.successGreen
            )
            statTile(
                label: "Lowest Week",
                value: pointsString(stats.lowestScore),
                subtitle: weekRefSubtitle(stats.lowestScoreWeek),
                accent: XomperColors.accentRed.opacity(0.85)
            )
            statTile(
                label: "Seasons",
                value: "\(stats.seasonsPlayed)",
                subtitle: "\(stats.playoffAppearances) playoffs",
                accent: XomperColors.textPrimary
            )
        }
    }

    // MARK: - Stat Tile

    private func statTile(
        label: String,
        value: String,
        subtitle: String? = nil,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xomperCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(subtitle.map { ". \($0)" } ?? "")")
    }

    // MARK: - Empty

    private var emptyCard: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            Text("Stats appear once your matchup history loads.")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .xomperCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Formatters

    private func recordString(_ stats: CareerStats) -> String {
        if stats.ties > 0 {
            return "\(stats.wins)-\(stats.losses)-\(stats.ties)"
        }
        return "\(stats.wins)-\(stats.losses)"
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func pointsString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func weekRefSubtitle(_ ref: CareerStats.WeekRef?) -> String? {
        guard let ref else { return nil }
        return "\(ref.season) W\(ref.week)"
    }
}
