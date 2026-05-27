import SwiftUI

/// Top-level Standings destination. Thin wrapper around `StandingsListView`
/// that:
///
/// - builds the live `[StandingsTeam]` from `LeagueStore`
/// - gates on `NflStateStore.isRegularSeason` and renders
///   `StandingsOffseasonCard` whenever the league isn't actively playing
///
/// All actual row + division rendering lives in `StandingsListView` so the
/// same layout can be reused by the Archive's `HistoricalStandingsView`.
struct StandingsView: View {
    var leagueStore: LeagueStore
    var teamStore: TeamStore
    var authStore: AuthStore
    var nflStateStore: NflStateStore
    var router: AppRouter

    @State private var standings: [StandingsTeam] = []
    @State private var divisionStandings: [String: [StandingsTeam]] = [:]
    @State private var hasDivisions = false

    var body: some View {
        Group {
            if nflStateStore.hasLiveStandings {
                liveStandings
            } else {
                offseason
            }
        }
        .background(XomperColors.bgDark)
        .refreshable {
            await refreshStandings()
        }
        // Rebuild whenever the home league or its rosters/users land —
        // covers the bootstrap-vs-mount race where StandingsView is the
        // landing destination and Phase 2 hasn't resolved yet.
        .task(id: leagueStore.myLeague?.leagueId) {
            buildStandings()
        }
        .onChange(of: leagueStore.myLeagueRosters.count) { _, _ in
            buildStandings()
        }
        .onChange(of: leagueStore.myLeagueUsers.count) { _, _ in
            buildStandings()
        }
    }

    // MARK: - Live standings (regular season)

    @ViewBuilder
    private var liveStandings: some View {
        if standings.isEmpty && (leagueStore.isLoading || leagueStore.myLeagueRosters.isEmpty) {
            LoadingView(message: "Loading standings...")
        } else if standings.isEmpty {
            EmptyStateView(
                icon: "list.number",
                title: "Standings Not Loaded",
                message: "Pull to refresh to load the latest standings."
            )
        } else {
            StandingsListView(
                standings: standings,
                hasDivisions: hasDivisions,
                divisionStandings: divisionStandings,
                playoffCutoff: leagueStore.myLeague?.settings?.playoffTeams,
                myUserId: authStore.sleeperUserId,
                onTeamTap: selectTeam,
                onProfileTap: navigateToProfile
            )
        }
    }

    // MARK: - Offseason empty state

    private var offseason: some View {
        ScrollView {
            StandingsOffseasonCard()
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Actions

    private func navigateToProfile(_ team: StandingsTeam) {
        router.navigate(to: .userProfile(userId: team.userId))
    }

    private func selectTeam(_ team: StandingsTeam) {
        let user = leagueStore.myLeagueUsers.first { $0.userId == team.userId }
        teamStore.setCurrentTeam(team, user: user)
        router.navigate(to: .teamDetail(rosterId: team.rosterId))
    }

    private func buildStandings() {
        guard let league = leagueStore.myLeague else { return }

        standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )

        divisionStandings = StandingsBuilder.buildDivisionStandings(from: standings)
        hasDivisions = standings.contains { $0.hasDivision }
    }

    private func refreshStandings() async {
        await leagueStore.loadMyLeague()
        buildStandings()

        if let league = leagueStore.myLeague {
            let freshStandings = StandingsBuilder.buildStandings(
                rosters: leagueStore.myLeagueRosters,
                users: leagueStore.myLeagueUsers,
                league: league
            )
            teamStore.loadMyTeam(from: freshStandings, userId: authStore.sleeperUserId)
        }
    }
}

#Preview {
    NavigationStack {
        StandingsView(
            leagueStore: LeagueStore(),
            teamStore: TeamStore(),
            authStore: AuthStore(),
            nflStateStore: NflStateStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
