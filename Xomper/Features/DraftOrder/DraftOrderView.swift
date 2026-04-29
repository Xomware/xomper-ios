import SwiftUI

/// Projected draft order for next year's rookie draft, using the
/// reverse-HPP rule: non-playoff teams pick in ascending order of
/// season Highest Possible Points. Playoff teams pick at the back
/// of round 1, ordered by (eventual) playoff finish.
///
/// Rationale (per league rule discussion in #57):
/// - Punishes managers who tank by setting bad lineups (high HPP +
///   low actual = first pick under old rules → top pick of next
///   year's class).
/// - Rewards managers who maximized their starts but ran into
///   bad luck (low HPP, low actual = they tried; they get the
///   higher pick).
struct DraftOrderView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var playerPointsStore: PlayerPointsStore

    var body: some View {
        Group {
            if leagueStore.myLeagueRosters.isEmpty {
                LoadingView(message: "Loading league…")
            } else if !playerPointsStore.hasData {
                if playerPointsStore.isLoading {
                    LoadingView(message: "Computing perfect-lineup totals…")
                } else {
                    EmptyStateView(
                        icon: "list.number",
                        title: "Draft Order Pending",
                        message: "Per-week data not yet aggregated. Pull to refresh."
                    )
                }
            } else {
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: leagueStore.myLeague?.leagueId) {
            await ensureLoaded()
        }
        .refreshable {
            await ensureLoaded()
        }
    }

    // MARK: - Content

    private var content: some View {
        let projection = compute()

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                explainerCard

                if !projection.nonPlayoffOrder.isEmpty {
                    sectionHeader("Reverse-HPP order (picks 1–\(projection.nonPlayoffOrder.count))")
                    ForEach(Array(projection.nonPlayoffOrder.enumerated()), id: \.offset) { idx, entry in
                        row(rank: idx + 1, entry: entry, isPlayoff: false)
                    }
                }

                if !projection.playoffOrder.isEmpty {
                    sectionHeader(
                        "Playoff teams (picks "
                        + "\(projection.nonPlayoffOrder.count + 1)–"
                        + "\(projection.nonPlayoffOrder.count + projection.playoffOrder.count))"
                    )
                    ForEach(Array(projection.playoffOrder.enumerated()), id: \.offset) { idx, entry in
                        row(
                            rank: projection.nonPlayoffOrder.count + idx + 1,
                            entry: entry,
                            isPlayoff: true
                        )
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Explainer

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Reverse-HPP draft order")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)

            Text("Non-playoff teams pick in ascending order of season Highest Possible Points (perfect-lineup score). Playoff teams pick at the back, ordered by playoff finish.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)

            Text("HPP credits a team for the points they could have scored if they'd started their best lineup each week. Set bad lineups → high HPP / low wins → late pick. Maximized starts but unlucky → low HPP → early pick.")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(XomperColors.textMuted)
            .padding(.top, XomperTheme.Spacing.sm)
    }

    // MARK: - Row

    private func row(rank: Int, entry: DraftOrderProjection.Entry, isPlayoff: Bool) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text("\(rank)")
                .font(.title3.weight(.bold))
                .foregroundStyle(rank == 1 ? XomperColors.championGold : XomperColors.textSecondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: XomperTheme.Spacing.sm) {
                    Text(entry.recordLabel)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                    Text(entry.actualPFLabel)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                    if isPlayoff {
                        Text("PLAYOFFS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(XomperColors.bgDark)
                            .padding(.horizontal, XomperTheme.Spacing.xs)
                            .background(XomperColors.successGreen)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", entry.seasonHPP))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
                Text("season HPP")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    // MARK: - Compute

    private func compute() -> DraftOrderProjection {
        DraftOrderProjection.compute(
            leagueStore: leagueStore,
            playerStore: playerStore,
            playerPointsStore: playerPointsStore,
            regularSeasonLastWeek: regularSeasonLastWeek
        )
    }

    // MARK: - Data loading

    private func ensureLoaded() async {
        if !playerPointsStore.hasData,
           let leagueId = leagueStore.myLeague?.leagueId {
            await playerPointsStore.loadRegularSeason(
                leagueId: leagueId,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
        }
    }

    private var regularSeasonLastWeek: Int {
        guard let value = leagueStore.myLeague?.settings?.additionalSettings?["playoff_week_start"] else {
            return 14
        }
        if let i = value.intValue { return max(i - 1, 1) }
        if let d = value.doubleValue { return max(Int(d) - 1, 1) }
        return 14
    }
}

// MARK: - Projection

struct DraftOrderProjection: Sendable {
    let nonPlayoffOrder: [Entry]
    let playoffOrder: [Entry]

    static let empty = DraftOrderProjection(nonPlayoffOrder: [], playoffOrder: [])

    struct Entry: Sendable, Hashable {
        let rosterId: Int
        let teamName: String
        let recordLabel: String
        let actualPFLabel: String
        let actualPF: Double
        let seasonHPP: Double
        let leagueRank: Int
    }

    @MainActor
    static func compute(
        leagueStore: LeagueStore,
        playerStore: PlayerStore,
        playerPointsStore: PlayerPointsStore,
        regularSeasonLastWeek: Int
    ) -> DraftOrderProjection {
        guard let league = leagueStore.myLeague else { return .empty }
        let standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )

        let rosterPositions = league.rosterPositions ?? []
        let playoffTeams = league.settings?.playoffTeams ?? 6

        let entries: [Entry] = standings.map { team in
            let hpp = HighestPossibleCalculator.seasonHPP(
                rosterId: team.rosterId,
                rosterPositions: rosterPositions,
                playerPointsStore: playerPointsStore,
                playerStore: playerStore,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
            return Entry(
                rosterId: team.rosterId,
                teamName: team.teamName,
                recordLabel: "\(team.wins)-\(team.losses)\(team.ties > 0 ? "-\(team.ties)" : "")",
                actualPFLabel: String(format: "%.1f PF", team.fpts),
                actualPF: team.fpts,
                seasonHPP: hpp,
                leagueRank: team.leagueRank
            )
        }

        // Standings is already sorted by wins-DESC then PF-DESC. Top
        // playoff_teams qualify; rest go to non-playoff.
        let playoffEntries = Array(entries.prefix(playoffTeams))
        let nonPlayoff = Array(entries.dropFirst(playoffTeams))
            .sorted(by: { $0.seasonHPP < $1.seasonHPP })  // ascending HPP

        return DraftOrderProjection(
            nonPlayoffOrder: nonPlayoff,
            playoffOrder: playoffEntries
        )
    }
}
