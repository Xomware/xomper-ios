import Foundation

/// Per-player season totals from STARTING lineups only. Drives the
/// position-MVP payout categories — a player only counts toward their
/// position MVP when their owner actually started them in a given
/// week (bench points don't count).
///
/// Lazy-loaded: PayoutsView triggers `loadRegularSeason` on appear,
/// hits `/league/{id}/matchups/{week}` for each regular-season week
/// not yet fetched, walks each matchup's parallel `starters` /
/// `starters_points` arrays, and accumulates points by player ID.
///
/// Cache key is (leagueId, weeksFetched). Weeks that fail to fetch
/// are simply skipped on this run; they'll be retried next time the
/// view appears.
@Observable
@MainActor
final class PlayerPointsStore {

    /// player_id → season starter-points total (regular season only).
    private(set) var seasonStarterPoints: [String: Double] = [:]

    /// "(week)-(rosterId)" → [player_id: points scored that week].
    /// Captures the FULL roster (starters + bench) so the
    /// HighestPossibleCalculator can re-pick an optimal lineup
    /// independent of what was actually started.
    private(set) var weeklyRosterPoints: [String: [String: Double]] = [:]

    /// (leagueId, week) we've already aggregated. Resets when
    /// `reset()` is called (e.g. league switch).
    private(set) var fetched: Set<String> = []

    private(set) var isLoading = false
    private(set) var error: Error?

    private let apiClient: SleeperAPIClientProtocol

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
    }

    /// Walks every regular-season week (1 through `regularSeasonLastWeek`)
    /// for the given league chain. Reads from the head league (current
    /// season). Multi-season chain walking can be added later if MVP
    /// pots ever need to span multiple years; for now MVP is per-season.
    func loadRegularSeason(
        leagueId: String,
        regularSeasonLastWeek: Int
    ) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        var totals = seasonStarterPoints
        for week in 1...max(regularSeasonLastWeek, 1) {
            let key = cacheKey(leagueId: leagueId, week: week)
            if fetched.contains(key) { continue }
            do {
                let matchups = try await apiClient.fetchLeagueMatchups(leagueId, week: week)
                for matchup in matchups {
                    // Starter aggregation (drives Position MVPs)
                    if let starters = matchup.starters,
                       let starterPoints = matchup.startersPoints {
                        let count = min(starters.count, starterPoints.count)
                        for i in 0..<count {
                            let pid = starters[i]
                            let pts = starterPoints[i]
                            guard !pid.isEmpty, pid != "0" else { continue }
                            totals[pid, default: 0] += pts
                        }
                    }

                    // Per-week per-roster full-roster points (drives
                    // Highest Possible Points calc for #57 draft order)
                    if let players = matchup.players,
                       let pp = matchup.playersPoints {
                        var rosterScores: [String: Double] = [:]
                        for pid in players {
                            guard !pid.isEmpty, pid != "0" else { continue }
                            if let pts = pp[pid] { rosterScores[pid] = pts }
                        }
                        let rosterKey = "\(week)-\(matchup.rosterId)"
                        weeklyRosterPoints[rosterKey] = rosterScores
                    }
                }
                fetched.insert(key)
            } catch {
                // Non-fatal — try the rest of the season; surface only
                // if every week failed.
                self.error = error
            }
        }
        seasonStarterPoints = totals
    }

    func points(for playerId: String) -> Double {
        seasonStarterPoints[playerId] ?? 0
    }

    var hasData: Bool {
        !seasonStarterPoints.isEmpty
    }

    func reset() {
        seasonStarterPoints = [:]
        fetched = []
        error = nil
    }

    private func cacheKey(leagueId: String, week: Int) -> String {
        "\(leagueId)#\(week)"
    }
}
