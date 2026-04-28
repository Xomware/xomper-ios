import SwiftUI

struct WorldCupView: View {
    var worldCupStore: WorldCupStore
    var historyStore: HistoryStore
    var leagueStore: LeagueStore

    @Environment(\.selectedSeason) private var seasonStore: SeasonStore?

    private var activeSeason: String? {
        let season = seasonStore?.selectedSeason ?? ""
        return season.isEmpty ? nil : season
    }

    private var displayedDivisions: [WorldCupDivision] {
        worldCupStore.filteredDivisions(for: activeSeason)
    }

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
        .task {
            await loadIfNeeded()
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

            Text("Top 2 per division qualify · \(ClinchCalculator.defaultGamesRemaining) games remaining")
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
        if let season = activeSeason, worldCupStore.seasons.contains(season) {
            return "Divisional records for \(season)"
        }
        let count = worldCupStore.seasons.count
        let seasonList = worldCupStore.seasons.joined(separator: ", ")
        let plural = count != 1 ? "s" : ""
        return "Divisional head-to-head records across \(count) season\(plural) (\(seasonList))"
    }

    // MARK: - Divisions

    private var divisionsSection: some View {
        let columns = displayedColumnSeasons
        return VStack(spacing: XomperTheme.Spacing.lg) {
            ForEach(displayedDivisions) { division in
                WorldCupDivisionSection(
                    division: division,
                    seasons: columns
                )
            }
        }
    }

    /// Per-season columns to render in each division's stat table. When a
    /// single season is selected, we only show that season's column. When the
    /// selection is unset (or "All"), we keep the multi-season layout.
    private var displayedColumnSeasons: [String] {
        if let season = activeSeason, worldCupStore.seasons.contains(season) {
            return [season]
        }
        return worldCupStore.seasons
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        guard !worldCupStore.hasData, !worldCupStore.isLoading else { return }

        // Ensure chain and matchup history are loaded before computing standings
        if leagueStore.leagueChain.isEmpty, let leagueId = leagueStore.currentLeague?.leagueId ?? leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }
        if historyStore.matchupHistory.isEmpty, !leagueStore.leagueChain.isEmpty {
            await historyStore.loadMatchupHistory(chain: leagueStore.leagueChain)
        }

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
        VStack(spacing: XomperTheme.Spacing.md) {
            divisionHeader
            standingsTable
        }
        .padding(XomperTheme.Spacing.lg)
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
        VStack(spacing: XomperTheme.Spacing.xs) {
            tableHeader
            ForEach(Array(division.teams.enumerated()), id: \.element.id) { index, team in
                WorldCupTeamRow(
                    team: team,
                    rank: index + 1,
                    seasons: seasons
                )

                if index + 1 == qualificationCutoff, index + 1 < division.teams.count {
                    qualificationDivider
                }
            }
        }
    }

    private var qualificationCutoff: Int { 2 }

    private var qualificationDivider: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Rectangle()
                .fill(XomperColors.championGold.opacity(0.4))
                .frame(height: 2)

            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "line.horizontal.star.fill.line.horizontal")
                    .font(.caption2)
                Text("QUALIFICATION LINE")
                    .font(.caption2)
                    .fontWeight(.heavy)
                    .tracking(1)
            }
            .foregroundStyle(XomperColors.championGold)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(XomperColors.championGold.opacity(0.12))
            .clipShape(Capsule())

            Rectangle()
                .fill(XomperColors.championGold.opacity(0.4))
                .frame(height: 2)
        }
        .padding(.vertical, XomperTheme.Spacing.sm)
        .accessibilityLabel("Qualification line. Top \(qualificationCutoff) teams per division qualify for the bracket.")
    }

    private var tableHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.xs) {
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
            .padding(.horizontal, XomperTheme.Spacing.md)
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

}

// MARK: - Team Row

private struct WorldCupTeamRow: View {
    let team: WorldCupTeamRecord
    let rank: Int
    let seasons: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                rankCell
                teamInfoCell
                statCell(String(team.wins), width: 36, isWins: true)
                statCell(String(team.losses), width: 36, isLosses: true)
                statCell(String(format: "%.1f", team.pointsFor), width: 64, alignment: .trailing)
                statCell(String(format: "%.1f", team.pointsAgainst), width: 64, alignment: .trailing)
                seasonCells
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.horizontal, XomperTheme.Spacing.md)
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .opacity(team.clinchStatus == .eliminated ? 0.4 : 1.0)
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
        if team.clinchStatus == .eliminated { return XomperColors.textMuted }
        if team.clinchStatus == .clinched { return XomperColors.championGold }
        switch rank {
        case 1: return XomperColors.championGold
        case 2: return XomperColors.textSecondary
        default: return XomperColors.textMuted
        }
    }

    private var teamInfoCell: some View {
        let isEliminated = team.clinchStatus == .eliminated
        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text(team.teamName.isEmpty ? team.username : team.teamName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isEliminated ? XomperColors.textMuted : XomperColors.textPrimary)
                    .strikethrough(isEliminated, color: XomperColors.textMuted)
                    .lineLimit(1)

                if team.clinchStatus == .clinched {
                    clinchedBadge
                } else if team.clinchStatus == .eliminated {
                    eliminatedBadge
                }
            }
            Text(team.username)
                .font(.caption2)
                .foregroundStyle(XomperColors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 120, alignment: .leading)
    }

    private var clinchedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9))
            Text("CLINCHED")
                .font(.caption2)
                .fontWeight(.heavy)
                .tracking(0.5)
        }
        .foregroundStyle(XomperColors.championGold)
        .accessibilityLabel("Clinched")
    }

    private var eliminatedBadge: some View {
        Text("OUT")
            .font(.caption2)
            .fontWeight(.heavy)
            .tracking(0.5)
            .foregroundStyle(XomperColors.accentRed.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(XomperColors.accentRed.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel("Eliminated")
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
        switch team.clinchStatus {
        case .clinched:    XomperColors.championGold.opacity(0.14)
        case .alive:       XomperColors.bgCard.opacity(0.3)
        case .eliminated:  XomperColors.bgCard.opacity(0.15)
        }
    }

    private var accessibilityDescription: String {
        var desc = "Rank \(rank), \(team.teamName.isEmpty ? team.username : team.teamName), "
        desc += "\(team.record), "
        desc += "Points for \(String(format: "%.1f", team.pointsFor)), "
        desc += "Points against \(String(format: "%.1f", team.pointsAgainst))"
        switch team.clinchStatus {
        case .clinched:   desc += ", Clinched"
        case .eliminated: desc += ", Eliminated from contention"
        case .alive:      break
        }
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
