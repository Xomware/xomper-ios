import SwiftUI

struct MatchupsView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var router: AppRouter

    @State private var selectedSeason: String = ""
    @State private var expandedWeek: Int?
    @State private var selectedMatchup: MatchupHistoryRecord?
    @State private var hasLoaded = false

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
                seasonPicker
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
    }

    // MARK: - Season Picker

    @ViewBuilder
    private var seasonPicker: some View {
        let seasons = historyStore.availableMatchupSeasons
        if seasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(seasons, id: \.self) { season in
                        seasonButton(season)
                    }
                }
            }
        }
    }

    private func seasonButton(_ season: String) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                selectedSeason = season
                expandedWeek = historyStore.latestScoredWeek(forSeason: season)
            }
        } label: {
            Text(season)
                .font(.subheadline)
                .fontWeight(selectedSeason == season ? .semibold : .regular)
                .foregroundStyle(selectedSeason == season ? XomperColors.deepNavy : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(selectedSeason == season ? XomperColors.championGold : XomperColors.surfaceLight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Season \(season)")
        .accessibilityAddTraits(selectedSeason == season ? .isSelected : [])
    }

    // MARK: - Weeks List

    private var weeksList: some View {
        let weeks = historyStore.weeklyMatchups(forSeason: selectedSeason)

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
                        MatchupCardView(matchup: matchup) {
                            selectedMatchup = matchup
                        }
                    }
                }
                .padding(.top, XomperTheme.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(weekData.week), \(weekData.matchups.count) matchups")
        .accessibilityHint(expandedWeek == weekData.week ? "Collapse" : "Expand to see matchups")
    }

    // MARK: - Load

    private func loadMatchups() async {
        guard let leagueId = leagueStore.currentLeague?.leagueId else { return }

        await leagueStore.loadLeagueChain(startingFrom: leagueId)
        let chain = leagueStore.leagueChain

        guard !chain.isEmpty else { return }

        await historyStore.loadMatchupHistory(chain: chain)

        // Default to most recent season
        if selectedSeason.isEmpty, let first = historyStore.availableMatchupSeasons.first {
            selectedSeason = first
            expandedWeek = historyStore.latestScoredWeek(forSeason: first)
        }
    }
}

// MARK: - Matchup Card

private struct MatchupCardView: View {
    let matchup: MatchupHistoryRecord
    let onTap: () -> Void

    @State private var isPressed = false

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
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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

#Preview {
    NavigationStack {
        MatchupsView(
            leagueStore: LeagueStore(),
            historyStore: HistoryStore(),
            playerStore: PlayerStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
