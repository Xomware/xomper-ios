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
        .onChange(of: leagueStore.myLeagueRosters.count) { _, _ in
            Task { await reload(force: false) }
        }
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: XomperTheme.Spacing.sm) {
                ForEach(newsStore.items) { item in
                    card(for: item)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                }
            }
            .padding(.top, XomperTheme.Spacing.xs)
            .padding(.bottom, XomperTheme.Spacing.md)
        }
        .refreshable { await reload(force: true) }
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

        // Ensure league chain and draft history are loaded first.
        await ensureChainAndHistoryLoaded()

        await valuesStore.loadValues()

        // Use chain-based loading to get transactions from ALL seasons,
        // not just the current one. This fixes historical trades not showing.
        if !leagueStore.leagueChain.isEmpty {
            await newsStore.loadFromChain(
                chain: leagueStore.leagueChain,
                playerStore: playerStore,
                valuesStore: valuesStore,
                draftHistory: historyStore.draftHistory,
                forceRefresh: force
            )
        } else {
            // Fallback to single-league load if chain isn't available
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
    }

    /// Ensures league chain and draft history are loaded for proper
    /// historical data display and pick resolution.
    private func ensureChainAndHistoryLoaded() async {
        // Build the league chain if not already available.
        if leagueStore.leagueChain.isEmpty,
           let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }

        // Load draft history for pick resolution.
        if historyStore.draftHistory.isEmpty,
           !historyStore.isLoadingDrafts,
           !leagueStore.leagueChain.isEmpty {
            await historyStore.loadDraftHistory(chain: leagueStore.leagueChain)
        }
    }
}
