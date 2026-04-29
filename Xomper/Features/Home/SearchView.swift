import SwiftUI

/// Three-mode search surface: Sleeper user, Sleeper league, or NFL player.
/// State and async work live on `SearchStore`; this view is a thin observer
/// that binds the field, picks the mode, and renders results via
/// `SearchResultGroup`.
///
/// `SearchStore` is held in view-local `@State`. Search state is intentionally
/// ephemeral — leaving and re-entering search resets the query and mode.
struct SearchView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var authStore: AuthStore
    var router: AppRouter
    var navStore: NavigationStore

    @State private var searchStore: SearchStore
    @State private var searchButtonPressed = false

    init(
        leagueStore: LeagueStore,
        playerStore: PlayerStore,
        authStore: AuthStore,
        router: AppRouter,
        navStore: NavigationStore
    ) {
        self.leagueStore = leagueStore
        self.playerStore = playerStore
        self.authStore = authStore
        self.router = router
        self.navStore = navStore
        _searchStore = State(
            initialValue: SearchStore(playerStore: playerStore)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchControls
            resultArea
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Search Controls

    private var searchControls: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            modeToggle
            searchField
            searchHint
        }
        .padding(XomperTheme.Spacing.md)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(SearchMode.allCases) { mode in
                modeButton(mode)
            }
        }
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search mode")
    }

    private func modeButton(_ mode: SearchMode) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(XomperTheme.defaultAnimation) {
                searchStore.setMode(mode)
            }
        } label: {
            Text(mode.title)
                .font(.subheadline)
                .fontWeight(searchStore.mode == mode ? .semibold : .regular)
                .foregroundStyle(
                    searchStore.mode == mode
                        ? XomperColors.deepNavy
                        : XomperColors.textSecondary
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(
                    searchStore.mode == mode
                        ? XomperColors.championGold
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) search")
        .accessibilityAddTraits(searchStore.mode == mode ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)

                TextField(
                    searchStore.mode.placeholder,
                    text: Binding(
                        get: { searchStore.query },
                        set: { searchStore.setQuery($0) }
                    )
                )
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { searchStore.performSearch() }

                if !searchStore.query.isEmpty {
                    Button {
                        searchStore.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(XomperColors.textMuted)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .background(XomperColors.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))

            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                searchStore.performSearch()
            } label: {
                Text("Search")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.deepNavy)
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .frame(minHeight: XomperTheme.minTouchTarget)
                    .background(XomperColors.championGold)
                    .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            }
            .buttonStyle(.plain)
            .scaleEffect(searchButtonPressed ? 0.95 : 1.0)
            .animation(XomperTheme.defaultAnimation, value: searchButtonPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in searchButtonPressed = true }
                    .onEnded { _ in searchButtonPressed = false }
            )
            .disabled(searchStore.query.trimmingCharacters(in: .whitespaces).isEmpty || searchStore.isSearching)
            .opacity(searchStore.query.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            .accessibilityLabel("Search")
            .accessibilityHint("Double tap to search for \(searchStore.mode.title.lowercased())")
        }
    }

    private var searchHint: some View {
        Text(searchStore.mode.hint)
            .font(.caption)
            .foregroundStyle(XomperColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Result Area

    @ViewBuilder
    private var resultArea: some View {
        if searchStore.isSearching {
            Spacer()
            ProgressView()
                .tint(XomperColors.championGold)
                .accessibilityLabel("Searching")
            Spacer()
        } else if let errorMessage = searchStore.errorMessage {
            Spacer()
            searchErrorView(errorMessage)
            Spacer()
        } else if !searchStore.results.isEmpty {
            SearchResultGroup(
                results: searchStore.results,
                mode: searchStore.mode,
                onUserTap: { user in
                    router.navigate(to: .userProfile(userId: user.userId ?? ""))
                },
                onLeagueTap: { league in
                    navigateToLeague(league)
                },
                onPlayerTap: { playerId in
                    router.navigate(to: .playerDetail(playerId: playerId))
                },
                ownerLookup: { playerId in
                    resolveOwnership(forPlayerId: playerId)
                }
            )
        } else if searchStore.hasSearched {
            Spacer()
            noResultsView
            Spacer()
        } else {
            Spacer()
            searchPromptView
            Spacer()
        }
    }

    // MARK: - Empty / prompt / error states

    private var noResultsView: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            Text("No results found")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)

            Text("Try a different \(searchStore.mode.emptyNoun).")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func searchErrorView(_ message: String) -> some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.errorRed)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var searchPromptView: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            Text(searchStore.mode.promptCopy)
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - League navigation

    private func navigateToLeague(_ league: League) {
        // switchToLeague is now a no-op (see LeagueStore docs) — tray
        // destinations always show the home league. Future iteration:
        // push a dedicated `.leagueOverview(leagueId:)` route here.
        navStore.select(.standings, router: router)
    }

    // MARK: - Player ownership in home league

    /// Looks up which CLT roster owns a given player. Pure dictionary
    /// lookup over `leagueStore.myLeagueRosters` + `myLeagueUsers`.
    /// Returns `nil` for free agents.
    private func resolveOwnership(forPlayerId playerId: String) -> PlayerOwnership? {
        guard !playerId.isEmpty else { return nil }

        let owningRoster = leagueStore.myLeagueRosters.first { roster in
            (roster.players ?? []).contains(playerId)
                || (roster.starters ?? []).contains(playerId)
                || (roster.taxi ?? []).contains(playerId)
                || (roster.reserve ?? []).contains(playerId)
        }
        guard let roster = owningRoster, let ownerId = roster.ownerId else { return nil }

        let user = leagueStore.myLeagueUsers.first { $0.userId == ownerId }
        let teamName = user?.teamName
            ?? user?.resolvedDisplayName
            ?? "Unknown"

        let isMine = ownerId == authStore.sleeperUserId
        return PlayerOwnership(teamName: teamName, isMine: isMine)
    }
}

#Preview {
    NavigationStack {
        SearchView(
            leagueStore: LeagueStore(),
            playerStore: PlayerStore(),
            authStore: AuthStore(),
            router: AppRouter(),
            navStore: NavigationStore()
        )
    }
    .preferredColorScheme(.dark)
}
