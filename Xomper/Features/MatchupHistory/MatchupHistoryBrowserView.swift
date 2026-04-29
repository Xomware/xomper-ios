import SwiftUI

/// Season-grouped browser of every matchup across the league chain.
/// Mirrors xomper-front-end's `matchup-history` page: pick a season,
/// see weeks descending; expand a week to see all that week's
/// matchups with scores + W/L; tap a matchup row for the detail view.
///
/// Replaces the previous H2H-only `MatchupHistoryView` at the
/// `.matchupHistory` tray destination. The H2H concept survives as
/// `HeadToHeadView` for ad-hoc deep-links from profile / search.
struct MatchupHistoryBrowserView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore

    @Environment(\.selectedSeason) private var seasonStore: SeasonStore?

    @State private var expandedWeeks: Set<Int> = []
    @State private var selectedRecord: MatchupHistoryRecord?

    var body: some View {
        Group {
            if historyStore.isLoadingMatchups && historyStore.matchupHistory.isEmpty {
                LoadingView(message: "Loading matchup history...")
            } else if let error = historyStore.matchupError, historyStore.matchupHistory.isEmpty {
                ErrorView(message: error.localizedDescription) {
                    Task { await reload() }
                }
            } else if historyStore.matchupHistory.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No Matchup History",
                    message: "Past weeks' matchups will appear here once games are played."
                )
            } else {
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: leagueStore.myLeague?.leagueId) {
            await ensureLoaded()
        }
        .refreshable {
            await reload()
        }
        .sheet(item: $selectedRecord) { record in
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

    private var content: some View {
        let weeks = weeksForActiveSeason

        return ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                if weeks.isEmpty {
                    Text("No matchups for this season yet.")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textMuted)
                        .padding(.top, XomperTheme.Spacing.lg)
                } else {
                    ForEach(weeks) { weekBundle in
                        weekSection(weekBundle)
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Week section

    @ViewBuilder
    private func weekSection(_ bundle: WeekBundle) -> some View {
        let isExpanded = expandedWeeks.contains(bundle.week)
        VStack(spacing: XomperTheme.Spacing.xs) {
            Button {
                withAnimation(XomperTheme.defaultAnimation) {
                    if isExpanded { expandedWeeks.remove(bundle.week) }
                    else { expandedWeeks.insert(bundle.week) }
                }
            } label: {
                HStack {
                    Text("Week \(bundle.week)")
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                    Spacer()
                    Text("\(bundle.matchups.count) matchups")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .xomperCard()
            }
            .buttonStyle(.pressableCard)

            if isExpanded {
                ForEach(bundle.matchups, id: \.id) { record in
                    matchupRow(record)
                }
            }
        }
    }

    // MARK: - Matchup row

    private func matchupRow(_ record: MatchupHistoryRecord) -> some View {
        let aWin = record.winnerRosterId == record.teamARosterId
        let bWin = record.winnerRosterId == record.teamBRosterId
        let bothScoreless = record.teamAPoints == 0 && record.teamBPoints == 0

        return Button {
            selectedRecord = record
        } label: {
            VStack(spacing: 0) {
                if let placement = placementLabel(for: record) {
                    Text(placement)
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(XomperColors.championGold)
                        .padding(.bottom, 2)
                }
                HStack(spacing: XomperTheme.Spacing.md) {
                    teamColumn(
                        name: record.teamATeamName.isEmpty ? record.teamAUsername : record.teamATeamName,
                        points: record.teamAPoints,
                        isWinner: aWin,
                        showOutcome: !bothScoreless
                    )

                    Text("vs")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)

                    teamColumn(
                        name: record.teamBTeamName.isEmpty ? record.teamBUsername : record.teamBTeamName,
                        points: record.teamBPoints,
                        isWinner: bWin,
                        showOutcome: !bothScoreless
                    )

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .background(XomperColors.bgCard.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.pressableCard)
    }

    /// Surface a placement tag ("CHAMPIONSHIP" / "3RD PLACE" / etc.)
    /// on matchup rows. Reads the placement stamped onto each record
    /// at ingest by HistoryStore (which loads each league's bracket
    /// per-season — so labels work for past seasons too, not just the
    /// currently-anchored league). Other playoff games show
    /// "PLAYOFFS · WEEK N".
    private func placementLabel(for record: MatchupHistoryRecord) -> String? {
        if let placement = record.playoffPlacement {
            return placementCopy(for: placement)
        }
        if record.isPlayoff {
            return "PLAYOFFS · WEEK \(record.week)"
        }
        return nil
    }

    private func placementCopy(for placement: Int) -> String {
        switch placement {
        case 1: return "CHAMPIONSHIP"
        case 2: return "RUNNER-UP"
        case 3: return "3RD PLACE"
        case 5: return "5TH PLACE"
        case 7: return "7TH PLACE"
        case 9: return "9TH PLACE"
        case 11: return "11TH PLACE"
        default: return "\(placement) PLACE"
        }
    }

    private func teamColumn(name: String, points: Double, isWinner: Bool, showOutcome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline)
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(isWinner ? XomperColors.successGreen : XomperColors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(String(format: "%.1f", points))
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
                    .monospacedDigit()
                if showOutcome {
                    Text(isWinner ? "W" : "L")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isWinner ? XomperColors.successGreen : XomperColors.accentRed.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Data

    private func ensureLoaded() async {
        guard !historyStore.isLoadingMatchups else { return }

        if leagueStore.leagueChain.isEmpty,
           let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }
        let chain = leagueStore.leagueChain
        guard !chain.isEmpty else { return }

        if historyStore.matchupHistory.isEmpty {
            await historyStore.loadMatchupHistory(chain: chain)
        }

        if expandedWeeks.isEmpty {
            // Auto-expand the most recent week with non-zero scores so the
            // user lands on real data instead of a wall of collapsed weeks.
            if let firstScored = weeksForActiveSeason.first(where: { bundle in
                bundle.matchups.contains { $0.teamAPoints > 0 || $0.teamBPoints > 0 }
            }) {
                expandedWeeks = [firstScored.week]
            }
        }
    }

    private func reload() async {
        historyStore.reset()
        if let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
            await historyStore.loadMatchupHistory(chain: leagueStore.leagueChain)
        }
    }

    // MARK: - Grouping

    /// Active season — env-driven via F5 SeasonStore. Falls back to the
    /// newest season we have data for.
    private var activeSeason: String {
        let env = seasonStore?.selectedSeason ?? ""
        if !env.isEmpty { return env }
        return historyStore.availableMatchupSeasons.first ?? ""
    }

    private var weeksForActiveSeason: [WeekBundle] {
        let season = activeSeason
        guard !season.isEmpty else { return [] }
        let filtered = historyStore.matchupHistory.filter { $0.season == season }

        var byWeek: [Int: [MatchupHistoryRecord]] = [:]
        for record in filtered {
            byWeek[record.week, default: []].append(record)
        }

        return byWeek
            .map { week, records in
                WeekBundle(
                    week: week,
                    matchups: records.sorted { $0.matchupId < $1.matchupId }
                )
            }
            .sorted { $0.week > $1.week }
    }
}

// MARK: - Supporting types

private struct WeekBundle: Identifiable {
    let week: Int
    let matchups: [MatchupHistoryRecord]
    var id: Int { week }
}

