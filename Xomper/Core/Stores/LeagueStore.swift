import Foundation

@Observable
@MainActor
final class LeagueStore {

    // MARK: - State

    private(set) var userLeagues: [League] = []
    private(set) var isLoadingUserLeagues = false
    private(set) var myLeague: League?
    private(set) var currentLeague: League?
    private(set) var myLeagueUsers: [SleeperUser] = []
    private(set) var currentLeagueUsers: [SleeperUser] = []
    private(set) var myLeagueRosters: [Roster] = []
    private(set) var currentLeagueRosters: [Roster] = []
    private(set) var leagueChain: [League] = []
    private(set) var winnersBracket: [PlayoffBracketMatch]?
    private(set) var losersBracket: [PlayoffBracketMatch]?
    private(set) var isLoadingBrackets = false
    private(set) var bracketError: Error?
    private(set) var isLoading = false
    private(set) var error: Error?

    private let apiClient: SleeperAPIClientProtocol
    var leagueChainCache: [League]?

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Load User Leagues

    func loadUserLeagues(userId: String, season: String) async {
        guard !isLoadingUserLeagues else { return }
        isLoadingUserLeagues = true

        do {
            userLeagues = try await apiClient.fetchUserLeagues(userId, season: season)
        } catch {
            // Non-fatal — userLeagues stays empty
        }

        isLoadingUserLeagues = false
    }

    // MARK: - Fetch League

    func fetchLeague(id: String) async throws -> League {
        try await apiClient.fetchLeague(id)
    }

    // MARK: - Fetch League Context (users + rosters in parallel)

    func fetchLeagueContext(leagueId: String) async throws -> (users: [SleeperUser], rosters: [Roster]) {
        async let users = apiClient.fetchLeagueUsers(leagueId)
        async let rosters = apiClient.fetchLeagueRosters(leagueId)
        return try await (users: users, rosters: rosters)
    }

    // MARK: - Load My League

    func loadMyLeague() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let leagueId = Config.whitelistedLeagueId
            let league = try await apiClient.fetchLeague(leagueId)
            let context = try await fetchLeagueContext(leagueId: leagueId)

            myLeague = league
            myLeagueUsers = context.users
            myLeagueRosters = context.rosters

            // Also set as current league for initial view
            currentLeague = league
            currentLeagueUsers = context.users
            currentLeagueRosters = context.rosters
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Resolve current-season home league by name

    /// Re-anchors `myLeague` (and `currentLeague` if it currently equals
    /// the old `myLeague`) to the current-season incarnation of the home
    /// dynasty league. Looks for a league in `userLeagues` whose `name`
    /// matches `Config.whitelistedLeagueName`. No-op when the name isn't
    /// configured, when no match is found, or when the match is already
    /// the active `myLeague`.
    ///
    /// Solves the dynasty-rollover problem: each new Sleeper season
    /// produces a *new* leagueId, so the hardcoded `whitelistedLeagueId`
    /// goes stale every year. By matching on the stable league name we
    /// follow the league forward automatically.
    func resolveAndAnchorMyLeagueByName() async {
        let targetName = Config.whitelistedLeagueName.trimmingCharacters(in: .whitespaces)
        guard !targetName.isEmpty else { return }

        let resolvedLeague = userLeagues.first { league in
            (league.name ?? "").caseInsensitiveCompare(targetName) == .orderedSame
        }

        guard let resolved = resolvedLeague else { return }
        guard resolved.leagueId != myLeague?.leagueId else { return }

        do {
            let context = try await fetchLeagueContext(leagueId: resolved.leagueId)
            let wasCurrentMatchingMy = currentLeague?.leagueId == myLeague?.leagueId

            myLeague = resolved
            myLeagueUsers = context.users
            myLeagueRosters = context.rosters

            if wasCurrentMatchingMy {
                currentLeague = resolved
                currentLeagueUsers = context.users
                currentLeagueRosters = context.rosters
            }

            // Invalidate the chain cache so subsequent loadLeagueChain
            // calls walk back from the new (current-season) league.
            leagueChainCache = nil
            leagueChain = []
        } catch {
            // Non-fatal — keep the previously-loaded myLeague.
        }
    }

    // MARK: - Load League Chain (Dynasty History)

    func loadLeagueChain(startingFrom leagueId: String) async {
        if let cached = leagueChainCache {
            leagueChain = cached
            return
        }

        var chain: [League] = []
        var currentId: String? = leagueId

        while let id = currentId {
            do {
                let league = try await apiClient.fetchLeague(id)
                chain.append(league)
                currentId = league.previousLeagueId
            } catch {
                break
            }
        }

        leagueChainCache = chain
        leagueChain = chain
    }

    // MARK: - Set Current League

    func setCurrentLeague(_ league: League, users: [SleeperUser], rosters: [Roster]) {
        currentLeague = league
        currentLeagueUsers = users
        currentLeagueRosters = rosters
    }

    /// Switching the global "current league" used to overwrite all the
    /// tray destinations' data (Standings, Matchups, Drafts...) when a
    /// user tapped another league in profile or search. The product call
    /// is to keep the home league (`myLeague`) anchored as the only
    /// source of truth for tray destinations — viewing other leagues is
    /// a future feature that should use a pushed `.leagueOverview` route
    /// fetching its own data, not mutate global state.
    ///
    /// Kept as a no-op stub so existing call sites don't need to be
    /// torn out in this same patch. Will be removed once those sites
    /// are migrated to a push-based browser.
    func switchToLeague(id: String) async {
        // Intentionally no-op. See doc comment.
    }

    // MARK: - Fetch Brackets

    func fetchBrackets(leagueId: String) async {
        guard !isLoadingBrackets else { return }
        isLoadingBrackets = true
        bracketError = nil

        do {
            async let winners = apiClient.fetchWinnersBracket(leagueId)
            async let losers = apiClient.fetchLosersBracket(leagueId)
            let (w, l) = try await (winners, losers)
            winnersBracket = w
            losersBracket = l
        } catch {
            bracketError = error
        }

        isLoadingBrackets = false
    }

    // MARK: - Reset

    func reset() {
        userLeagues = []
        myLeague = nil
        currentLeague = nil
        myLeagueUsers = []
        currentLeagueUsers = []
        myLeagueRosters = []
        currentLeagueRosters = []
        leagueChain = []
        leagueChainCache = nil
        winnersBracket = nil
        losersBracket = nil
        bracketError = nil
        error = nil
    }
}
