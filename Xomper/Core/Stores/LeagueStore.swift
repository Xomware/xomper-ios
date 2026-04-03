import Foundation

@Observable
@MainActor
final class LeagueStore {

    // MARK: - State

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
    private var leagueChainCache: [League]?

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
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

    /// Loads and switches to a different league by ID.
    func switchToLeague(id: String) async {
        isLoading = true
        error = nil

        do {
            let league = try await apiClient.fetchLeague(id)
            let context = try await fetchLeagueContext(leagueId: id)
            currentLeague = league
            currentLeagueUsers = context.users
            currentLeagueRosters = context.rosters
        } catch {
            self.error = error
        }

        isLoading = false
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
