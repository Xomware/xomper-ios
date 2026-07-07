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
    var historyStore: HistoryStore

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
        // Filter bar lives in a fixed strip above the ScrollView (not a
        // pinned section header) so it stays put with no gap between it
        // and the content as the feed scrolls underneath.
        VStack(spacing: 0) {
            NewsFilterBar(store: newsStore)
                .background(XomperColors.bgDark)

            ScrollView {
                LazyVStack(spacing: XomperTheme.Spacing.sm) {
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
                }
                .padding(.top, XomperTheme.Spacing.sm)
                .padding(.bottom, XomperTheme.Spacing.md)
            }
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

        // Ensure draft history is loaded so we can resolve traded picks
        // to the players they became and value them correctly.
        await ensureDraftHistoryLoaded()

        await valuesStore.loadValues()
        await newsStore.load(
            leagueId: leagueStore.resolvedHomeLeagueId,
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore,
            draftHistory: historyStore.draftHistory,
            forceRefresh: force
        )
    }

    /// Ensures draft history is loaded for pick resolution. Skips if already
    /// loaded or loading.
    private func ensureDraftHistoryLoaded() async {
        guard historyStore.draftHistory.isEmpty,
              !historyStore.isLoadingDrafts else { return }

        // Build the league chain if not already available.
        if leagueStore.leagueChain.isEmpty,
           let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }

        guard !leagueStore.leagueChain.isEmpty else { return }
        await historyStore.loadDraftHistory(chain: leagueStore.leagueChain)
    }
}
