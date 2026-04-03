import SwiftUI

struct WorldCupView: View {
    var worldCupStore: WorldCupStore
    var historyStore: HistoryStore
    var leagueStore: LeagueStore

    var body: some View {
        ScrollView {
            if worldCupStore.isLoading {
                LoadingView(message: "Computing World Cup standings...")
            } else if let error = worldCupStore.error {
                ErrorView(message: error.localizedDescription) {
                    reloadStandings()
                }
            } else if worldCupStore.hasData {
                standingsContent
            } else {
                EmptyStateView(
                    icon: "globe.americas.fill",
                    title: "No World Cup Data",
                    message: "Divisional matchup data is needed to compute standings."
                )
            }
        }
        .background(XomperColors.bgDark)
        .refreshable {
            await refreshData()
        }
        .onAppear {
            loadIfNeeded()
        }
    }

    // MARK: - Standings Content

    private var standingsContent: some View {
        VStack(spacing: XomperTheme.Spacing.lg) {
            headerSection
            divisionsSection
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            Text("World Cup Qualifying")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(XomperColors.textPrimary)

            Text(seasonsSummary)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)

            Text("Top 2 in each division qualify")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(XomperColors.successGreen)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.bottom, XomperTheme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var seasonsSummary: String {
        let count = worldCupStore.seasons.count
        let seasonList = worldCupStore.seasons.joined(separator: ", ")
        let plural = count != 1 ? "s" : ""
        return "Divisional head-to-head records across \(count) season\(plural) (\(seasonList))"
    }

    // MARK: - Divisions

    private var divisionsSection: some View {
        VStack(spacing: XomperTheme.Spacing.lg) {
            ForEach(worldCupStore.divisions) { division in
                WorldCupDivisionSection(
                    division: division,
                    seasons: worldCupStore.seasons
                )
            }
        }
    }

    // MARK: - Actions

    private func loadIfNeeded() {
        guard !worldCupStore.hasData, !worldCupStore.isLoading else { return }
        reloadStandings()
    }

    private func reloadStandings() {
        let chain = leagueStore.leagueChain
        let matchups = historyStore.matchupHistory
        worldCupStore.loadStandings(chain: chain, matchups: matchups)
    }

    private func refreshData() async {
        // Re-load matchup history from chain, then recompute
        if let leagueId = leagueStore.currentLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
            await historyStore.loadMatchupHistory(chain: leagueStore.leagueChain)
        }
        reloadStandings()
    }
}

// MARK: - Division Section

private struct WorldCupDivisionSection: View {
    let division: WorldCupDivision
    let seasons: [String]

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            divisionHeader
            standingsTable
            qualifyLine
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .stroke(XomperColors.surfaceLight.opacity(0.2), lineWidth: 1)
        )
    }

    private var divisionHeader: some View {
        Text(division.divisionName)
            .font(.title3)
            .fontWeight(.bold)
            .foregroundStyle(XomperColors.championGold)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, XomperTheme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private var standingsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            ForEach(Array(division.teams.enumerated()), id: \.element.id) { index, team in
                WorldCupTeamRow(
                    team: team,
                    rank: index + 1,
                    seasons: seasons
                )
            }
        }
    }

    private var tableHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                headerCell("#", width: 32, alignment: .center)
                headerCell("Team", width: 120, alignment: .leading)
                headerCell("W", width: 36, alignment: .center)
                headerCell("L", width: 36, alignment: .center)
                headerCell("PF", width: 64, alignment: .trailing)
                headerCell("PA", width: 64, alignment: .trailing)
                ForEach(seasons, id: \.self) { season in
                    headerCell(season, width: 56, alignment: .center)
                }
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.horizontal, XomperTheme.Spacing.xs)
        }
    }

    private func headerCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(XomperColors.textMuted)
            .textCase(.uppercase)
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    private var qualifyLine: some View {
        if division.teams.count > 2 {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Text("Qualified")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(XomperColors.championGold)
                    .padding(.horizontal, XomperTheme.Spacing.sm)
                    .padding(.vertical, XomperTheme.Spacing.xxs)
                    .background(XomperColors.championGold.opacity(0.15))
                    .clipShape(Capsule())

                Rectangle()
                    .fill(XomperColors.championGold.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.top, XomperTheme.Spacing.xs)
            .accessibilityLabel("Top 2 teams above this line are qualified")
        }
    }
}

// MARK: - Team Row

private struct WorldCupTeamRow: View {
    let team: WorldCupTeamRecord
    let rank: Int
    let seasons: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                rankCell
                teamInfoCell
                statCell(String(team.wins), width: 36, isWins: true)
                statCell(String(team.losses), width: 36, isLosses: true)
                statCell(String(format: "%.1f", team.pointsFor), width: 64, alignment: .trailing)
                statCell(String(format: "%.1f", team.pointsAgainst), width: 64, alignment: .trailing)
                seasonCells
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.horizontal, XomperTheme.Spacing.xs)
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .opacity(team.qualified ? 1.0 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var rankCell: some View {
        Text("\(rank)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(rankColor)
            .frame(width: 32, alignment: .center)
    }

    private var rankColor: Color {
        switch rank {
        case 1: XomperColors.championGold
        case 2: XomperColors.textSecondary
        default: XomperColors.textMuted
        }
    }

    private var teamInfoCell: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
            Text(team.teamName.isEmpty ? team.username : team.teamName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
            Text(team.username)
                .font(.caption2)
                .foregroundStyle(XomperColors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 120, alignment: .leading)
    }

    private func statCell(
        _ text: String,
        width: CGFloat,
        isWins: Bool = false,
        isLosses: Bool = false,
        alignment: Alignment = .center
    ) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .fontDesign(.monospaced)
            .foregroundStyle(statColor(isWins: isWins, isLosses: isLosses))
            .frame(width: width, alignment: alignment)
    }

    private func statColor(isWins: Bool, isLosses: Bool) -> Color {
        if isWins { return XomperColors.successGreen }
        if isLosses { return XomperColors.accentRed }
        return XomperColors.textSecondary
    }

    private var seasonCells: some View {
        ForEach(seasons, id: \.self) { season in
            Text(seasonRecord(for: season))
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(XomperColors.textSecondary)
                .frame(width: 56, alignment: .center)
        }
    }

    private func seasonRecord(for season: String) -> String {
        guard let breakdown = team.seasonBreakdown.first(where: { $0.season == season }) else {
            return "-"
        }
        return "\(breakdown.wins)-\(breakdown.losses)"
    }

    private var rowBackground: Color {
        team.qualified
            ? XomperColors.championGold.opacity(0.05)
            : XomperColors.bgCard.opacity(0.3)
    }

    private var accessibilityDescription: String {
        var desc = "Rank \(rank), \(team.teamName.isEmpty ? team.username : team.teamName), "
        desc += "\(team.record), "
        desc += "Points for \(String(format: "%.1f", team.pointsFor)), "
        desc += "Points against \(String(format: "%.1f", team.pointsAgainst))"
        if team.qualified { desc += ", Qualified" }
        return desc
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorldCupView(
            worldCupStore: WorldCupStore(),
            historyStore: HistoryStore(),
            leagueStore: LeagueStore()
        )
    }
    .preferredColorScheme(.dark)
}
