import SwiftUI

/// Tiny `@Observable` shim used to drive `ThisWeekMatchupsCard.refresh()`
/// from the outer `LandingView.refreshable` modifier.
///
/// Bumping `refreshToken` re-fires the card's `.task(id:)` which kicks off
/// a fresh `fetchLeagueMatchups` call. Lives at the `LandingView` level so
/// the pull-to-refresh handler can `await` matchups alongside the other
/// three data sources.
@Observable
@MainActor
final class ThisWeekMatchupsController {
    /// Bump this UUID to retrigger the matchups card's load task.
    var refreshToken: UUID = UUID()

    /// Awaitable handle the card sets while a load is in flight. The
    /// outer refresh waits on this so its spinner lingers until matchups
    /// land — keeps all four refreshes feeling synchronous from the
    /// user's perspective.
    var pendingRefresh: Task<Void, Never>?

    func bumpAndWait() async {
        refreshToken = UUID()
        await pendingRefresh?.value
    }
}

/// New default top-level destination — the league's "home" surface.
/// Composes four cards in a static order: Headline AI Review (hero) →
/// Announcements → Standings scroll bar → This-week matchups.
///
/// Pulls from existing stores (`AIReviewStore`, `LeagueStore`,
/// `NflStateStore`) so it bootstraps with no extra plumbing. The
/// matchups card owns its own one-shot fetch; everything else reads
/// state already populated by `MainShell.bootstrapPhase1/2`.
struct LandingView: View {
    var leagueStore: LeagueStore
    var authStore: AuthStore
    var nflStateStore: NflStateStore
    var aiReviewStore: AIReviewStore
    var announcementsStore: AnnouncementsStore
    var historyStore: HistoryStore
    var userStore: UserStore
    var newsStore: NewsStore
    var playerStore: PlayerStore
    var valuesStore: PlayerValuesStore
    var navStore: NavigationStore
    var router: AppRouter

    @State private var matchupsController = ThisWeekMatchupsController()

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                HeadlineAIReportCard(
                    store: aiReviewStore,
                    navStore: navStore,
                    router: router
                )

                UpcomingDraftCountdownCard(
                    historyStore: historyStore,
                    leagueStore: leagueStore,
                    nflStateStore: nflStateStore,
                    userStore: userStore,
                    navStore: navStore,
                    router: router
                )

                AnnouncementsCard(store: announcementsStore)

                NewsPreviewCard(
                    newsStore: newsStore,
                    leagueStore: leagueStore,
                    playerStore: playerStore,
                    valuesStore: valuesStore,
                    historyStore: historyStore,
                    navStore: navStore,
                    router: router
                )

                StandingsScrollBar(
                    leagueStore: leagueStore,
                    nflStateStore: nflStateStore,
                    authStore: authStore,
                    router: router
                )

                ThisWeekMatchupsCard(
                    leagueStore: leagueStore,
                    nflStateStore: nflStateStore,
                    authStore: authStore,
                    controller: matchupsController
                )
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .refreshable {
            await refreshAll()
        }
        .task {
            // Prime the latest-by-type lookup for the hero card.
            // All three loads run in parallel; the card picks the
            // newest. Each respects the store's 12-hour freshness.
            async let post: () = aiReviewStore.loadLatest(type: .postDraft)
            async let pre:  () = aiReviewStore.loadLatest(type: .preseason)
            async let week: () = aiReviewStore.loadLatest(type: .weekly)
            _ = await (post, pre, week)
        }
    }

    // MARK: - Refresh

    /// Pull-to-refresh: fans out to all four data sources in parallel.
    /// AI reports / NFL state / league reload are awaited directly;
    /// the matchups card refresh is delegated via the controller so the
    /// card stays self-contained.
    private func refreshAll() async {
        async let ai:       () = aiReviewStore.refresh()
        async let nfl:      () = nflStateStore.fetchState()
        async let league:   () = leagueStore.loadMyLeague()
        async let ann:      () = announcementsStore.load(force: true)
        async let matchups: () = matchupsController.bumpAndWait()
        async let news:     () = refreshNews()
        _ = await (ai, nfl, league, ann, matchups, news)
    }

    /// Force-refresh the news feed on pull-to-refresh. Gated on rosters
    /// so team-name resolution has its source data.
    private func refreshNews() async {
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
            forceRefresh: true
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

#Preview {
    NavigationStack {
        LandingView(
            leagueStore: LeagueStore(),
            authStore: AuthStore(),
            nflStateStore: NflStateStore(),
            aiReviewStore: AIReviewStore(),
            announcementsStore: AnnouncementsStore(),
            historyStore: HistoryStore(),
            userStore: UserStore(),
            newsStore: NewsStore(),
            playerStore: PlayerStore(),
            valuesStore: PlayerValuesStore(),
            navStore: NavigationStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
