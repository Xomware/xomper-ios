import SwiftUI

struct LeagueDashboardView: View {
    var leagueStore: LeagueStore
    var userStore: UserStore
    var teamStore: TeamStore
    var authStore: AuthStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var worldCupStore: WorldCupStore
    var rulesStore: RulesStore
    var router: AppRouter

    @State private var activeTab: LeagueTab = .standings

    var body: some View {
        VStack(spacing: 0) {
            if leagueStore.isLoading {
                LoadingView(message: "Loading league...")
            } else if let error = leagueStore.error {
                ErrorView(message: error.localizedDescription) {
                    Task { await leagueStore.loadMyLeague() }
                }
            } else if let league = leagueStore.currentLeague {
                leagueContent(league)
            } else {
                EmptyStateView(
                    icon: "trophy",
                    title: "No League Selected",
                    message: "Head to Home to load your league."
                )
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle(leagueStore.currentLeague?.displayName ?? "League")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - League Content

    private func leagueContent(_ league: League) -> some View {
        VStack(spacing: 0) {
            tabPicker
            tabContentView(league)
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                ForEach(LeagueTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgCard)
    }

    private func tabButton(_ tab: LeagueTab) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                activeTab = tab
            }
        } label: {
            Text(tab.title)
                .font(.subheadline)
                .fontWeight(activeTab == tab ? .semibold : .regular)
                .foregroundStyle(activeTab == tab ? XomperColors.deepNavy : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(activeTab == tab ? XomperColors.championGold : XomperColors.surfaceLight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContentView(_ league: League) -> some View {
        switch activeTab {
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
        case .worldCup:
            WorldCupView(
                worldCupStore: worldCupStore,
                historyStore: historyStore,
                leagueStore: leagueStore
            )
        case .rules:
            RulesView(
                league: league,
                rulesStore: rulesStore,
                authStore: authStore
            )
        }
    }
}

// MARK: - League Tab Enum

private enum LeagueTab: String, CaseIterable, Identifiable {
    case standings
    case matchups
    case playoffs
    case worldCup
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standings: "Standings"
        case .matchups: "Matchups"
        case .playoffs: "Playoffs"
        case .worldCup: "World Cup"
        case .rules: "Rules"
        }
    }
}

#Preview {
    NavigationStack {
        LeagueDashboardView(
            leagueStore: LeagueStore(),
            userStore: UserStore(),
            teamStore: TeamStore(),
            authStore: AuthStore(),
            historyStore: HistoryStore(),
            playerStore: PlayerStore(),
            worldCupStore: WorldCupStore(),
            rulesStore: RulesStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
