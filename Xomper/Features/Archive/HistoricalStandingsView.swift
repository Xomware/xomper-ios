import SwiftUI

/// Renders one prior season's standings by reconstructing it from cached
/// `MatchupHistoryRecord`s via `StandingsBuilder.buildStandingsFromHistory`.
/// Same renderer (`StandingsListView`) as the live league view, so the row
/// layout / sort / accessibility all match.
///
/// v1 limits, all called out in the F4 plan:
/// - **No division view**: past-year league metadata isn't cached alongside
///   matchups, so divisions are suppressed (`hasDivisions = false`).
/// - **No tappable rows**: historical roster ids don't resolve to the live
///   `TeamStore`. Both row-tap and profile-context-menu closures are no-ops.
/// - **No playoff cutoff line**: same metadata gap.
struct HistoricalStandingsView: View {
    let year: String
    let historyStore: HistoryStore
    let leagueStore: LeagueStore
    let authStore: AuthStore
    let teamStore: TeamStore
    let router: AppRouter

    @State private var standings: [StandingsTeam] = []

    var body: some View {
        Group {
            if standings.isEmpty {
                EmptyStateView(
                    icon: "list.number",
                    title: "No data for \(year)",
                    message: "Pull to refresh from Matchup History to load this season."
                )
            } else {
                StandingsListView(
                    standings: standings,
                    hasDivisions: false,
                    divisionStandings: [:],
                    playoffCutoff: nil,
                    myUserId: authStore.sleeperUserId,
                    onTeamTap: { _ in },
                    onProfileTap: { _ in }
                )
            }
        }
        .background(XomperColors.bgDark)
        .navigationTitle("\(year) Standings")
        .navigationBarTitleDisplayMode(.large)
        .task(id: year) {
            rebuild()
        }
    }

    // MARK: - Build

    private func rebuild() {
        let records = historyStore.matchups(forSeason: year)
        standings = StandingsBuilder.buildStandingsFromHistory(records: records)
    }
}

#Preview {
    NavigationStack {
        HistoricalStandingsView(
            year: "2024",
            historyStore: HistoryStore(),
            leagueStore: LeagueStore(),
            authStore: AuthStore(),
            teamStore: TeamStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
