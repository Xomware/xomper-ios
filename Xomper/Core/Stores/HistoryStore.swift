import Foundation

@Observable
@MainActor
final class HistoryStore {

    // MARK: - Matchup History State

    private(set) var matchupHistory: [MatchupHistoryRecord] = []
    private(set) var isLoadingMatchups = false
    private(set) var matchupError: Error?

    // MARK: - Draft History State

    private(set) var draftHistory: [DraftHistoryRecord] = []
    private(set) var isLoadingDrafts = false
    private(set) var draftError: Error?

    // MARK: - Upcoming Draft State

    /// Snapshot of the next-season draft (status = `pre_draft` /
    /// `drafting`). Loaded on demand by `loadUpcomingDraft` when the
    /// user picks the upcoming-season chip in Draft History. Anchored
    /// by leagueId so re-renders are cheap and don't re-fetch.
    private(set) var upcomingDraft: Draft?
    private(set) var upcomingLeague: League?
    private(set) var upcomingRosters: [Roster] = []
    private(set) var upcomingUsers: [SleeperUser] = []
    private(set) var isLoadingUpcoming = false
    private(set) var upcomingError: Error?

    // MARK: - Derived

    var availableMatchupSeasons: [String] {
        Array(Set(matchupHistory.map(\.season)))
            .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
    }

    var availableDraftSeasons: [String] {
        Array(Set(draftHistory.map(\.season)))
            .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
    }

    var hasMatchups: Bool {
        !matchupHistory.isEmpty
    }

    var hasDrafts: Bool {
        !draftHistory.isEmpty
    }

    // MARK: - Private

    private let apiClient: SleeperAPIClientProtocol
    private var matchupCache: [String: [MatchupHistoryRecord]]?
    private var draftCache: [String: [DraftHistoryRecord]]?

    init(apiClient: SleeperAPIClientProtocol = SleeperAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Load Matchup History from Chain

    /// Ports `getMatchupHistoryFromChain` from Angular's LeagueHistoryService.
    /// For each league in the chain (skipping pre_draft), loads context (users + rosters),
    /// then fetches all 17 weeks of matchups in parallel, pairs them, and resolves usernames.
    func loadMatchupHistory(chain: [League]) async {
        guard !isLoadingMatchups else { return }

        // Check cache
        if let cacheKey = chain.first?.leagueId, let cached = matchupCache?[cacheKey] {
            matchupHistory = cached
            return
        }

        isLoadingMatchups = true
        matchupError = nil

        do {
            let leaguesWithMatchups = chain.filter { $0.status != "pre_draft" }
            guard !leaguesWithMatchups.isEmpty else {
                matchupHistory = []
                isLoadingMatchups = false
                return
            }

            var allRecords: [MatchupHistoryRecord] = []

            // Process each league in the chain
            for league in leaguesWithMatchups {
                let leagueRecords = try await fetchSeasonMatchups(for: league)
                allRecords.append(contentsOf: leagueRecords)
            }

            // Sort: newest season first, then week ascending
            allRecords.sort { a, b in
                let seasonA = Int(a.season) ?? 0
                let seasonB = Int(b.season) ?? 0
                if seasonA != seasonB { return seasonA > seasonB }
                return a.week < b.week
            }

            matchupHistory = allRecords

            // Cache
            if let cacheKey = chain.first?.leagueId {
                if matchupCache == nil { matchupCache = [:] }
                matchupCache?[cacheKey] = allRecords
            }
        } catch {
            matchupError = error
        }

        isLoadingMatchups = false
    }

    // MARK: - Season Filtering

    func matchups(forSeason season: String) -> [MatchupHistoryRecord] {
        matchupHistory.filter { $0.season == season }
    }

    func weeklyMatchups(forSeason season: String) -> [WeekMatchups] {
        let seasonMatchups = matchups(forSeason: season)
        var weekMap: [Int: [MatchupHistoryRecord]] = [:]

        for matchup in seasonMatchups {
            weekMap[matchup.week, default: []].append(matchup)
        }

        return weekMap.map { WeekMatchups(week: $0.key, matchups: $0.value) }
            .sorted { $0.week > $1.week }
    }

    /// Returns the most recent week that has actual scores, or nil.
    func latestScoredWeek(forSeason season: String) -> Int? {
        let weekly = weeklyMatchups(forSeason: season)
        return weekly.first { weekData in
            weekData.matchups.contains { $0.teamAPoints > 0 || $0.teamBPoints > 0 }
        }?.week
    }

    // MARK: - Head-to-Head

    func headToHead(userId1: String, userId2: String) -> HeadToHeadRecord {
        let h2hMatchups = matchupHistory.filter { m in
            (m.teamAUserId == userId1 && m.teamBUserId == userId2) ||
            (m.teamAUserId == userId2 && m.teamBUserId == userId1)
        }

        var user1Wins = 0
        var user2Wins = 0
        var ties = 0

        for m in h2hMatchups {
            let user1RosterId = m.teamAUserId == userId1 ? m.teamARosterId : m.teamBRosterId
            let user2RosterId = m.teamAUserId == userId2 ? m.teamARosterId : m.teamBRosterId

            if m.winnerRosterId == user1RosterId {
                user1Wins += 1
            } else if m.winnerRosterId == user2RosterId {
                user2Wins += 1
            } else {
                ties += 1
            }
        }

        return HeadToHeadRecord(
            user1Wins: user1Wins,
            user2Wins: user2Wins,
            ties: ties,
            matchups: h2hMatchups
        )
    }

    // MARK: - Championships (Trophy Case)

    /// Returns every championship the given user has won across the loaded
    /// matchup history. Pure derived computation — no network, no side effects.
    ///
    /// Selection rule: a record is a championship win if `isChampionship == true`
    /// AND the user is on the winning side AND the championship game is the
    /// final week of that season's playoffs (filtering out non-final week-16/17
    /// games that are flagged `isChampionship: true` due to the loose flag
    /// semantics in `convertMatchupResults`). We dedupe by `season`.
    ///
    /// `leagueNamesById` maps `leagueId → human-readable name` for display.
    /// If the map doesn't have an entry, falls back to the `season` string.
    ///
    /// Sorted descending by season (newest first).
    func championships(
        forUserId userId: String,
        leagueNamesById: [String: String] = [:]
    ) -> [Championship] {
        guard !userId.isEmpty else { return [] }

        // Determine the actual title-game week per (leagueId, season): the max
        // championship-flagged week. The current ingest tags both week 16 and
        // week 17 as `isChampionship`, but only the later week is the title
        // game in a 2-week playoff format.
        var titleWeekByKey: [String: Int] = [:]
        for record in matchupHistory where record.isChampionship {
            let key = "\(record.leagueId)-\(record.season)"
            titleWeekByKey[key] = max(titleWeekByKey[key] ?? 0, record.week)
        }

        // Filter to championship-flagged records this user won, and only the
        // actual title-game week per league/season.
        let wins = matchupHistory.filter { record in
            guard record.isChampionship else { return false }
            let key = "\(record.leagueId)-\(record.season)"
            guard record.week == titleWeekByKey[key] else { return false }

            if record.teamAUserId == userId,
               record.winnerRosterId == record.teamARosterId {
                return true
            }
            if record.teamBUserId == userId,
               record.winnerRosterId == record.teamBRosterId {
                return true
            }
            return false
        }

        // Map to Championship, picking the user's side as "team" and
        // the opponent's side as "opponent".
        let mapped: [Championship] = wins.map { record in
            let userIsTeamA = record.teamAUserId == userId
            let teamName = userIsTeamA ? record.teamATeamName : record.teamBTeamName
            let opponent = userIsTeamA ? record.teamBTeamName : record.teamATeamName
            let pointsFor = userIsTeamA ? record.teamAPoints : record.teamBPoints
            let pointsAgainst = userIsTeamA ? record.teamBPoints : record.teamAPoints
            let leagueName = leagueNamesById[record.leagueId] ?? ""

            return Championship(
                season: record.season,
                leagueId: record.leagueId,
                leagueName: leagueName,
                week: record.week,
                teamName: teamName,
                pointsFor: pointsFor,
                pointsAgainst: pointsAgainst,
                opponentTeamName: opponent
            )
        }

        // Dedupe by (leagueId, season) — a user can hold multiple titles
        // across different leagues in the same year. Prefer later week.
        var byKey: [String: Championship] = [:]
        for champ in mapped {
            let key = "\(champ.leagueId)-\(champ.season)"
            if let existing = byKey[key] {
                if champ.week > existing.week {
                    byKey[key] = champ
                }
            } else {
                byKey[key] = champ
            }
        }

        // Sort: descending by season, then by leagueId for stable order.
        return byKey.values.sorted { a, b in
            if a.season != b.season {
                return (Int(a.season) ?? 0) > (Int(b.season) ?? 0)
            }
            return a.leagueId < b.leagueId
        }
    }

    // MARK: - Career Stats (Profile)

    /// Aggregates all-time stats for the given user from `matchupHistory`.
    /// Pure derived computation — no network, no side effects. Returns
    /// `.empty` if the user has no recorded games.
    func careerStats(forUserId userId: String) -> CareerStats {
        guard !userId.isEmpty else { return .empty }

        var wins = 0
        var losses = 0
        var ties = 0
        var pointsFor: Double = 0
        var pointsAgainst: Double = 0
        var highest: Double = -.infinity
        var highestRef: CareerStats.WeekRef?
        var lowest: Double = .infinity
        var lowestRef: CareerStats.WeekRef?
        var seasons = Set<String>()
        var playoffSeasons = Set<String>()

        for record in matchupHistory {
            let userIsTeamA = record.teamAUserId == userId
            let userIsTeamB = record.teamBUserId == userId
            guard userIsTeamA || userIsTeamB else { continue }

            let userPoints = userIsTeamA ? record.teamAPoints : record.teamBPoints
            let oppPoints = userIsTeamA ? record.teamBPoints : record.teamAPoints
            let userRosterId = userIsTeamA ? record.teamARosterId : record.teamBRosterId

            // Skip records that haven't been played yet (both 0 — preseason
            // schedule placeholders) — they'd otherwise pollute lowest-score.
            if userPoints == 0 && oppPoints == 0 { continue }

            pointsFor += userPoints
            pointsAgainst += oppPoints
            seasons.insert(record.season)

            if record.isPlayoff {
                playoffSeasons.insert(record.season)
            }

            if userPoints > highest {
                highest = userPoints
                highestRef = .init(season: record.season, week: record.week)
            }
            if userPoints < lowest {
                lowest = userPoints
                lowestRef = .init(season: record.season, week: record.week)
            }

            if let winner = record.winnerRosterId {
                if winner == userRosterId {
                    wins += 1
                } else {
                    losses += 1
                }
            } else {
                ties += 1
            }
        }

        // Normalize sentinels for users with zero games.
        if highest == -.infinity { highest = 0 }
        if lowest == .infinity { lowest = 0 }

        return CareerStats(
            wins: wins,
            losses: losses,
            ties: ties,
            pointsFor: pointsFor,
            pointsAgainst: pointsAgainst,
            highestScore: highest,
            highestScoreWeek: highestRef,
            lowestScore: lowest,
            lowestScoreWeek: lowestRef,
            seasonsPlayed: seasons.count,
            playoffAppearances: playoffSeasons.count
        )
    }

    // MARK: - Fetch Raw Matchups for Detail

    /// Fetches the raw matchup data for a specific week to get player-level lineups and points.
    func fetchRawMatchups(leagueId: String, week: Int) async throws -> [MatchupPair] {
        let rawMatchups = try await apiClient.fetchLeagueMatchups(leagueId, week: week)
        return pairMatchups(rawMatchups)
    }

    // MARK: - Load Draft History from Chain

    /// Ports `getDraftHistoryFromChain` from Angular's LeagueHistoryService.
    /// For each league in the chain, fetches drafts, then picks for each draft,
    /// resolves player names from pick metadata, resolves "picked by" from rosters/users.
    func loadDraftHistory(chain: [League]) async {
        guard !isLoadingDrafts else { return }

        // Check cache
        if let cacheKey = chain.first?.leagueId, let cached = draftCache?[cacheKey] {
            draftHistory = cached
            return
        }

        isLoadingDrafts = true
        draftError = nil

        do {
            guard !chain.isEmpty else {
                draftHistory = []
                isLoadingDrafts = false
                return
            }

            var allRecords: [DraftHistoryRecord] = []

            // Process each league in the chain concurrently
            try await withThrowingTaskGroup(of: [DraftHistoryRecord].self) { group in
                for league in chain {
                    group.addTask { [apiClient] in
                        try await Self.fetchDraftRecords(
                            for: league,
                            apiClient: apiClient
                        )
                    }
                }

                for try await records in group {
                    allRecords.append(contentsOf: records)
                }
            }

            // Sort: newest season first, then by pick_no ascending
            allRecords.sort { a, b in
                let seasonA = Int(a.season) ?? 0
                let seasonB = Int(b.season) ?? 0
                if seasonA != seasonB { return seasonA > seasonB }
                return a.pickNo < b.pickNo
            }

            draftHistory = allRecords

            // Cache
            if let cacheKey = chain.first?.leagueId {
                if draftCache == nil { draftCache = [:] }
                draftCache?[cacheKey] = allRecords
            }
        } catch {
            draftError = error
        }

        isLoadingDrafts = false
    }

    // MARK: - Draft Filtering

    func draftPicks(forSeason season: String) -> [DraftHistoryRecord] {
        draftHistory.filter { $0.season == season }
    }

    func draftPicksByRound(forSeason season: String) -> [DraftRound] {
        let seasonPicks = draftPicks(forSeason: season)
        var roundMap: [Int: [DraftHistoryRecord]] = [:]

        for pick in seasonPicks {
            roundMap[pick.round, default: []].append(pick)
        }

        return roundMap.map { DraftRound(round: $0.key, picks: $0.value.sorted { $0.pickNo < $1.pickNo }) }
            .sorted { $0.round < $1.round }
    }

    func userDraftPicks(forSeason season: String, userId: String) -> [DraftHistoryRecord] {
        draftPicks(forSeason: season).filter { $0.pickedByUserId == userId }
    }

    // MARK: - Load Upcoming Draft

    /// Loads the upcoming-season draft for a league with the given
    /// `homeLeagueName` (e.g. "CLT DYNASTY") in the user's account.
    /// Sleeper exposes `/user/{user_id}/leagues/nfl/{season}` for that
    /// year's leagues, so we can find the next-season league forward
    /// from `myLeague` (which only walks `previous_league_id`
    /// backward). Once located, fetches its first draft + context
    /// (users + rosters) so the view can render the bracket-set draft
    /// order before any picks are made.
    ///
    /// No-op if a draft is already loaded for the same `season`.
    func loadUpcomingDraft(
        season: String,
        homeLeagueName: String,
        userId: String
    ) async {
        guard !isLoadingUpcoming else { return }
        // Cache: same-season already loaded? Skip the network round trip.
        if upcomingDraft != nil, upcomingLeague?.season == season { return }

        isLoadingUpcoming = true
        upcomingError = nil
        defer { isLoadingUpcoming = false }

        do {
            let leagues = try await apiClient.fetchUserLeagues(userId, season: season)
            // Match by name first (handles renames in either direction);
            // fall back to the only league of that season if just one
            // exists in the user's account.
            let target = leagues.first(where: {
                $0.name?.caseInsensitiveCompare(homeLeagueName) == .orderedSame
            }) ?? (leagues.count == 1 ? leagues.first : nil)

            guard let league = target else {
                // No upcoming league created yet — leave state empty
                // so the view can fall through to a "draft not yet
                // scheduled" empty state.
                upcomingDraft = nil
                upcomingLeague = nil
                upcomingRosters = []
                upcomingUsers = []
                return
            }

            async let draftsTask = apiClient.fetchDrafts(league.leagueId)
            async let usersTask = apiClient.fetchLeagueUsers(league.leagueId)
            async let rostersTask = apiClient.fetchLeagueRosters(league.leagueId)

            let drafts = try await draftsTask
            let users = try await usersTask
            let rosters = try await rostersTask

            // Most leagues have one draft per season; if there are
            // multiple, prefer drafting > pre_draft > complete to
            // surface the most actionable one.
            let priority: [String?: Int] = ["drafting": 0, "pre_draft": 1, "complete": 2]
            let sortedDrafts = drafts.sorted {
                (priority[$0.status] ?? 99) < (priority[$1.status] ?? 99)
            }

            upcomingLeague = league
            upcomingUsers = users
            upcomingRosters = rosters
            upcomingDraft = sortedDrafts.first
        } catch {
            upcomingError = error
        }
    }

    // MARK: - Reset

    func reset() {
        matchupHistory = []
        matchupCache = nil
        matchupError = nil
        draftHistory = []
        draftCache = nil
        draftError = nil
        upcomingDraft = nil
        upcomingLeague = nil
        upcomingRosters = []
        upcomingUsers = []
        upcomingError = nil
    }

    // MARK: - Private: Fetch Draft Records for a Single League

    /// Fetches drafts, picks, users, and rosters for a single league and builds DraftHistoryRecords.
    /// Nonisolated static so it can run inside a TaskGroup across the Sendable boundary.
    private nonisolated static func fetchDraftRecords(
        for league: League,
        apiClient: SleeperAPIClientProtocol
    ) async throws -> [DraftHistoryRecord] {
        // Load drafts, users, and rosters in parallel
        async let draftsTask = apiClient.fetchDrafts(league.leagueId)
        async let usersTask = apiClient.fetchLeagueUsers(league.leagueId)
        async let rostersTask = apiClient.fetchLeagueRosters(league.leagueId)

        let drafts = try await draftsTask
        let users = try await usersTask
        let rosters = try await rostersTask

        var records: [DraftHistoryRecord] = []

        // For each draft, fetch picks then build records
        for draft in drafts {
            let picks: [DraftPick]
            do {
                picks = try await apiClient.fetchDraftPicks(draft.draftId)
            } catch {
                continue
            }

            for pick in picks {
                // Resolve user from roster data
                let roster = rosters.first { $0.rosterId == pick.rosterId }
                let user = users.first { $0.userId == (pick.pickedBy ?? roster?.ownerId) }

                let playerName = [
                    pick.metadata?.firstName ?? "",
                    pick.metadata?.lastName ?? ""
                ]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

                let record = DraftHistoryRecord(
                    leagueId: draft.leagueId,
                    draftId: draft.draftId,
                    season: draft.season,
                    round: pick.round,
                    pickNo: pick.pickNo,
                    draftSlot: pick.draftSlot,
                    playerId: pick.playerId,
                    playerName: playerName,
                    playerPosition: pick.metadata?.position ?? "",
                    playerTeam: pick.metadata?.team ?? "",
                    pickedByUserId: pick.pickedBy ?? roster?.ownerId ?? "",
                    pickedByRosterId: pick.rosterId ?? 0,
                    pickedByUsername: user?.username ?? "",
                    pickedByTeamName: user?.teamName ?? "",
                    isKeeper: pick.isKeeper ?? false
                )

                records.append(record)
            }
        }

        return records
    }

    // MARK: - Private: Fetch Season Matchups

    /// Fetches context + all 17 weeks of matchups for a single league, then converts to records.
    private func fetchSeasonMatchups(for league: League) async throws -> [MatchupHistoryRecord] {
        // Load users + rosters in parallel
        async let usersTask = apiClient.fetchLeagueUsers(league.leagueId)
        async let rostersTask = apiClient.fetchLeagueRosters(league.leagueId)
        // Brackets — best-effort. Pre-playoff seasons return empty arrays;
        // missing brackets just mean no placement labels for that season.
        async let winnersTask: [PlayoffBracketMatch] = {
            (try? await apiClient.fetchWinnersBracket(league.leagueId)) ?? []
        }()
        async let losersTask: [PlayoffBracketMatch] = {
            (try? await apiClient.fetchLosersBracket(league.leagueId)) ?? []
        }()

        let users = try await usersTask
        let rosters = try await rostersTask
        let winners = await winnersTask
        let losers = await losersTask

        let totalWeeks = 17

        // Fetch all weeks in parallel using TaskGroup
        let weekResults: [(week: Int, pairs: [MatchupPair])] = try await withThrowingTaskGroup(
            of: (Int, [MatchupPair]).self
        ) { group in
            for week in 1...totalWeeks {
                group.addTask { [apiClient] in
                    do {
                        let matchups = try await apiClient.fetchLeagueMatchups(league.leagueId, week: week)
                        let pairs = Self.pairMatchupsStatic(matchups)
                        return (week, pairs)
                    } catch {
                        return (week, [])
                    }
                }
            }

            var results: [(Int, [MatchupPair])] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        let placementMap = Self.buildPlacementMap(
            winners: winners,
            losers: losers,
            playoffWeekStart: Self.playoffWeekStart(for: league)
        )

        return convertMatchupResults(
            leagueId: league.leagueId,
            season: league.season,
            weekResults: weekResults,
            users: users,
            rosters: rosters,
            placementMap: placementMap
        )
    }

    /// `(week, sorted roster pair)` → placement, derived from a
    /// league's bracket. Sorted to make the lookup direction-agnostic.
    /// Only matches with a non-nil `placement` and both roster IDs
    /// resolved are included — early-round games stay unlabeled.
    private nonisolated static func buildPlacementMap(
        winners: [PlayoffBracketMatch],
        losers: [PlayoffBracketMatch],
        playoffWeekStart: Int?
    ) -> [String: Int] {
        guard let start = playoffWeekStart else { return [:] }
        var map: [String: Int] = [:]
        for match in winners + losers {
            guard let placement = match.placement,
                  let r1 = match.team1RosterId,
                  let r2 = match.team2RosterId else { continue }
            // Round 1 → playoff_week_start, round 2 → +1, etc.
            // (`playoff_round_type=1` two-week rounds aren't modeled —
            // placement still resolves on the second/final week.)
            let week = start + match.round - 1
            let key = bracketKeyStatic(week: week, rosters: [r1, r2])
            map[key] = placement
        }
        return map
    }

    private nonisolated static func bracketKeyStatic(week: Int, rosters: [Int]) -> String {
        let sorted = rosters.sorted()
        return "\(week)-\(sorted.map(String.init).joined(separator: "-"))"
    }

    private nonisolated static func playoffWeekStart(for league: League) -> Int? {
        guard let value = league.settings?.additionalSettings?["playoff_week_start"] else { return nil }
        if let i = value.intValue { return i }
        if let d = value.doubleValue { return Int(d) }
        return nil
    }

    // MARK: - Private: Pair Matchups

    /// Groups raw matchup array by matchup_id into pairs.
    private func pairMatchups(_ matchups: [Matchup]) -> [MatchupPair] {
        Self.pairMatchupsStatic(matchups)
    }

    /// Static version for use inside TaskGroup (Sendable boundary).
    private nonisolated static func pairMatchupsStatic(_ matchups: [Matchup]) -> [MatchupPair] {
        var grouped: [Int: [Matchup]] = [:]
        for matchup in matchups {
            guard let mid = matchup.matchupId else { continue }
            grouped[mid, default: []].append(matchup)
        }

        return grouped.values.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return MatchupPair(teamA: pair[0], teamB: pair[1])
        }
    }

    // MARK: - Private: Convert Matchup Results

    /// Ports `convertMatchupResults` from Angular -- resolves usernames from rosters/users,
    /// determines winner, and builds MatchupHistoryRecord array.
    private func convertMatchupResults(
        leagueId: String,
        season: String,
        weekResults: [(week: Int, pairs: [MatchupPair])],
        users: [SleeperUser],
        rosters: [Roster],
        placementMap: [String: Int] = [:]
    ) -> [MatchupHistoryRecord] {
        var records: [MatchupHistoryRecord] = []

        for (week, pairs) in weekResults {
            for pair in pairs {
                let rosterA = rosters.first { $0.rosterId == pair.teamA.rosterId }
                let rosterB = rosters.first { $0.rosterId == pair.teamB.rosterId }
                let userA = users.first { $0.userId == rosterA?.ownerId }
                let userB = users.first { $0.userId == rosterB?.ownerId }

                let pointsA = pair.teamA.resolvedPoints
                let pointsB = pair.teamB.resolvedPoints

                let winnerId: Int?
                if pointsA > pointsB {
                    winnerId = pair.teamA.rosterId
                } else if pointsB > pointsA {
                    winnerId = pair.teamB.rosterId
                } else {
                    winnerId = nil
                }

                let placementKey = Self.bracketKeyStatic(
                    week: week,
                    rosters: [pair.teamA.rosterId, pair.teamB.rosterId]
                )
                let placement = placementMap[placementKey]

                let record = MatchupHistoryRecord(
                    leagueId: leagueId,
                    season: season,
                    week: week,
                    matchupId: pair.teamA.matchupId ?? 0,
                    teamARosterId: pair.teamA.rosterId,
                    teamAUserId: userA?.userId ?? "",
                    teamAUsername: userA?.username ?? "",
                    teamATeamName: userA?.teamName ?? userA?.displayName ?? "",
                    teamAPoints: pointsA,
                    teamBRosterId: pair.teamB.rosterId,
                    teamBUserId: userB?.userId ?? "",
                    teamBUsername: userB?.username ?? "",
                    teamBTeamName: userB?.teamName ?? userB?.displayName ?? "",
                    teamBPoints: pointsB,
                    winnerRosterId: winnerId,
                    isPlayoff: week > 14,
                    // Authoritative championship flag: only the bracket
                    // game with placement == 1 is the title game. Falls
                    // back to the loose week-16/17 flag when the bracket
                    // wasn't loaded (legacy/empty-bracket leagues).
                    isChampionship: placement == 1 || (placementMap.isEmpty && (week == 16 || week == 17)),
                    teamADivision: rosterA?.division ?? 0,
                    teamBDivision: rosterB?.division ?? 0,
                    playoffPlacement: placement
                )

                records.append(record)
            }
        }

        return records
    }
}

// MARK: - Supporting Types

struct MatchupPair: Sendable {
    let teamA: Matchup
    let teamB: Matchup
}

struct WeekMatchups: Identifiable, Sendable {
    let week: Int
    let matchups: [MatchupHistoryRecord]

    var id: Int { week }

    var hasScores: Bool {
        matchups.contains { $0.teamAPoints > 0 || $0.teamBPoints > 0 }
    }
}

struct DraftRound: Identifiable, Sendable {
    let round: Int
    let picks: [DraftHistoryRecord]

    var id: Int { round }
}

struct HeadToHeadRecord: Sendable {
    let user1Wins: Int
    let user2Wins: Int
    let ties: Int
    let matchups: [MatchupHistoryRecord]

    var totalGames: Int { user1Wins + user2Wins + ties }

    var recordString: String {
        if ties > 0 {
            return "\(user1Wins)-\(user2Wins)-\(ties)"
        }
        return "\(user1Wins)-\(user2Wins)"
    }
}
