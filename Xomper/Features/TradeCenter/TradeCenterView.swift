import SwiftUI

/// Trade Center — the single hub that consolidates every trade surface
/// in the app behind one pill-segmented control (#151):
///
/// - **Recent**      → league-wide completed trades, graded + written up,
///                      reusing the News feed's `TradeNewsCard`.
/// - **Builder**     → the standalone any-team-vs-any-team
///                      `TradeAnalysisView`, embedded verbatim.
/// - **Suggestions** → fair-value upgrade ideas for *my* weak positions,
///                      via `RecommendedTradeBuilder`.
/// - **My Trades**   → the Recent feed filtered to deals my team was in.
///
/// Trade + roster-move data comes from the shared `NewsStore` (no LLM,
/// graded locally); dynasty values from the shared `PlayerValuesStore`.
/// My roster is resolved from `TeamStore.myTeam` — sections that need it
/// degrade to an explanatory empty state until the team loads.
struct TradeCenterView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var valuesStore: PlayerValuesStore
    var newsStore: NewsStore
    var teamStore: TeamStore
    var historyStore: HistoryStore

    @State private var selectedTab: TradeCenterTab = .recent

    private var myRosterId: Int? { teamStore.myTeam?.rosterId }

    /// Completed trades only, newest first (NewsStore already sorts).
    private var tradeItems: [NewsItem] {
        newsStore.items.filter { $0.type == .trade }
    }

    /// Trades my team was a party to.
    private var myTradeItems: [NewsItem] {
        guard let myRosterId else { return [] }
        return tradeItems.filter { $0.involves(rosterId: myRosterId) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TradeCenterTabBar(selection: $selectedTab)

            Group {
                switch selectedTab {
                case .recent:      recentTab
                case .builder:     builderTab
                case .suggestions: suggestionsTab
                case .myTrades:    myTradesTab
                }
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task { await reloadNews(force: false) }
        .onChange(of: leagueStore.myLeagueRosters.count) { _, _ in
            Task { await reloadNews(force: false) }
        }
    }

    // MARK: - Recent

    private var recentTab: some View {
        tradeFeed(
            items: tradeItems,
            emptyIcon: "arrow.left.arrow.right.circle",
            emptyTitle: "No Trades Yet",
            emptyMessage: "Completed trades across the league will show up here, graded and written up."
        )
    }

    // MARK: - Builder

    private var builderTab: some View {
        // The standalone builder owns its own values load + refresh.
        TradeAnalysisView(
            leagueStore: leagueStore,
            playerStore: playerStore,
            valuesStore: valuesStore,
            tradedPicks: historyStore.upcomingTradedPicks
        )
    }

    // MARK: - Suggestions

    private var suggestionsTab: some View {
        Group {
            if !valuesStore.hasValues {
                loadingOrValues
            } else if myRosterId == nil {
                EmptyStateView(
                    icon: "person.crop.square",
                    title: "Team Not Loaded",
                    message: "Trade suggestions appear once your team finishes loading."
                )
            } else {
                let recs = suggestions()
                if recs.isEmpty {
                    ScrollView {
                        VStack(spacing: XomperTheme.Spacing.md) {
                            suggestionsExplainer
                            EmptyStateView(
                                icon: "sparkles",
                                title: "No Fair-Value Upgrades",
                                message: "We couldn't find a balanced deal that improves a weak spot right now. Check back after roster or value changes."
                            )
                            .padding(.top, XomperTheme.Spacing.lg)
                        }
                        .padding(.horizontal, XomperTheme.Spacing.md)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                    }
                    .refreshable { await valuesStore.loadValues(forceRefresh: true) }
                } else {
                    ScrollView {
                        LazyVStack(spacing: XomperTheme.Spacing.md) {
                            suggestionsExplainer
                            ForEach(recs) { rec in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(XomperTheme.defaultAnimation) {
                                        selectedTab = .builder
                                    }
                                } label: {
                                    RecommendedTradeCard(rec)
                                }
                                .buttonStyle(.pressableCard)
                            }
                        }
                        .padding(.horizontal, XomperTheme.Spacing.md)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                    }
                    .refreshable { await valuesStore.loadValues(forceRefresh: true) }
                }
            }
        }
    }

    private var suggestionsExplainer: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(XomperColors.championGold)
                Text("Fair-value upgrades")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
            }
            Text("Balanced deals that ship a surplus player from a strong position and bring back help at one of your weak spots. Tap a suggestion to open the Builder and war-game it.")
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    /// Build fair-value upgrade suggestions for my team. Empty until
    /// values + rosters load, or when no weak/surplus pairing exists.
    private func suggestions() -> [RecommendedTrade] {
        guard let myRosterId,
              !leagueStore.myLeagueRosters.isEmpty else { return [] }

        let analyses = TeamAnalysisBuilder.build(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore
        )
        guard let mine = analyses.first(where: { $0.rosterId == myRosterId }) else { return [] }

        return RecommendedTradeBuilder.recommend(
            myAnalysis: mine,
            analyses: analyses,
            rosters: leagueStore.myLeagueRosters,
            playerStore: playerStore,
            valuesStore: valuesStore
        )
    }

    // MARK: - My Trades

    private var myTradesTab: some View {
        Group {
            if myRosterId == nil {
                EmptyStateView(
                    icon: "person.crop.square",
                    title: "Team Not Loaded",
                    message: "Your trade history appears once your team finishes loading."
                )
            } else {
                tradeFeed(
                    items: myTradeItems,
                    emptyIcon: "clock.arrow.circlepath",
                    emptyTitle: "No Trades Yet",
                    emptyMessage: "Trades involving your team will show up here once you make one."
                )
            }
        }
    }

    // MARK: - Shared trade feed

    /// Loading / error / empty / content states for a list of graded
    /// trades. Mirrors `NewsView`'s state machine but scoped to trades.
    @ViewBuilder
    private func tradeFeed(
        items: [NewsItem],
        emptyIcon: String,
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        if newsStore.isLoading && !newsStore.hasItems {
            LoadingView(message: "Loading league trades...")
        } else if let error = newsStore.error, !newsStore.hasItems {
            ErrorView(message: error.localizedDescription) {
                Task { await reloadNews(force: true) }
            }
        } else if items.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: emptyIcon,
                    title: emptyTitle,
                    message: emptyMessage
                )
                .padding(.top, XomperTheme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await reloadNews(force: true) }
        } else {
            ScrollView {
                LazyVStack(spacing: XomperTheme.Spacing.sm) {
                    ForEach(items) { item in
                        TradeNewsCard(item: item)
                            .padding(.horizontal, XomperTheme.Spacing.md)
                    }
                }
                .padding(.top, XomperTheme.Spacing.sm)
                .padding(.bottom, XomperTheme.Spacing.md)
            }
            .refreshable { await reloadNews(force: true) }
        }
    }

    // MARK: - Loading helpers

    @ViewBuilder
    private var loadingOrValues: some View {
        if valuesStore.isLoading {
            LoadingView(message: "Fetching player values...")
        } else if let error = valuesStore.error {
            ErrorView(message: error.localizedDescription) {
                Task { await valuesStore.loadValues(forceRefresh: true) }
            }
        } else {
            EmptyStateView(
                icon: "arrow.left.arrow.right.circle",
                title: "Values Not Loaded",
                message: "Pull to refresh to load dynasty values."
            )
            .task { await valuesStore.loadValues() }
        }
    }

    // MARK: - Load

    /// Fetch + grade the league trade feed. Needs rosters + users for
    /// team-name resolution, so it waits for them (matches `NewsView`).
    private func reloadNews(force: Bool) async {
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

// MARK: - Tabs

/// The four Trade Center sections, in bar order.
enum TradeCenterTab: String, CaseIterable, Identifiable, Sendable, Hashable {
    case recent
    case builder
    case suggestions
    case myTrades

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent:      "Recent"
        case .builder:     "Builder"
        case .suggestions: "Suggestions"
        case .myTrades:    "My Trades"
        }
    }
}

/// Pill-segmented control for the Trade Center tabs. Mirrors
/// `DraftSubTabBar`'s styling — championGold fill on the selected pill,
/// muted text otherwise — so the visual language matches the Draft
/// surface. Horizontally scrollable since four labels are tight in
/// portrait.
private struct TradeCenterTabBar: View {
    @Binding var selection: TradeCenterTab

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(TradeCenterTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .background(XomperColors.surfaceLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md + 2))
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
    }

    private func tabButton(_ tab: TradeCenterTab) -> some View {
        let isSelected = selection == tab
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                selection = tab
            }
        } label: {
            Text(tab.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? XomperColors.championGold : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TradeCenterView(
            leagueStore: LeagueStore(),
            playerStore: PlayerStore(),
            valuesStore: PlayerValuesStore(),
            newsStore: NewsStore(),
            teamStore: TeamStore(),
            historyStore: HistoryStore()
        )
    }
    .preferredColorScheme(.dark)
}
