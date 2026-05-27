import SwiftUI

struct MatchupsView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var aiReviewStore: AIReviewStore
    var router: AppRouter

    @Environment(\.selectedSeason) private var seasonStore: SeasonStore?

    @State private var expandedWeek: Int?
    @State private var selectedMatchup: MatchupHistoryRecord?
    @State private var hasLoaded = false

    private var currentSeason: String {
        seasonStore?.selectedSeason ?? ""
    }

    var body: some View {
        Group {
            if historyStore.isLoadingMatchups {
                LoadingView(message: "Loading matchups...")
            } else if let error = historyStore.matchupError {
                ErrorView(message: error.localizedDescription) {
                    Task { await loadMatchups() }
                }
            } else if historyStore.hasMatchups {
                matchupsContent
            } else {
                EmptyStateView(
                    icon: "sportscourt",
                    title: "No Matchups Found",
                    message: "Results will appear here as weeks complete."
                )
            }
        }
        .task {
            guard !hasLoaded else { return }
            await loadMatchups()
            hasLoaded = true
        }
        .sheet(item: $selectedMatchup) { record in
            NavigationStack {
                MatchupDetailView(
                    record: record,
                    historyStore: historyStore,
                    playerStore: playerStore
                )
            }
        }
    }

    // MARK: - Content

    private var matchupsContent: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                weeksList
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
        .refreshable {
            historyStore.reset()
            hasLoaded = false
            await loadMatchups()
            hasLoaded = true
        }
        .onChange(of: seasonStore?.selectedSeason) { _, newSeason in
            withAnimation(XomperTheme.defaultAnimation) {
                expandedWeek = historyStore.latestScoredWeek(forSeason: newSeason ?? "")
            }
        }
    }

    // MARK: - Weeks List

    private var weeksList: some View {
        let weeks = historyStore.weeklyMatchups(forSeason: currentSeason)

        return LazyVStack(spacing: XomperTheme.Spacing.md) {
            if weeks.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "No Matchups",
                    message: "No matchup data for this season."
                )
            } else {
                ForEach(weeks) { weekData in
                    weekSection(weekData)
                }
            }
        }
    }

    // MARK: - Week Section

    private func weekSection(_ weekData: WeekMatchups) -> some View {
        VStack(spacing: 0) {
            weekHeader(weekData)

            if expandedWeek == weekData.week {
                VStack(spacing: XomperTheme.Spacing.md) {
                    ForEach(weekData.matchups) { matchup in
                        VStack(spacing: XomperTheme.Spacing.xs) {
                            MatchupCardView(matchup: matchup) {
                                selectedMatchup = matchup
                            }

                            // Inline AI-generated blurb under the matchup
                            // card. Renders only when the weekly recap
                            // is present + has a matching `matchup_id`.
                            // Current weeks and weeks pre-AI-review
                            // (none of 2024/2025 today, all backfilled)
                            // produce no blurb — view is silently absent.
                            if let blurb = blurb(for: matchup, weekData: weekData) {
                                MatchupBlurbCardView(blurb: blurb)
                            }
                        }
                    }
                }
                .padding(.top, XomperTheme.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .task(id: weekRecapTaskId(weekData)) {
                    // Only fetch the recap once a week is expanded AND
                    // it has scores — otherwise we'd fan out a request
                    // for every week and waste cycles on the
                    // unscored current week.
                    guard weekData.hasScores else { return }
                    let period = AIReviewStore.weeklyPeriod(
                        season: currentSeason,
                        week: weekData.week
                    )
                    await aiReviewStore.loadWeeklyReport(period: period)
                }
            }
        }
    }

    /// Stable identifier used by the `.task(id:)` modifier so the
    /// weekly-recap fetch fires once per (season, week) expansion and
    /// doesn't repeat on every render. Embedding `currentSeason`
    /// avoids stale fetches when the season chip flips.
    private func weekRecapTaskId(_ weekData: WeekMatchups) -> String {
        "\(currentSeason)-\(weekData.week)"
    }

    /// Resolves the per-matchup blurb for a rendered matchup. Looks
    /// up the weekly recap by `(season, week)` period, then keys into
    /// its `metadata.matchups[]` array by `matchup_id`. Falls back to
    /// a team-name match if Sleeper rotated the matchup ids after a
    /// re-roster cycle (rare, but defensive).
    private func blurb(
        for matchup: MatchupHistoryRecord,
        weekData: WeekMatchups
    ) -> WeeklyMatchupBlurb? {
        let period = AIReviewStore.weeklyPeriod(
            season: currentSeason,
            week: weekData.week
        )
        guard !period.isEmpty,
              let report = aiReviewStore.weeklyReportsByPeriod[period],
              let recap = report.decodeMetadata(WeeklyRecapMetadata.self) else {
            return nil
        }

        if let hit = recap.matchups.first(where: { $0.matchupId == matchup.matchupId }) {
            return hit
        }
        // Fallback: same teams, regardless of `matchup_id`. Order
        // doesn't matter because both pairings (A→B, B→A) are valid.
        let aName = matchup.teamATeamName.isEmpty ? matchup.teamAUsername : matchup.teamATeamName
        let bName = matchup.teamBTeamName.isEmpty ? matchup.teamBUsername : matchup.teamBTeamName
        return recap.matchups.first { blurb in
            (blurb.teamA == aName && blurb.teamB == bName) ||
            (blurb.teamA == bName && blurb.teamB == aName)
        }
    }

    private func weekHeader(_ weekData: WeekMatchups) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                expandedWeek = expandedWeek == weekData.week ? nil : weekData.week
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(weekData.week > 14 ? "Playoff Week \(weekData.week)" : "Week \(weekData.week)")
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)

                    Text("\(weekData.matchups.count) matchups")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                }

                Spacer()

                if !weekData.hasScores {
                    Text("No scores")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .rotationEffect(.degrees(expandedWeek == weekData.week ? 180 : 0))
                    .animation(XomperTheme.defaultAnimation, value: expandedWeek)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Week \(weekData.week), \(weekData.matchups.count) matchups")
        .accessibilityHint(expandedWeek == weekData.week ? "Collapse" : "Expand to see matchups")
    }

    // MARK: - Load

    private func loadMatchups() async {
        guard let leagueId = leagueStore.myLeague?.leagueId else { return }

        await leagueStore.loadLeagueChain(startingFrom: leagueId)
        let chain = leagueStore.leagueChain

        guard !chain.isEmpty else { return }

        await historyStore.loadMatchupHistory(chain: chain)

        // Seed expandedWeek from whatever season the shared store currently
        // has selected. `MainShell` already refreshes `availableSeasons`
        // reactively when matchup history changes, so we don't manage that
        // here.
        if expandedWeek == nil {
            expandedWeek = historyStore.latestScoredWeek(forSeason: currentSeason)
        }
    }
}

// MARK: - Matchup Card

private struct MatchupCardView: View {
    let matchup: MatchupHistoryRecord
    let onTap: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onTap()
        } label: {
            VStack(spacing: 0) {
                teamRow(
                    name: matchup.teamATeamName.isEmpty ? matchup.teamAUsername : matchup.teamATeamName,
                    username: matchup.teamATeamName.isEmpty ? nil : matchup.teamAUsername,
                    points: matchup.teamAPoints,
                    result: matchupResult(for: matchup.teamARosterId)
                )

                vsDivider

                teamRow(
                    name: matchup.teamBTeamName.isEmpty ? matchup.teamBUsername : matchup.teamBTeamName,
                    username: matchup.teamBTeamName.isEmpty ? nil : matchup.teamBUsername,
                    points: matchup.teamBPoints,
                    result: matchupResult(for: matchup.teamBRosterId)
                )
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .stroke(XomperColors.surfaceLight, lineWidth: 0.5)
            )
            .xomperShadow(.sm)
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view matchup details")
    }

    private func teamRow(name: String, username: String?, points: Double, result: MatchupResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(result == .win ? XomperColors.textPrimary : XomperColors.textSecondary)
                    .lineLimit(1)

                if let username {
                    Text(username)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: XomperTheme.Spacing.sm) {
                Text(String(format: "%.2f", points))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(result == .win ? XomperColors.championGold : XomperColors.textSecondary)
                    .monospacedDigit()

                resultIndicator(result)
            }
        }
        .padding(.vertical, XomperTheme.Spacing.sm)
    }

    private var vsDivider: some View {
        HStack {
            Rectangle()
                .fill(XomperColors.surfaceLight)
                .frame(height: 0.5)

            VStack(spacing: XomperTheme.Spacing.xs) {
                Text("VS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(XomperColors.textMuted)

                Text("\(pointsDiff) pts")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .padding(.horizontal, XomperTheme.Spacing.sm)

            Rectangle()
                .fill(XomperColors.surfaceLight)
                .frame(height: 0.5)
        }
    }

    private func resultIndicator(_ result: MatchupResult) -> some View {
        Text(result.label)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(result.color)
            .frame(width: 20)
    }

    private func matchupResult(for rosterId: Int) -> MatchupResult {
        if matchup.winnerRosterId == rosterId { return .win }
        if matchup.winnerRosterId == nil { return .tie }
        return .loss
    }

    private var pointsDiff: String {
        let diff = abs(matchup.teamAPoints - matchup.teamBPoints)
        return String(format: "%.2f", diff)
    }

    private var accessibilityDescription: String {
        let teamA = matchup.teamATeamName.isEmpty ? matchup.teamAUsername : matchup.teamATeamName
        let teamB = matchup.teamBTeamName.isEmpty ? matchup.teamBUsername : matchup.teamBTeamName
        return "\(teamA) \(String(format: "%.2f", matchup.teamAPoints)) versus \(teamB) \(String(format: "%.2f", matchup.teamBPoints))"
    }
}

// MARK: - Matchup Result

private enum MatchupResult {
    case win, loss, tie

    var label: String {
        switch self {
        case .win: "W"
        case .loss: "L"
        case .tie: "T"
        }
    }

    var color: Color {
        switch self {
        case .win: XomperColors.championGold
        case .loss: XomperColors.accentRed
        case .tie: XomperColors.textMuted
        }
    }
}

// MARK: - Matchup Blurb Card

/// Small markdown-rendered card that sits under a `MatchupCardView`
/// when the week's AI recap has a per-matchup blurb. The blurb
/// markdown leans on `**bold**` for team names + margins so
/// `AttributedString(markdown:)` is sufficient — no need for the
/// heavier interpreted-syntax setup.
private struct MatchupBlurbCardView: View {
    let blurb: WeeklyMatchupBlurb

    var body: some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.championGold)
                .padding(.top, 2)

            renderedBlurb
                .font(.caption)
                .foregroundStyle(XomperColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(XomperColors.championGold.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recap: \(blurb.blurb)")
    }

    @ViewBuilder
    private var renderedBlurb: some View {
        if let attributed = try? AttributedString(
            markdown: blurb.blurb,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
        } else {
            Text(blurb.blurb)
        }
    }
}

#Preview {
    NavigationStack {
        MatchupsView(
            leagueStore: LeagueStore(),
            historyStore: HistoryStore(),
            playerStore: PlayerStore(),
            aiReviewStore: AIReviewStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
