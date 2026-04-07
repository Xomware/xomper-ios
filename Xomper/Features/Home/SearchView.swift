import SwiftUI
import Combine

struct SearchView: View {
    var leagueStore: LeagueStore
    var router: AppRouter

    @State private var searchText = ""
    @State private var searchMode: SearchMode = .user
    @State private var isSearching = false
    @State private var searchResult: SearchResult?
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchButtonPressed = false
    @State private var debouncedText = ""
    @State private var debounceTask: Task<Void, Never>?

    private let apiClient: SleeperAPIClientProtocol = SleeperAPIClient()

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
                searchMode = mode
                clearResults()
            }
        } label: {
            Text(mode.title)
                .font(.subheadline)
                .fontWeight(searchMode == mode ? .semibold : .regular)
                .foregroundStyle(
                    searchMode == mode
                        ? XomperColors.deepNavy
                        : XomperColors.textSecondary
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(
                    searchMode == mode
                        ? XomperColors.championGold
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) search")
        .accessibilityAddTraits(searchMode == mode ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)

                TextField(
                    searchMode.placeholder,
                    text: $searchText
                )
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { performSearch() }
                .onChange(of: searchText) { _, newValue in
                    scheduleDebounce(newValue)
                }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        clearResults()
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
                performSearch()
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
            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            .opacity(searchText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            .accessibilityLabel("Search")
            .accessibilityHint("Double tap to search for \(searchMode.title.lowercased())")
        }
    }

    private var searchHint: some View {
        Text(searchMode.hint)
            .font(.caption)
            .foregroundStyle(XomperColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Result Area

    @ViewBuilder
    private var resultArea: some View {
        if isSearching {
            Spacer()
            ProgressView()
                .tint(XomperColors.championGold)
                .accessibilityLabel("Searching")
            Spacer()
        } else if let errorMessage {
            Spacer()
            searchErrorView(errorMessage)
            Spacer()
        } else if let result = searchResult {
            searchResultView(result)
        } else if hasSearched {
            Spacer()
            noResultsView
            Spacer()
        } else {
            Spacer()
            searchPromptView
            Spacer()
        }
    }

    // MARK: - Result Views

    private func searchResultView(_ result: SearchResult) -> some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                switch result {
                case .user(let user):
                    userResultCard(user)
                case .league(let league):
                    leagueResultCard(league)
                }
            }
            .padding(XomperTheme.Spacing.md)
        }
    }

    private func userResultCard(_ user: SleeperUser) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            router.navigate(to: .userProfile(userId: user.userId ?? ""))
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: user.avatar,
                    size: XomperTheme.AvatarSize.lg
                )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(user.resolvedDisplayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)

                    if let username = user.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(XomperColors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View profile for \(user.resolvedDisplayName)")
        .accessibilityHint("Double tap to open profile")
    }

    private func leagueResultCard(_ league: League) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            navigateToLeague(league)
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: league.avatar,
                    size: XomperTheme.AvatarSize.lg,
                    isTeam: true
                )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(league.displayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.sm) {
                        Label("\(league.season)", systemImage: "calendar")
                        Label("\(league.totalRosters ?? 0) teams", systemImage: "person.3")
                    }
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)

                    if league.isDynasty {
                        Text("Dynasty")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(XomperColors.deepNavy)
                            .padding(.horizontal, XomperTheme.Spacing.sm)
                            .padding(.vertical, XomperTheme.Spacing.xs)
                            .background(XomperColors.championGold)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(league.displayName)")
        .accessibilityHint("Double tap to open league")
    }

    private var noResultsView: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)

            Text("No results found")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)

            Text("Try a different \(searchMode == .user ? "username" : "league ID").")
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

            Text("Search for \(searchMode == .user ? "Sleeper users" : "Sleeper leagues")")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Search Logic

    private func scheduleDebounce(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            debouncedText = text
        }
    }

    private func performSearch() {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }

        debounceTask?.cancel()
        isSearching = true
        errorMessage = nil
        searchResult = nil
        hasSearched = true

        Task {
            switch searchMode {
            case .user:
                await searchUser(term)
            case .league:
                await searchLeague(term)
            }
        }
    }

    private func searchUser(_ term: String) async {
        do {
            let user = try await apiClient.fetchUser(term)
            searchResult = .user(user)
        } catch {
            searchResult = nil
        }
        isSearching = false
    }

    private func searchLeague(_ term: String) async {
        do {
            let league = try await apiClient.fetchLeague(term)
            searchResult = .league(league)
        } catch {
            searchResult = nil
        }
        isSearching = false
    }

    private func clearResults() {
        searchResult = nil
        errorMessage = nil
        hasSearched = false
    }

    private func navigateToLeague(_ league: League) {
        Task {
            await leagueStore.switchToLeague(id: league.leagueId)
            router.switchTab(.league)
        }
    }
}

// MARK: - Supporting Types

private enum SearchMode: String, CaseIterable, Identifiable {
    case user
    case league

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "User"
        case .league: "League"
        }
    }

    var placeholder: String {
        switch self {
        case .user: "Enter a Sleeper username..."
        case .league: "Enter a Sleeper league ID..."
        }
    }

    var hint: String {
        switch self {
        case .user: "Search by Sleeper username or user ID"
        case .league: "Paste a Sleeper league ID to view any league"
        }
    }
}

private enum SearchResult {
    case user(SleeperUser)
    case league(League)
}

#Preview {
    NavigationStack {
        SearchView(
            leagueStore: LeagueStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
