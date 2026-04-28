import SwiftUI

/// Signed-in root shell. Hosts a header bar + a single `NavigationStack` whose
/// root switches on `navStore.currentDestination`. The slide-out `DrawerView`
/// and its `DrawerScrim` are overlaid above the content column.
///
/// Owns:
/// - `NavigationStore` — drawer state + selected top-level destination
/// - `AppRouter`       — the inner `NavigationStack` path for downstream pushes
/// - Bootstrap `.task` modifiers that load league / NFL / players / user data
struct MainShell: View {

    // MARK: - Stores (injected from ContentView)

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

    // MARK: - Local state

    @State private var navStore = NavigationStore()
    @State private var router = AppRouter()
    @State private var seasonStore = SeasonStore()

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            XomperColors.bgDark
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderBar(
                    navStore: navStore,
                    router: router,
                    avatarID: userStore.myUser?.avatar,
                    seasonStore: seasonStore
                )

                NavigationStack(path: $router.path) {
                    destinationRoot
                        .environment(\.selectedSeason, seasonStore)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationView(for: route)
                                .environment(\.selectedSeason, seasonStore)
                        }
                }
            }

            DrawerScrim(navStore: navStore)

            DrawerView(
                navStore: navStore,
                router: router,
                avatarID: userStore.myUser?.avatar,
                displayName: resolvedDisplayName,
                email: authStore.session?.user.email
            )
        }
        .gesture(edgeDragGesture)
        .task {
            await bootstrapPhase1()
            seasonStore.bootstrap(currentSeason: nflStateStore.currentSeason)
            refreshSeasons()
        }
        .task(id: authStore.sleeperUserId) {
            await bootstrapPhase2()
            refreshSeasons()
        }
        .onChange(of: historyStore.matchupHistory.count) { _, _ in
            refreshSeasons()
        }
        .onChange(of: historyStore.draftHistory.count) { _, _ in
            refreshSeasons()
        }
        .onChange(of: leagueStore.leagueChain.count) { _, _ in
            refreshSeasons()
        }
        .onChange(of: nflStateStore.currentSeason) { _, _ in
            seasonStore.bootstrap(currentSeason: nflStateStore.currentSeason)
            refreshSeasons()
        }
    }

    // MARK: - Season Store Refresh

    private func refreshSeasons() {
        seasonStore.refreshAvailable(
            matchupSeasons: historyStore.availableMatchupSeasons,
            draftSeasons: historyStore.availableDraftSeasons,
            chainSeasons: leagueStore.leagueChain.map(\.season),
            currentSeason: nflStateStore.currentSeason
        )
    }

    // MARK: - Top-level destination root

    @ViewBuilder
    private var destinationRoot: some View {
        Group {
            switch navStore.currentDestination {
            case .standings:
                StandingsView(
                    leagueStore: leagueStore,
                    teamStore: teamStore,
                    authStore: authStore,
                    router: router
                )

            case .matchups:
                MatchupsView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore,
                    router: router
                )

            case .playoffs:
                PlayoffBracketView(leagueStore: leagueStore)

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

            case .worldCup:
                WorldCupView(
                    worldCupStore: worldCupStore,
                    historyStore: historyStore,
                    leagueStore: leagueStore
                )

            case .myTeam:
                myTeamRoot

            case .taxiSquad:
                TaxiSquadView(
                    leagueStore: leagueStore,
                    playerStore: playerStore,
                    authStore: authStore,
                    taxiSquadStore: taxiSquadStore
                )

            case .rules:
                if let league = leagueStore.currentLeague ?? leagueStore.myLeague {
                    RulesView(
                        league: league,
                        rulesStore: rulesStore,
                        authStore: authStore
                    )
                } else {
                    EmptyStateView(
                        icon: "book",
                        title: "No League Loaded",
                        message: "Rules will appear once your league is loaded."
                    )
                }

            case .profile:
                MyProfileView(
                    authStore: authStore,
                    userStore: userStore,
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    router: router,
                    navStore: navStore
                )

            case .settings:
                SettingsView(pushManager: PushNotificationManager.shared)
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle(navStore.currentDestination.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - My Team root

    /// Resolves `teamStore.myTeam` to a TeamView at the root. Falls back to
    /// an empty-state placeholder if the team / roster / league hasn't loaded.
    @ViewBuilder
    private var myTeamRoot: some View {
        if let team = teamStore.myTeam,
           let league = leagueStore.currentLeague ?? leagueStore.myLeague,
           let roster = (leagueStore.currentLeagueRosters.isEmpty
                ? leagueStore.myLeagueRosters
                : leagueStore.currentLeagueRosters
           ).first(where: { $0.rosterId == team.rosterId }) {
            TeamView(
                team: team,
                roster: roster,
                league: league,
                playerStore: playerStore
            )
        } else {
            EmptyStateView(
                icon: "person.crop.square",
                title: "Team Not Loaded",
                message: "Your team will appear once your league finishes loading."
            )
        }
    }

    // MARK: - Pushed routes

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .leagueDashboard:
            // Defensive: dashboard is dissolved post-F3. If anything still
            // pushes this route, we fall through to standings.
            StandingsView(
                leagueStore: leagueStore,
                teamStore: teamStore,
                authStore: authStore,
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
                router: router,
                navStore: navStore
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
                router: router,
                navStore: navStore
            )

        case .settings:
            SettingsView(pushManager: PushNotificationManager.shared)
        }
    }

    // MARK: - Edge swipe → drawer

    /// Edge swipe: a horizontal drag started near the leading edge that pulls
    /// the drawer open, mirroring the system-wide left-edge gesture you'd
    /// expect on iOS.
    ///
    /// We require:
    /// - the gesture *starts* in the leftmost ~30pt (so it doesn't fight
    ///   horizontal scrolls inside content)
    /// - drawer is currently closed
    /// - we're at the root of the navigation stack (so swipe-to-pop wins
    ///   inside pushed views)
    private var edgeDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onEnded { value in
                let startedAtEdge = value.startLocation.x < 30
                let pulledRight = value.translation.width > 60
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                guard !navStore.isDrawerOpen,
                      startedAtEdge,
                      pulledRight,
                      mostlyHorizontal,
                      router.path.count == 0 else { return }
                navStore.openDrawer()
            }
    }

    // MARK: - Profile card name resolution

    private var resolvedDisplayName: String? {
        authStore.sleeperUsername
            ?? userStore.myUser?.username
            ?? authStore.userDisplayName
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

    /// Phase 2: Once sleeperUserId resolves, load user info, team, and all leagues.
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

        // Load all user's leagues for the home screen
        let season = nflStateStore.nflState?.season ?? leagueStore.myLeague?.season ?? "2024"
        await leagueStore.loadUserLeagues(userId: sleeperUserId, season: season)
    }
}
