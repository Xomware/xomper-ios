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
    var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            Group {
                if newsStore.isLoading && !newsStore.hasItems {
                    LoadingView(message: "Loading league news...")
                } else if let error = newsStore.error, !newsStore.hasItems {
                    ErrorView(message: error.localizedDescription) {
                        Task { await reload(force: true) }
                    }
                } else if filteredItems.isEmpty && newsStore.hasItems {
                    EmptyStateView(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "No Matches",
                        message: "No news items match your filters."
                    )
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
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task { await reload(force: false) }
        .onChange(of: leagueStore.myLeagueRosters.count) { _, _ in
            Task { await reload(force: false) }
        }
    }

    // MARK: - Filters

    private var filteredItems: [NewsItem] {
        newsStore.filteredItems
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Type filters
                ForEach(NewsType.allCases) { type in
                    filterChip(
                        label: type.label,
                        icon: type.systemImage,
                        selected: newsStore.typeFilter == type
                    ) {
                        newsStore.typeFilter = newsStore.typeFilter == type ? nil : type
                    }
                }

                // Divider
                Rectangle()
                    .fill(XomperColors.surfaceLight)
                    .frame(width: 1, height: 20)

                // Team filter (if teams available)
                if !newsStore.teamNames.isEmpty {
                    Menu {
                        Button("All Teams") {
                            newsStore.teamFilter = nil
                        }
                        Divider()
                        ForEach(newsStore.teamNames.sorted(by: { $0.value < $1.value }), id: \.key) { rosterId, name in
                            Button(name) {
                                newsStore.teamFilter = rosterId
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 11, weight: .semibold))
                            Text(newsStore.teamFilter.flatMap { newsStore.teamNames[$0] } ?? "Team")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(newsStore.teamFilter != nil ? XomperColors.bgDark : XomperColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(newsStore.teamFilter != nil ? XomperColors.championGold : XomperColors.bgCard)
                        .clipShape(Capsule())
                    }
                }

                // Clear button if filters active
                if newsStore.activeFilterCount > 0 {
                    Button {
                        newsStore.clearFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
        }
        .padding(.vertical, 8)
        .background(XomperColors.bgDark)
    }

    private func filterChip(label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? XomperColors.bgDark : XomperColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? XomperColors.championGold : XomperColors.bgCard)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: XomperTheme.Spacing.sm) {
                ForEach(filteredItems) { item in
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
            TradeNewsCard(item: item, router: router)
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
