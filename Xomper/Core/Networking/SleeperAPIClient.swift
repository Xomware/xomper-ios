import Foundation

// MARK: - Protocol

protocol SleeperAPIClientProtocol: Sendable {
    func fetchUser(_ usernameOrId: String) async throws -> SleeperUser
    func fetchUserLeagues(_ userId: String, season: String) async throws -> [League]
    func fetchLeague(_ leagueId: String) async throws -> League
    func fetchLeagueUsers(_ leagueId: String) async throws -> [SleeperUser]
    func fetchLeagueRosters(_ leagueId: String) async throws -> [Roster]
    func fetchLeagueMatchups(_ leagueId: String, week: Int) async throws -> [Matchup]
    func fetchDrafts(_ leagueId: String) async throws -> [Draft]
    func fetchDraftPicks(_ draftId: String) async throws -> [DraftPick]
    func fetchWinnersBracket(_ leagueId: String) async throws -> [PlayoffBracketMatch]
    func fetchLosersBracket(_ leagueId: String) async throws -> [PlayoffBracketMatch]
    func fetchTradedPicks(_ leagueId: String) async throws -> [TradedPick]
    func fetchTransactions(_ leagueId: String, week: Int) async throws -> [Transaction]
    func fetchNflState() async throws -> NflState
    func fetchAllPlayers() async throws -> [String: Player]
    func fetchAllPlayersRaw(etag: String?) async throws -> PlayerFetchResult
}

// MARK: - Player Fetch Result

enum PlayerFetchResult: Sendable {
    case notModified
    case updated(data: Data, etag: String?)
}

// MARK: - Errors

enum SleeperAPIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .httpError(let code):
            "Server returned status \(code)"
        case .decodingError(let error):
            "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Concrete Implementation

final class SleeperAPIClient: SleeperAPIClientProtocol {
    private let baseURL = "https://api.sleeper.app/v1"
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - User

    func fetchUser(_ usernameOrId: String) async throws -> SleeperUser {
        try await get("/user/\(usernameOrId)")
    }

    func fetchUserLeagues(_ userId: String, season: String) async throws -> [League] {
        try await get("/user/\(userId)/leagues/nfl/\(season)")
    }

    // MARK: - League

    func fetchLeague(_ leagueId: String) async throws -> League {
        try await get("/league/\(leagueId)")
    }

    func fetchLeagueUsers(_ leagueId: String) async throws -> [SleeperUser] {
        try await get("/league/\(leagueId)/users")
    }

    func fetchLeagueRosters(_ leagueId: String) async throws -> [Roster] {
        try await get("/league/\(leagueId)/rosters")
    }

    func fetchLeagueMatchups(_ leagueId: String, week: Int) async throws -> [Matchup] {
        try await get("/league/\(leagueId)/matchups/\(week)")
    }

    // MARK: - Draft

    func fetchDrafts(_ leagueId: String) async throws -> [Draft] {
        try await get("/league/\(leagueId)/drafts")
    }

    func fetchDraftPicks(_ draftId: String) async throws -> [DraftPick] {
        try await get("/draft/\(draftId)/picks")
    }

    // MARK: - Brackets

    func fetchWinnersBracket(_ leagueId: String) async throws -> [PlayoffBracketMatch] {
        try await get("/league/\(leagueId)/winners_bracket")
    }

    func fetchLosersBracket(_ leagueId: String) async throws -> [PlayoffBracketMatch] {
        try await get("/league/\(leagueId)/losers_bracket")
    }

    // MARK: - Picks & Transactions

    func fetchTradedPicks(_ leagueId: String) async throws -> [TradedPick] {
        try await get("/league/\(leagueId)/traded_picks")
    }

    func fetchTransactions(_ leagueId: String, week: Int) async throws -> [Transaction] {
        try await get("/league/\(leagueId)/transactions/\(week)")
    }

    // MARK: - NFL State

    func fetchNflState() async throws -> NflState {
        try await get("/state/nfl")
    }

    // MARK: - Players

    func fetchAllPlayers() async throws -> [String: Player] {
        try await get("/players/nfl")
    }

    func fetchAllPlayersRaw(etag: String?) async throws -> PlayerFetchResult {
        guard let url = URL(string: "\(baseURL)/players/nfl") else {
            throw SleeperAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SleeperAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SleeperAPIError.httpError(statusCode: 0)
        }

        if httpResponse.statusCode == 304 {
            return .notModified
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SleeperAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        let newEtag = httpResponse.value(forHTTPHeaderField: "Etag")
        return .updated(data: data, etag: newEtag)
    }

    // MARK: - Private

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw SleeperAPIError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: URLRequest(url: url))
        } catch {
            throw SleeperAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SleeperAPIError.httpError(statusCode: 0)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SleeperAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SleeperAPIError.decodingError(error)
        }
    }
}
