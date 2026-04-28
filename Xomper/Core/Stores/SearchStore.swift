import Foundation

// MARK: - SearchMode

/// Three exclusive search modes surfaced as a segmented toggle in `SearchView`.
/// Lifted out of the view so `SearchStore` can switch on it from outside the
/// view layer.
enum SearchMode: String, CaseIterable, Identifiable, Sendable {
    case user
    case league
    case player

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "User"
        case .league: "League"
        case .player: "Player"
        }
    }

    var placeholder: String {
        switch self {
        case .user: "Enter a Sleeper username..."
        case .league: "Enter a Sleeper league ID..."
        case .player: "Search players by name..."
        }
    }

    var hint: String {
        switch self {
        case .user: "Search by Sleeper username or user ID"
        case .league: "Paste a Sleeper league ID to view any league"
        case .player: "Find any NFL player by name"
        }
    }

    /// Singular noun used in the empty-results "Try a different X" copy.
    var emptyNoun: String {
        switch self {
        case .user: "username"
        case .league: "league ID"
        case .player: "player name"
        }
    }

    /// Prompt copy shown before the user has searched anything in this mode.
    var promptCopy: String {
        switch self {
        case .user: "Search for Sleeper users"
        case .league: "Search for Sleeper leagues"
        case .player: "Search for NFL players"
        }
    }
}

// MARK: - SearchStore

/// Owns all state and async work for `SearchView`. View becomes a thin
/// observer; logic — including the 500ms debounce — lives here.
///
/// User and league modes hit `SleeperAPIClient`. Player mode is an in-memory
/// filter against `PlayerStore.players` (no network).
///
/// Player mode short-circuits below 2 characters to keep the lazy filter from
/// returning enormous result sets on a single keystroke.
@Observable
@MainActor
final class SearchStore {

    // MARK: - State

    /// Current text in the search field. Setting via `setQuery(_:)` triggers
    /// the 500ms debounce → `performSearch()`.
    private(set) var query: String = ""

    /// Active search mode. Setting via `setMode(_:)` clears prior results.
    private(set) var mode: SearchMode = .user

    /// Snapshot of `query` at the moment the debounce window elapsed and the
    /// async search fired. Surfaced for tests / introspection only.
    private(set) var debouncedText: String = ""

    /// True while an async search is in flight (user / league only — player
    /// mode is synchronous and never flips this on).
    private(set) var isSearching: Bool = false

    /// Last error message to surface in the UI, if any.
    private(set) var errorMessage: String?

    /// True once the user has triggered at least one search in the current
    /// mode. Cleared when `setMode(_:)` switches modes.
    private(set) var hasSearched: Bool = false

    /// Aggregated result payload. Only one bucket is populated per mode in v1.
    private(set) var results: SearchResults = .empty

    // MARK: - Dependencies

    private let apiClient: SleeperAPIClientProtocol
    private let playerStore: PlayerStore

    private var debounceTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        playerStore: PlayerStore,
        apiClient: SleeperAPIClientProtocol = SleeperAPIClient()
    ) {
        self.playerStore = playerStore
        self.apiClient = apiClient
    }

    // MARK: - Mutators

    /// Update `query` and (re)schedule the 500ms debounce. The debounced
    /// search runs against the *latest* query value at the time the timer
    /// fires.
    func setQuery(_ newValue: String) {
        query = newValue
        scheduleDebounce(newValue)
    }

    /// Switch search modes. Clears results, error, and `hasSearched` so the
    /// new mode starts in its prompt state.
    func setMode(_ newMode: SearchMode) {
        guard newMode != mode else { return }
        mode = newMode
        clearResults()
    }

    /// Clear typed text and reset the result/error/hasSearched flags. Used by
    /// the field's clear (X) button.
    func clear() {
        debounceTask?.cancel()
        searchTask?.cancel()
        query = ""
        debouncedText = ""
        clearResults()
    }

    /// Fire a search immediately, bypassing the debounce. Used by the
    /// keyboard `.search` submit and the "Search" button.
    func performSearch() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }

        debounceTask?.cancel()
        searchTask?.cancel()

        // Player mode is synchronous (in-memory filter). User/league hit the
        // network and need a spinner.
        switch mode {
        case .user, .league:
            isSearching = true
            errorMessage = nil
            results = .empty
            hasSearched = true
            searchTask = Task { [weak self] in
                guard let self else { return }
                switch self.mode {
                case .user:
                    await self.searchUser(term)
                case .league:
                    await self.searchLeague(term)
                case .player:
                    break
                }
            }
        case .player:
            errorMessage = nil
            results = .empty
            hasSearched = true
            searchPlayer(term)
        }
    }

    // MARK: - Debounce

    private func scheduleDebounce(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.debouncedText = text
            // Empty (or whitespace-only) query clears any stale results
            // without triggering a search.
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                self.clearResults()
                return
            }
            self.performSearch()
        }
    }

    // MARK: - Per-mode searches

    private func searchUser(_ term: String) async {
        do {
            let user = try await apiClient.fetchUser(term)
            results = SearchResults(user: user, league: nil, players: [])
        } catch {
            results = .empty
        }
        isSearching = false
    }

    private func searchLeague(_ term: String) async {
        do {
            let league = try await apiClient.fetchLeague(term)
            results = SearchResults(user: nil, league: league, players: [])
        } catch {
            results = .empty
        }
        isSearching = false
    }

    /// Player search is an in-memory filter against `PlayerStore.players`.
    /// Below 2 characters we no-op (no spinner, no error, empty results) to
    /// avoid returning multi-thousand-row result sets on a single keystroke.
    private func searchPlayer(_ term: String) {
        guard term.count >= 2 else {
            results = .empty
            return
        }
        let matches = playerStore.search(query: term, limit: 25)
        results = SearchResults(user: nil, league: nil, players: matches)
    }

    // MARK: - Internal helpers

    private func clearResults() {
        results = .empty
        errorMessage = nil
        hasSearched = false
    }
}
