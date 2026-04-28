import Foundation

@Observable
@MainActor
final class WorldCupStore {

    // MARK: - State

    private(set) var divisions: [WorldCupDivision] = []
    private(set) var seasons: [String] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    var hasData: Bool { !divisions.isEmpty }

    // MARK: - Load World Cup Standings

    /// Computes World Cup standings from the league chain and matchup history.
    /// Ports `getWorldCupStandings` from Angular's LeagueHistoryService line-by-line.
    ///
    /// Algorithm:
    /// 1. Get division names from the current (most recent) league metadata
    /// 2. Filter to regular-season, intra-divisional matchups with scores
    /// 3. Build per-user records keyed by user_id (stable across seasons)
    /// 4. Group by division, sort by wins DESC then points-for DESC
    /// 5. Mark top 2 per division as qualified
    func loadStandings(chain: [League], matchups: [MatchupHistoryRecord]) {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            divisions = try computeStandings(chain: chain, matchups: matchups)

            // Gather unique seasons sorted ascending
            seasons = Array(Set(matchups.map(\.season)))
                .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Reset

    func reset() {
        divisions = []
        seasons = []
        error = nil
    }

    // MARK: - Private: Compute Standings

    /// Pure computation -- ports `getWorldCupStandings` from Angular exactly.
    private func computeStandings(
        chain: [League],
        matchups: [MatchupHistoryRecord]
    ) throws -> [WorldCupDivision] {

        // Step 1: Get division names from the most recent league in the chain
        let currentLeague = chain.first
        let divisionNameMap: [Int: String] = currentLeague?.divisions ?? [:]

        // Step 2: Filter -- regular season only, intra-divisional matchups with scores
        let divisionalMatchups = matchups.filter { m in
            !m.isPlayoff
            && m.teamADivision > 0
            && m.teamBDivision > 0
            && m.teamADivision == m.teamBDivision
            && (m.teamAPoints > 0 || m.teamBPoints > 0)
        }

        // Step 3: Build per-user records keyed by user_id
        var userRecords: [String: UserRecord] = [:]

        for m in divisionalMatchups {
            // Ensure user A
            var recA = userRecords[m.teamAUserId] ?? UserRecord(
                userId: m.teamAUserId,
                username: m.teamAUsername,
                teamName: m.teamATeamName,
                division: m.teamADivision
            )
            // Update team name to latest
            if !m.teamATeamName.isEmpty { recA.teamName = m.teamATeamName }
            if m.teamADivision > 0 { recA.division = m.teamADivision }

            // Ensure user B
            var recB = userRecords[m.teamBUserId] ?? UserRecord(
                userId: m.teamBUserId,
                username: m.teamBUsername,
                teamName: m.teamBTeamName,
                division: m.teamBDivision
            )
            if !m.teamBTeamName.isEmpty { recB.teamName = m.teamBTeamName }
            if m.teamBDivision > 0 { recB.division = m.teamBDivision }

            // Ensure season data
            var seasonA = recA.seasonData[m.season] ?? SeasonData()
            var seasonB = recB.seasonData[m.season] ?? SeasonData()

            // Accumulate points
            recA.pointsFor += m.teamAPoints
            recA.pointsAgainst += m.teamBPoints
            seasonA.pointsFor += m.teamAPoints
            seasonA.pointsAgainst += m.teamBPoints

            recB.pointsFor += m.teamBPoints
            recB.pointsAgainst += m.teamAPoints
            seasonB.pointsFor += m.teamBPoints
            seasonB.pointsAgainst += m.teamAPoints

            // Determine winner
            if m.winnerRosterId == nil {
                // Tie
                recA.ties += 1
                recB.ties += 1
            } else if m.teamAPoints > m.teamBPoints {
                recA.wins += 1
                recB.losses += 1
                seasonA.wins += 1
                seasonB.losses += 1
            } else {
                recB.wins += 1
                recA.losses += 1
                seasonB.wins += 1
                seasonA.losses += 1
            }

            recA.seasonData[m.season] = seasonA
            recB.seasonData[m.season] = seasonB
            userRecords[m.teamAUserId] = recA
            userRecords[m.teamBUserId] = recB
        }

        // Step 4: Group by division
        var divisionGroups: [Int: [WorldCupTeamRecord]] = [:]

        for rec in userRecords.values {
            let seasonBreakdown = rec.seasonData
                .map { (season, data) in
                    SeasonBreakdown(
                        season: season,
                        wins: data.wins,
                        losses: data.losses,
                        pointsFor: data.pointsFor,
                        pointsAgainst: data.pointsAgainst
                    )
                }
                .sorted { (Int($0.season) ?? 0) < (Int($1.season) ?? 0) }

            let teamRecord = WorldCupTeamRecord(
                userId: rec.userId,
                username: rec.username,
                teamName: rec.teamName,
                division: rec.division,
                divisionName: divisionNameMap[rec.division] ?? "Division \(rec.division)",
                wins: rec.wins,
                losses: rec.losses,
                ties: rec.ties,
                pointsFor: rec.pointsFor,
                pointsAgainst: rec.pointsAgainst,
                clinchStatus: .alive,
                seasonBreakdown: seasonBreakdown
            )

            divisionGroups[rec.division, default: []].append(teamRecord)
        }

        // Step 5: Sort within each division -- wins DESC, then points for DESC as tiebreaker
        var result: [WorldCupDivision] = []

        for (divNum, var teams) in divisionGroups {
            teams.sort { a, b in
                if b.wins != a.wins { return b.wins < a.wins }
                return b.pointsFor < a.pointsFor
            }

            // Compute clinch status for each team in this division
            let statuses = ClinchCalculator.calculate(teams: teams)
            for i in teams.indices {
                teams[i].clinchStatus = statuses[teams[i].userId] ?? .alive
            }

            result.append(WorldCupDivision(
                divisionNumber: divNum,
                divisionName: divisionNameMap[divNum] ?? "Division \(divNum)",
                teams: teams
            ))
        }

        // Sort divisions by number
        result.sort { $0.divisionNumber < $1.divisionNumber }

        return result
    }
}

// MARK: - Private Supporting Types

private extension WorldCupStore {

    struct UserRecord {
        let userId: String
        var username: String
        var teamName: String
        var division: Int
        var wins: Int = 0
        var losses: Int = 0
        var ties: Int = 0
        var pointsFor: Double = 0
        var pointsAgainst: Double = 0
        var seasonData: [String: SeasonData] = [:]
    }

    struct SeasonData {
        var wins: Int = 0
        var losses: Int = 0
        var pointsFor: Double = 0
        var pointsAgainst: Double = 0
    }
}
