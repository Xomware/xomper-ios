import SwiftUI

/// Top-level News feed — league trades + roster moves, graded and
/// written up locally (no LLM), with a pinned filter bar.
///
/// Reads rosters/users from `LeagueStore`, dynasty values from the
/// shared `PlayerValuesStore`, and player names from `PlayerStore`.
struct NewsView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var valuesStore: PlayerValuesStore
    var newsStore: NewsStore

    var body: some View {
        Group {
            if newsStore.isLoading && !newsStore.hasItems {
                LoadingView(message: "Loading league news...")
            } else if let error = newsStore.error, !newsStore.hasItems {
                ErrorView(message: error.localizedDescription) {
                    Task { await reload(force: true) }
                }
            } else if !newsStore.hasItems {
                EmptyStateView(
                    icon: "newspaper",
                    title: "No News Yet",
                    message: "Trades and roster moves across the league will show up here."
                )
            } else {
                feed
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task { await reload(force: false) }
        .refreshable { await reload(force: true) }
        .onChange(of: leagueStore.myLeagueRosters.count) { _, _ in
            Task { await reload(force: false) }
        }
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: XomperTheme.Spacing.sm, pinnedViews: [.sectionHeaders]) {
                Section {
                    let items = newsStore.filteredItems
                    if items.isEmpty {
                        EmptyStateView(
                            icon: "line.3.horizontal.decrease.circle",
                            title: "No Matches",
                            message: "No news matches your current filters."
                        )
                        .padding(.top, XomperTheme.Spacing.xl)
                    } else {
                        ForEach(items) { item in
                            card(for: item)
                                .padding(.horizontal, XomperTheme.Spacing.md)
                        }
                    }
                } header: {
                    NewsFilterBar(store: newsStore)
                        .background(XomperColors.bgDark)
                }
            }
            .padding(.bottom, XomperTheme.Spacing.md)
        }
    }

    @ViewBuilder
    private func card(for item: NewsItem) -> some View {
        switch item.type {
        case .trade:
            TradeNewsCard(item: item)
        case .waiver, .freeAgent:
            MoveNewsCard(item: item)
        }
    }

    // MARK: - Load

    private func reload(force: Bool) async {
        // Team-name resolution needs rosters + users; wait for them so
        // the feed doesn't cache placeholder "Team N" labels.
        guard !leagueStore.myLeagueRosters.isEmpty else { return }
        await valuesStore.loadValues()
        await newsStore.load(
            leagueId: leagueStore.resolvedHomeLeagueId,
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore,
            forceRefresh: force
        )
    }
}
