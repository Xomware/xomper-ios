import SwiftUI

struct ContentView: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    var userStore: UserStore
    var teamStore: TeamStore
    var nflStateStore: NflStateStore
    var playerStore: PlayerStore
    var historyStore: HistoryStore
    var worldCupStore: WorldCupStore
    var taxiSquadStore: TaxiSquadStore
    var rulesStore: RulesStore
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: tab == router.selectedTab ? $router.path : .constant(NavigationPath())) {
                    tabContent(for: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationView(for: route)
                        }
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
        .tint(XomperColors.championGold)
        .task {
            await bootstrapPhase1()
        }
        .task(id: authStore.sleeperUserId) {
            await bootstrapPhase2()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                authStore: authStore,
                leagueStore: leagueStore,
                userStore: userStore,
                teamStore: teamStore,
                nflStateStore: nflStateStore,
                router: router
            )
        case .league:
            LeagueDashboardView(
                leagueStore: leagueStore,
                userStore: userStore,
                teamStore: teamStore,
                authStore: authStore,
                historyStore: historyStore,
                playerStore: playerStore,
                worldCupStore: worldCupStore,
                rulesStore: rulesStore,
                router: router
            )
        case .myTeam:
            if let team = teamStore.myTeam,
               let roster = leagueStore.myLeagueRosters.first(where: { $0.rosterId == team.rosterId }),
               let league = leagueStore.myLeague {
                TeamView(
                    team: team,
                    roster: roster,
                    league: league,
                    playerStore: playerStore
                )
                .navigationTitle("My Team")
            } else {
                EmptyStateView(
                    icon: "person.3.fill",
                    title: "No Team",
                    message: "Load your league first to see your team."
                )
            }
        case .profile:
            MyProfileView(
                authStore: authStore,
                userStore: userStore,
                leagueStore: leagueStore,
                router: router
            )
        }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .leagueDashboard:
            LeagueDashboardView(
                leagueStore: leagueStore,
                userStore: userStore,
                teamStore: teamStore,
                authStore: authStore,
                historyStore: historyStore,
                playerStore: playerStore,
                worldCupStore: worldCupStore,
                rulesStore: rulesStore,
                router: router
            )
        case .teamDetail(let rosterId):
            if let league = leagueStore.currentLeague ?? leagueStore.myLeague {
                let standings = StandingsBuilder.buildStandings(
                    rosters: leagueStore.currentLeagueRosters.isEmpty ? leagueStore.myLeagueRosters : leagueStore.currentLeagueRosters,
                    users: leagueStore.currentLeagueUsers.isEmpty ? leagueStore.myLeagueUsers : leagueStore.currentLeagueUsers,
                    league: league
                )
                let rosters = leagueStore.currentLeagueRosters.isEmpty ? leagueStore.myLeagueRosters : leagueStore.currentLeagueRosters
                if let team = standings.first(where: { $0.rosterId == rosterId }),
                   let roster = rosters.first(where: { $0.rosterId == rosterId }) {
                    TeamView(
                        team: team,
                        roster: roster,
                        league: league,
                        playerStore: playerStore
                    )
                } else {
                    EmptyStateView(icon: "person.3.fill", title: "Team Not Found", message: nil)
                }
            } else {
                EmptyStateView(icon: "person.3.fill", title: "No League Loaded", message: nil)
            }
        case .userProfile(let userId):
            ProfileView(
                userId: userId,
                leagueStore: leagueStore,
                router: router
            )
        case .draftHistory:
            DraftHistoryView(
                leagueStore: leagueStore,
                historyStore: historyStore,
                playerStore: playerStore,
                userStore: userStore
            )
        case .matchupHistory:
            MatchupHistoryView(
                user1Id: authStore.sleeperUserId ?? "",
                user2Id: "",
                user1Name: userStore.myUser?.resolvedDisplayName ?? "",
                user2Name: "",
                historyStore: historyStore
            )
        case .taxiSquad:
            TaxiSquadView(
                leagueStore: leagueStore,
                playerStore: playerStore,
                authStore: authStore,
                taxiSquadStore: taxiSquadStore
            )
        case .search:
            SearchView(
                leagueStore: leagueStore,
                router: router
            )
        }
    }

    // MARK: - Bootstrap

    /// Phase 1: Load league, NFL state, and players in parallel.
    /// These don't depend on sleeperUserId.
    private func bootstrapPhase1() async {
        async let leagueLoad: () = leagueStore.loadMyLeague()
        async let nflLoad: () = nflStateStore.fetchState()
        async let playerLoad: () = playerStore.loadPlayers()

        _ = await (leagueLoad, nflLoad, playerLoad)
    }

    /// Phase 2: Once sleeperUserId resolves, load user info and build my team.
    /// Re-triggers automatically when authStore.sleeperUserId changes.
    private func bootstrapPhase2() async {
        guard let sleeperUserId = authStore.sleeperUserId else { return }

        await userStore.loadMyUser(userId: sleeperUserId)

        if let league = leagueStore.myLeague {
            let standings = StandingsBuilder.buildStandings(
                rosters: leagueStore.myLeagueRosters,
                users: leagueStore.myLeagueUsers,
                league: league
            )
            teamStore.loadMyTeam(from: standings, userId: sleeperUserId)
        }
    }
}

#Preview {
    ContentView(
        authStore: AuthStore(),
        leagueStore: LeagueStore(),
        userStore: UserStore(),
        teamStore: TeamStore(),
        nflStateStore: NflStateStore(),
        playerStore: PlayerStore(),
        historyStore: HistoryStore(),
        worldCupStore: WorldCupStore(),
        taxiSquadStore: TaxiSquadStore(),
        rulesStore: RulesStore()
    )
    .preferredColorScheme(.dark)
}
