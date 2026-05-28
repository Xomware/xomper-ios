import SwiftUI

/// Mocks tab — client-side rookie mock-draft engine. Replaces the
/// earlier backend-fetched view that pulled `report_type=mock` rows
/// from Dynamo. The engine is pure Swift (see
/// `Features/DraftOrder/Mocks/MockDraftEngine`) and runs against the
/// live FantasyCalc rookie pool + the Sleeper-set slot order for the
/// upcoming draft.
///
/// Two viewing modes (see `PLAN.md §5`):
/// - **Pure**: one mock per personality (5 mocks, every team picks
///   the same way).
/// - **Mixed**: 3 mocks, each with a random per-team personality
///   assignment.
///
/// Cached for the session via `MockDraftStore`. Reshuffle bumps the
/// seed and regenerates the stochastic mocks (Wildcard + Hype Train)
/// — deterministic mocks (BPA / Team Fit / Win-Now) reuse the same
/// inputs and produce identical output.
struct MocksView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var playerValuesStore: PlayerValuesStore
    var playerPointsStore: PlayerPointsStore
    var nflStateStore: NflStateStore
    var userStore: UserStore

    @State private var store = MockDraftStore()
    @State private var expandedIds: Set<String> = []

    var body: some View {
        Group {
            switch store.status {
            case .idle, .pending:
                LoadingView(message: "Generating mock drafts…")
            case .noUpcomingDraft:
                EmptyStateView(
                    icon: "calendar.badge.exclamationmark",
                    title: "No Upcoming Draft",
                    message: "The commissioner hasn't set up the next draft yet. Once it's scheduled in Sleeper, mocks will appear here."
                )
            case .noRookiePool:
                EmptyStateView(
                    icon: "person.fill.questionmark",
                    title: "No Rookies Found",
                    message: "FantasyCalc didn't return any rookies with non-zero dynasty value. Try refreshing after the NFL draft."
                )
            case .error(let message):
                ErrorView(message: message) {
                    loadDependencies()
                }
            case .ready:
                content
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .task(id: triggerKey) {
            loadDependencies()
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Ready content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                topBar

                if store.didFallbackPool {
                    fallbackNotice(
                        text: "Rookie pool widened to include 1st-year vets — strict yearsExp = 0 pool was too small."
                    )
                }
                if store.didFallbackTeamContext {
                    fallbackNotice(
                        text: "Team Fit degraded to BPA — no weekly points loaded yet."
                    )
                }

                switch store.mode {
                case .pure:
                    pureCards
                case .mixed:
                    mixedCards
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
    }

    // MARK: - Top bar (mode toggle + reshuffle)

    private var topBar: some View {
        HStack(alignment: .center, spacing: XomperTheme.Spacing.sm) {
            modeToggle
            Spacer(minLength: 0)
            reshuffleButton
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modePill(.pure, label: "Pure")
            modePill(.mixed, label: "Mixed")
        }
        .padding(2)
        .background(XomperColors.surfaceLight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md + 2))
    }

    private func modePill(_ mode: MockDraftResult.Mode, label: String) -> some View {
        let isSelected = store.mode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                store.setMode(mode)
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, 6)
                .frame(minWidth: 64)
                .background(isSelected ? XomperColors.championGold : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("\(label) mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var reshuffleButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.reshuffle(
                leagueStore: leagueStore,
                historyStore: historyStore,
                playerStore: playerStore,
                playerValuesStore: playerValuesStore,
                playerPointsStore: playerPointsStore,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
        } label: {
            HStack(spacing: XomperTheme.Spacing.xxs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Reshuffle")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(XomperColors.championGold)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .strokeBorder(XomperColors.championGold.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Reshuffle stochastic mocks")
    }

    private func fallbackNotice(text: String) -> some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(XomperColors.championGold)
            Text(text)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    // MARK: - Cards

    private var pureCards: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            ForEach(DraftPersonality.displayOrder) { personality in
                if let result = store.pureMocks[personality] {
                    card(for: result)
                }
            }
        }
    }

    private var mixedCards: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            ForEach(store.mixedMocks) { result in
                card(for: result)
            }
        }
    }

    @ViewBuilder
    private func card(for result: MockDraftResult) -> some View {
        MockDraftCard(
            result: result,
            slotOrder: store.slotOrder,
            myUserId: userStore.myUser?.userId,
            isExpanded: binding(for: result.id)
        )
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedIds.contains(id) },
            set: { newValue in
                if newValue {
                    expandedIds.insert(id)
                } else {
                    expandedIds.remove(id)
                }
            }
        )
    }

    // MARK: - Side-effects

    /// Pulls the dependencies the store needs and triggers generation.
    /// Idempotent — `MockDraftStore.ensureLoaded` no-ops when the
    /// inputs haven't changed.
    private func loadDependencies() {
        Task {
            // 1. Upcoming draft (slot order). Loaded by Live tab too;
            //    `historyStore.loadUpcomingDraft` is cached per season.
            if historyStore.upcomingDraft == nil,
               let userId = userStore.myUser?.userId {
                await historyStore.loadUpcomingDraft(
                    season: nflStateStore.currentSeason,
                    homeLeagueName: leagueStore.resolvedHomeLeagueName,
                    userId: userId
                )
            }
            // 2. FantasyCalc rookie values.
            if !playerValuesStore.hasValues {
                await playerValuesStore.loadValues()
            }
            // 3. Per-week per-roster points for Team Fit needBoost.
            if playerPointsStore.weeklyRosterPoints.isEmpty,
               let leagueId = leagueStore.myLeague?.leagueId {
                await playerPointsStore.loadRegularSeason(
                    leagueId: leagueId,
                    regularSeasonLastWeek: regularSeasonLastWeek
                )
            }
            // 4. Generate.
            store.ensureLoaded(
                leagueStore: leagueStore,
                historyStore: historyStore,
                playerStore: playerStore,
                playerValuesStore: playerValuesStore,
                playerPointsStore: playerPointsStore,
                regularSeasonLastWeek: regularSeasonLastWeek
            )
            // 5. Default-expand the first card so users land on
            //    content per the plan.
            if expandedIds.isEmpty {
                if let first = DraftPersonality.displayOrder
                    .compactMap({ store.pureMocks[$0]?.id })
                    .first {
                    expandedIds = [first]
                }
            }
        }
    }

    private func refresh() async {
        // Bump the seed + reload dependencies.
        await playerValuesStore.loadValues(forceRefresh: true)
        store.reshuffle(
            leagueStore: leagueStore,
            historyStore: historyStore,
            playerStore: playerStore,
            playerValuesStore: playerValuesStore,
            playerPointsStore: playerPointsStore,
            regularSeasonLastWeek: regularSeasonLastWeek
        )
    }

    // MARK: - Triggers

    /// Composite key the `.task` watches — re-runs `loadDependencies`
    /// when the upcoming-draft id or FantasyCalc snapshot changes.
    private var triggerKey: String {
        let draft = historyStore.upcomingDraft?.draftId ?? "no-draft"
        let stamp = playerValuesStore.lastLoadedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "no-values"
        let players = playerStore.players.isEmpty ? "no-players" : "players"
        return "\(draft)|\(stamp)|\(players)"
    }

    /// Last regular-season week to feed into the per-position HPP
    /// calc. Reuses `NflStateStore` if present; defaults to 14 (our
    /// league's regular season).
    private var regularSeasonLastWeek: Int {
        // Default — matches PayoutsView and Live draft tab. If a
        // store-driven value is needed later, lift it through here.
        14
    }
}
