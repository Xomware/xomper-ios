import SwiftUI

/// Self-contained Trophy Case section for `MyProfileView`.
/// Renders one `TrophyCaseCard` per championship the signed-in user has won.
/// Falls back to an empty-state card when the user has no titles, and to a
/// loading state when matchup history hasn't been fetched yet.
///
/// F7 will add a sibling Top Performers section next to this one — adding
/// it requires a single insertion in `MyProfileView`'s VStack, no refactor.
struct TrophyCaseSection: View {
    var historyStore: HistoryStore
    var leagueStore: LeagueStore
    var userId: String

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Trophy Case")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.leading, XomperTheme.Spacing.xs)

            content
        }
        .task {
            await ensureHistoryLoaded()
        }
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        let titles = historyStore.championships(forUserId: userId)

        if historyStore.isLoadingMatchups && historyStore.matchupHistory.isEmpty {
            loadingCard
        } else if titles.isEmpty {
            emptyCard
        } else {
            ForEach(titles) { championship in
                TrophyCaseCard(championship: championship)
            }
        }
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "trophy")
                .font(.title2)
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            Text("No championships yet — keep grinding.")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .xomperCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trophy Case empty. No championships yet.")
    }

    // MARK: - Loading state

    private var loadingCard: some View {
        VStack {
            ProgressView()
                .tint(XomperColors.championGold)
        }
        .frame(maxWidth: .infinity)
        .xomperCard()
        .accessibilityLabel("Loading championships")
    }

    // MARK: - History bootstrapping

    /// Triggers a matchup-history load if it isn't already in memory or in
    /// flight. Builds the league chain from `leagueStore` if necessary. Bails
    /// silently when the chain isn't ready — empty state is acceptable, the
    /// section will re-render once data arrives.
    private func ensureHistoryLoaded() async {
        guard !historyStore.isLoadingMatchups,
              historyStore.matchupHistory.isEmpty else { return }

        // Prefer the already-loaded chain. If empty, try to build it from the
        // current/my league. If neither is set yet, give up — the section will
        // re-evaluate on subsequent renders once league data lands.
        if leagueStore.leagueChain.isEmpty {
            guard let leagueId = leagueStore.currentLeague?.leagueId
                ?? leagueStore.myLeague?.leagueId else { return }
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }

        let chain = leagueStore.leagueChain
        guard !chain.isEmpty else { return }

        await historyStore.loadMatchupHistory(chain: chain)
    }
}
