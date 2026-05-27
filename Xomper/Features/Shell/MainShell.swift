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
    @State private var valuesStore = PlayerValuesStore()
    @State private var playerPointsStore = PlayerPointsStore()
    @State private var aiReviewStore = AIReviewStore()
    /// F2 hoist: previously owned by `AIReviewSubScreen` as `@State`.
    /// Lifted up so the new `AIReviewPreviewView` route can read the
    /// same instance — without the hoist a fresh `AdminStore` would
    /// spin up per push and `lastPreviewsByType` would be empty.
    /// See `docs/features/admin-portal/f2-preview/PLAN.md` B5.
    @State private var adminStore = AdminStore()
    /// F4: drives the Tables (users + leagues) + Audit feed
    /// sub-screens. Shared across `TablesSubScreenView`,
    /// `UsersListView`, `UserEditView`, `LeaguesListView`,
    /// `LeagueEditView`, `AuditFeedView`, and `AuditDetailView`
    /// so the lists + edit forms + detail view read from the
    /// same in-memory rows.
    @State private var adminTablesStore = AdminTablesStore()

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
                    seasonStore: seasonStore,
                    leagueName: leagueStore.myLeague?.name
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
                email: authStore.session?.user.email,
                isAdmin: authStore.whitelistedUser?.isAdmin == true
            )

            // Edge-swipe-to-open hit area. Confined to a 20pt strip on
            // the leading edge so the drag gesture doesn't race with
            // scroll/tap gestures across the whole content area. Only
            // active when the drawer is closed and the user is at the
            // root of the nav stack — otherwise the system swipe-to-pop
            // and inner scrolls take precedence.
            if !navStore.isDrawerOpen && router.path.count == 0 {
                Color.clear
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeDragGesture)
                    .accessibilityHidden(true)
            }
        }
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
            case .landing:
                LandingView(
                    leagueStore: leagueStore,
                    authStore: authStore,
                    nflStateStore: nflStateStore,
                    aiReviewStore: aiReviewStore,
                    navStore: navStore,
                    router: router
                )

            case .standings:
                StandingsView(
                    leagueStore: leagueStore,
                    teamStore: teamStore,
                    authStore: authStore,
                    nflStateStore: nflStateStore,
                    router: router
                )

            case .matchups:
                MatchupsView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore,
                    aiReviewStore: aiReviewStore,
                    router: router
                )

            case .playoffs:
                PlayoffBracketView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore
                )

            case .draftHistory:
                DraftHistoryView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore,
                    playerPointsStore: playerPointsStore,
                    userStore: userStore,
                    nflStateStore: nflStateStore,
                    aiReviewStore: aiReviewStore
                )

            case .matchupHistory:
                MatchupHistoryBrowserView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore
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

            case .teamAnalyzer:
                TeamAnalyzerView(
                    leagueStore: leagueStore,
                    playerStore: playerStore,
                    authStore: authStore,
                    valuesStore: valuesStore
                )

            case .payouts:
                PayoutsView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore,
                    playerPointsStore: playerPointsStore,
                    authStore: authStore,
                    nflStateStore: nflStateStore
                )

            case .draftOrder:
                DraftOrderView(
                    leagueStore: leagueStore,
                    historyStore: historyStore,
                    playerStore: playerStore,
                    playerPointsStore: playerPointsStore,
                    userStore: userStore
                )

            case .aiReview:
                AIReviewView(
                    store: aiReviewStore,
                    authStore: authStore,
                    router: router
                )

            case .archive:
                ArchiveView(
                    navStore: navStore,
                    router: router,
                    historyStore: historyStore,
                    leagueStore: leagueStore,
                    authStore: authStore,
                    teamStore: teamStore,
                    seasonStore: seasonStore
                )

            case .admin:
                AdminView(
                    authStore: authStore,
                    leagueStore: leagueStore,
                    router: router
                )

            case .rulebook:
                rulesPage(.rulebook)

            case .scoring:
                rulesPage(.scoring)

            case .leagueSettings:
                rulesPage(.leagueSettings)

            case .ruleProposals:
                rulesPage(.ruleProposals)

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

    /// Resolves a `RulesView` filtered to a single page (Scoring / League
    /// Settings / Rule Proposals / Rulebook). Falls back to an empty state
    /// when the league isn't loaded yet.
    @ViewBuilder
    private func rulesPage(_ page: RulesPage) -> some View {
        if let league = leagueStore.myLeague {
            RulesView(
                league: league,
                rulesStore: rulesStore,
                authStore: authStore,
                page: page
            )
        } else {
            EmptyStateView(
                icon: "book",
                title: "No League Loaded",
                message: "Rules will appear once your league is loaded."
            )
        }
    }

    /// Resolves `teamStore.myTeam` to a TeamView at the root. Falls back to
    /// an empty-state placeholder if the team / roster / league hasn't loaded.
    /// Triggers a `loadMyTeam` build if the league is loaded but the team
    /// hasn't been resolved yet (bootstrap-vs-view-mount race).
    @ViewBuilder
    private var myTeamRoot: some View {
        if let team = teamStore.myTeam,
           let league = leagueStore.myLeague,
           let roster = (leagueStore.myLeagueRosters
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
            .task {
                await ensureMyTeamLoaded()
            }
        }
    }

    /// Builds my-team from already-loaded league + rosters when bootstrap
    /// raced ahead of the team-store population. Bails silently if data
    /// isn't ready — the next view appearance retries.
    private func ensureMyTeamLoaded() async {
        guard teamStore.myTeam == nil,
              let league = leagueStore.myLeague,
              let userId = authStore.sleeperUserId,
              !leagueStore.myLeagueRosters.isEmpty,
              !leagueStore.myLeagueUsers.isEmpty else { return }

        let standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )
        teamStore.loadMyTeam(from: standings, userId: userId)
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
                nflStateStore: nflStateStore,
                router: router
            )

        case .teamDetail(let rosterId):
            if let league = leagueStore.myLeague {
                let standings = StandingsBuilder.buildStandings(
                    rosters: leagueStore.myLeagueRosters,
                    users: leagueStore.myLeagueUsers,
                    league: league
                )
                let rosters = leagueStore.myLeagueRosters
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
                playerPointsStore: playerPointsStore,
                userStore: userStore,
                nflStateStore: nflStateStore,
                aiReviewStore: aiReviewStore
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
                playerStore: playerStore,
                authStore: authStore,
                router: router,
                navStore: navStore,
                aiReviewStore: aiReviewStore
            )

        case .settings:
            SettingsView(pushManager: PushNotificationManager.shared)

        case .playerDetail(let playerId):
            if let player = playerStore.player(for: playerId) {
                PlayerDetailView(
                    player: player,
                    playerStore: playerStore,
                    currentSeason: nflStateStore.nflState?.season
                )
            } else {
                EmptyStateView(
                    icon: "person.fill",
                    title: "Player Not Found",
                    message: "We couldn't load this player's details."
                )
            }

        case .leagueOverview(let leagueId):
            LeagueOverviewView(leagueId: leagueId, router: router)

        case .aiReportDetail(let reportId):
            if let report = resolveAIReport(id: reportId) {
                AIReviewDetailView(report: report)
            } else {
                EmptyStateView(
                    icon: "sparkles",
                    title: "Report Not Found",
                    message: "We couldn't load this report — pull to refresh the archive."
                )
            }

        case .archivePastStandings:
            PastStandingsListView(
                historyStore: historyStore,
                leagueStore: leagueStore,
                authStore: authStore,
                teamStore: teamStore,
                router: router
            )

        case .archiveHistoricalStandings(let year):
            HistoricalStandingsView(
                year: year,
                historyStore: historyStore,
                leagueStore: leagueStore,
                authStore: authStore,
                teamStore: teamStore,
                router: router
            )

        case .archivePastDraftPicker:
            PastDraftPickerView(
                historyStore: historyStore,
                seasonStore: seasonStore,
                navStore: navStore,
                router: router,
                currentSeason: nflStateStore.currentSeason
            )

        case .adminAIReview:
            AIReviewSubScreen(
                authStore: authStore,
                leagueStore: leagueStore,
                store: adminStore,
                router: router
            )

        case .adminTestEmail:
            TestEmailView(
                authStore: authStore,
                aiReviewStore: aiReviewStore
            )

        case .adminTables:
            TablesSubScreenView(router: router, navStore: navStore)

        case .adminLogs:
            LogsStubView()

        case .adminAudit:
            AuditFeedView(store: adminTablesStore, router: router)

        case .adminAIReviewPreview(let reportType):
            AIReviewPreviewView(
                reportType: reportType,
                adminStore: adminStore,
                router: router
            )

        case .adminTablesUsers:
            UsersListView(store: adminTablesStore, router: router)

        case .adminTablesLeagues:
            LeaguesListView(store: adminTablesStore, router: router)

        case .adminTablesUserEdit(let userId):
            UserEditView(userId: userId, store: adminTablesStore, router: router)

        case .adminTablesLeagueEdit(let leagueId):
            LeagueEditView(leagueId: leagueId, store: adminTablesStore, router: router)

        case .adminAuditDetail(let entryId):
            AuditDetailView(entryId: entryId, store: adminTablesStore)
        }
    }

    /// Look up an `AIReport` from the store by its composite id. The
    /// archive is the canonical source; if not present, fall back to
    /// the latest-by-type cache. Returns nil if neither contains a
    /// match.
    private func resolveAIReport(id: String) -> AIReport? {
        if let hit = aiReviewStore.archive.first(where: { $0.id == id }) {
            return hit
        }
        return aiReviewStore.latestByType.values.first(where: { $0.id == id })
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

    /// Phase 1: Resolve the home league from Supabase first (source of
    /// truth), then load that league's data + NFL state + all players
    /// in parallel. Resolves the long-standing problem of hardcoded
    /// league IDs drifting across dynasty rollovers — Supabase is the
    /// single source of truth.
    private func bootstrapPhase1() async {
        // Resolve home league from Supabase before fetching it from
        // Sleeper, so loadMyLeague reads the right ID. Non-fatal — falls
        // back to Config.whitelistedLeagueId on failure.
        await leagueStore.fetchActiveWhitelistedLeague()

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

        // Load user's leagues for the current season *before* resolving
        // myTeam, so the name-based home-league anchor (Phase 1 used the
        // potentially-stale hardcoded ID) can re-anchor to this season's
        // league before we build standings against it.
        let season = nflStateStore.nflState?.season ?? leagueStore.myLeague?.season ?? "2024"
        await leagueStore.loadUserLeagues(userId: sleeperUserId, season: season)

        // Re-anchor myLeague to the current-season league matching
        // Config.whitelistedLeagueName. No-op when the name isn't set or
        // no match is found — the Phase 1 ID-based load remains.
        await leagueStore.resolveAndAnchorMyLeagueByName()

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
