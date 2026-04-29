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
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { user -> (String, SleeperUser)? in
            guard let id = user.userId else { return nil }
            return (id, user)
        })

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
                wins: roster.settings?.wins ?? 0,
                losses: roster.settings?.losses ?? 0,
                ties: roster.settings?.ties ?? 0,
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

    // MARK: - Build From Matchup History

    /// Reconstruct a season's standings from `MatchupHistoryRecord`s
    /// alone — no live roster data needed. Used by Payouts when the
    /// user picks a past season's chip; that league's roster snapshot
    /// is no longer in `LeagueStore.myLeagueRosters` (those track the
    /// currently-anchored league only).
    ///
    /// Wins / losses / ties / PF aggregate over **regular-season**
    /// records only (`isPlayoff == false`). Tiebreak: wins desc, then
    /// PF desc — same as the live builder.
    static func buildStandingsFromHistory(
        records: [MatchupHistoryRecord]
    ) -> [StandingsTeam] {
        // First pass — aggregate per-roster regular-season stats and
        // capture the most recent display fields we see for that team.
        struct Aggregate {
            var rosterId: Int
            var userId: String
            var username: String
            var teamName: String
            var wins: Int = 0
            var losses: Int = 0
            var ties: Int = 0
            var fpts: Double = 0
            var fptsAgainst: Double = 0
        }
        var byRoster: [Int: Aggregate] = [:]

        func upsert(rosterId: Int, userId: String, username: String, teamName: String) {
            if byRoster[rosterId] == nil {
                byRoster[rosterId] = Aggregate(
                    rosterId: rosterId,
                    userId: userId,
                    username: username,
                    teamName: teamName.isEmpty ? "\(username)'s Team" : teamName
                )
            }
        }

        for record in records {
            upsert(
                rosterId: record.teamARosterId,
                userId: record.teamAUserId,
                username: record.teamAUsername,
                teamName: record.teamATeamName
            )
            upsert(
                rosterId: record.teamBRosterId,
                userId: record.teamBUserId,
                username: record.teamBUsername,
                teamName: record.teamBTeamName
            )

            // Only regular-season weeks count toward standings.
            guard !record.isPlayoff else { continue }
            // Skip empty/preseason placeholder weeks.
            guard record.teamAPoints > 0 || record.teamBPoints > 0 else { continue }

            byRoster[record.teamARosterId]?.fpts += record.teamAPoints
            byRoster[record.teamARosterId]?.fptsAgainst += record.teamBPoints
            byRoster[record.teamBRosterId]?.fpts += record.teamBPoints
            byRoster[record.teamBRosterId]?.fptsAgainst += record.teamAPoints

            if let winner = record.winnerRosterId {
                if winner == record.teamARosterId {
                    byRoster[record.teamARosterId]?.wins += 1
                    byRoster[record.teamBRosterId]?.losses += 1
                } else if winner == record.teamBRosterId {
                    byRoster[record.teamBRosterId]?.wins += 1
                    byRoster[record.teamARosterId]?.losses += 1
                }
            } else {
                byRoster[record.teamARosterId]?.ties += 1
                byRoster[record.teamBRosterId]?.ties += 1
            }
        }

        var teams: [StandingsTeam] = byRoster.values.map { agg in
            StandingsTeam(
                rosterId: agg.rosterId,
                userId: agg.userId,
                username: agg.username,
                displayName: agg.username,
                teamName: agg.teamName,
                avatarId: nil,
                division: 0,
                divisionName: "",
                divisionAvatar: nil,
                wins: agg.wins,
                losses: agg.losses,
                ties: agg.ties,
                fpts: agg.fpts,
                fptsAgainst: agg.fptsAgainst,
                streak: .none,
                leagueRank: 0,
                divisionRank: 0
            )
        }

        teams.sort { a, b in
            if a.wins != b.wins { return a.wins > b.wins }
            return a.fpts > b.fpts
        }

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
