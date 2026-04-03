import Foundation

/// Pure computation -- no API calls. Builds standings from rosters, users, and league metadata.
enum StandingsBuilder {

    // MARK: - Build League Standings

    /// Combines roster data with user info, calculates win%, assigns ranks, sorts by wins then fpts.
    static func buildStandings(
        rosters: [Roster],
        users: [SleeperUser],
        league: League
    ) -> [StandingsTeam] {
        let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.userId, $0) })

        var teams = rosters.compactMap { roster -> StandingsTeam? in
            guard let ownerId = roster.ownerId else { return nil }
            let user = userMap[ownerId]

            let streak = parseStreak(from: roster.metadata)
            let divisionInfo = resolveDivision(
                rosterDivision: roster.division,
                leagueMetadata: league.metadata
            )

            return StandingsTeam(
                rosterId: roster.rosterId,
                userId: ownerId,
                username: user?.username ?? "Unknown",
                displayName: user?.resolvedDisplayName ?? "Unknown",
                teamName: user?.teamName ?? "\(user?.resolvedDisplayName ?? "Unknown")'s Team",
                avatarId: user?.avatar,
                division: roster.division,
                divisionName: divisionInfo.name,
                divisionAvatar: divisionInfo.avatarId,
                wins: roster.settings.wins,
                losses: roster.settings.losses,
                ties: roster.settings.ties,
                fpts: roster.pointsFor,
                fptsAgainst: roster.pointsAgainst,
                streak: streak,
                leagueRank: 0,
                divisionRank: 0
            )
        }

        // Sort: most wins first, tiebreak by most points for
        teams.sort { a, b in
            if a.wins != b.wins { return a.wins > b.wins }
            return a.fpts > b.fpts
        }

        // Assign league ranks
        for i in teams.indices {
            teams[i].leagueRank = i + 1
        }

        return teams
    }

    // MARK: - Build Division Standings

    /// Groups teams by division and assigns per-division ranks.
    static func buildDivisionStandings(
        from standings: [StandingsTeam]
    ) -> [String: [StandingsTeam]] {
        var grouped: [String: [StandingsTeam]] = [:]

        for team in standings {
            let key = team.hasDivision ? team.divisionName : "Unknown Division"
            grouped[key, default: []].append(team)
        }

        // Sort within each division and assign division ranks
        for key in grouped.keys {
            grouped[key]?.sort { a, b in
                if a.wins != b.wins { return a.wins > b.wins }
                return a.fpts > b.fpts
            }
            for i in (grouped[key] ?? []).indices {
                grouped[key]?[i].divisionRank = i + 1
            }
        }

        return grouped
    }

    // MARK: - Helpers

    /// Parses streak metadata string like "5W" or "2L" into a Streak value.
    private static func parseStreak(from metadata: [String: AnyCodableValue]?) -> Streak {
        guard let streakStr = metadata?["streak"]?.stringValue else {
            return .none
        }

        // Sleeper sends streaks like "5W" or "2L"
        let pattern = /(\d+)([WL])/
        guard let match = streakStr.firstMatch(of: pattern) else {
            return .none
        }

        let total = Int(match.1) ?? 0
        let type: Streak.StreakType = match.2 == "W" ? .win : .loss
        return Streak(type: type, total: total)
    }

    /// Resolves division name and avatar from league metadata.
    private static func resolveDivision(
        rosterDivision: Int,
        leagueMetadata: [String: AnyCodableValue]?
    ) -> (name: String, avatarId: String?) {
        guard rosterDivision > 0, let metadata = leagueMetadata else {
            return ("Unknown Division", nil)
        }

        let key = "division_\(rosterDivision)"
        let name = metadata[key]?.stringValue ?? "Unknown Division"
        let avatarId = metadata["\(key)_avatar"]?.stringValue
        return (name, avatarId)
    }
}
