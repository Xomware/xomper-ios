import SwiftUI

/// Root of the Archive tray destination. A single scrolling page composed of
/// three cards that hub the league's historical surfaces:
///
/// - **Past Standings** — pushes a per-year list; rows render historical
///   standings reconstructed from `MatchupHistoryRecord`s.
/// - **Past Matchup History** — switches the top-level destination to
///   `.matchupHistory` (reuses the existing browser surface).
/// - **Past Drafts** — pushes a year picker that sets the shared
///   `SeasonStore.selectedSeason` then switches to `.draftHistory`, landing
///   the Draft tab on the chosen prior year via F3's sub-tab UI.
///
/// Lazy-loads matchup + draft history on first appearance when the store is
/// empty so the cards have something to drill into when the user navigates
/// here cold.
struct ArchiveView: View {
    let navStore: NavigationStore
    let router: AppRouter
    let historyStore: HistoryStore
    let leagueStore: LeagueStore
    let authStore: AuthStore
    let teamStore: TeamStore
    let seasonStore: SeasonStore

    var body: some View {
        Group {
            if isEmpty {
                EmptyStateView(
                    icon: "archivebox",
                    title: "No archive yet",
                    message: "Past seasons appear here once they're loaded."
                )
            } else {
                cards
            }
        }
        .background(XomperColors.bgDark)
        .task {
            await ensureLoaded()
        }
    }

    // MARK: - Cards

    private var cards: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                ArchiveHubCard(
                    icon: "list.number",
                    title: "Past Standings",
                    subtitle: "Final regular-season records by year",
                    action: {
                        router.navigate(to: .archivePastStandings)
                    }
                )

                ArchiveHubCard(
                    icon: "clock.arrow.circlepath",
                    title: "Past Matchup History",
                    subtitle: "Weekly results from prior seasons",
                    action: {
                        navStore.select(.matchupHistory, router: router)
                    }
                )

                ArchiveHubCard(
                    icon: "list.clipboard.fill",
                    title: "Past Drafts",
                    subtitle: "Pick boards from previous years",
                    action: {
                        router.navigate(to: .archivePastDraftPicker)
                    }
                )
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Empty / load

    /// Archive is "empty" when we have neither matchup nor draft history.
    /// Drafts may exist without matchups (and vice versa) — either is enough
    /// to surface meaningful cards.
    private var isEmpty: Bool {
        historyStore.matchupHistory.isEmpty && historyStore.draftHistory.isEmpty
    }

    /// Best-effort lazy fetch. Only fires when the underlying store is empty
    /// so re-visits don't refetch. Both loads run in parallel and tolerate
    /// failure — the empty-state view will simply persist.
    private func ensureLoaded() async {
        guard isEmpty else { return }
        // Make sure we have a league chain before asking history to load.
        if leagueStore.leagueChain.isEmpty,
           let leagueId = leagueStore.myLeague?.leagueId {
            await leagueStore.loadLeagueChain(startingFrom: leagueId)
        }
        let chain = leagueStore.leagueChain
        guard !chain.isEmpty else { return }

        async let matchups: () = historyStore.loadMatchupHistory(chain: chain)
        async let drafts:   () = historyStore.loadDraftHistory(chain: chain)
        _ = await (matchups, drafts)
    }
}

// MARK: - Card chrome

/// Single archive hub card. Matches the `pressableCard` button-style + rounded
/// `bgCard` chrome used by other Landing/League cards so the page feels of-a-piece.
private struct ArchiveHubCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                    .frame(width: 36, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .xomperShadow(.sm)
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
        .accessibilityHint("Double tap to open")
    }
}

#Preview {
    NavigationStack {
        ArchiveView(
            navStore: NavigationStore(),
            router: AppRouter(),
            historyStore: HistoryStore(),
            leagueStore: LeagueStore(),
            authStore: AuthStore(),
            teamStore: TeamStore(),
            seasonStore: SeasonStore()
        )
    }
    .preferredColorScheme(.dark)
}
