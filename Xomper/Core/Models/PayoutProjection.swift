import Foundation

/// Per-category projection: who's currently leading, how the signed-in
/// user stands, and the dollar amount on the line. Built fresh on
/// each PayoutsView render via `PayoutCalculator`.
struct PayoutProjection: Sendable, Identifiable {
    let category: LeaguePayoutCategory
    let leader: LeaderRef?
    let userPlacement: UserPlacement
    /// Dollar amount the signed-in user is currently projected to win
    /// in this category. Zero if not leading (single-winner pots) or
    /// if the user has no qualifying weeks (weekly high).
    let projectedAmount: Double
    /// Optional ranked list — drives the drill-down screen later. Nil
    /// when the category data isn't available (e.g. position MVP
    /// before PlayerPointsStore lands).
    let standings: [StandingsRow]?
    /// User-visible reason this category is unresolved or unavailable.
    let unavailableReason: String?

    var id: String { category.id }

    struct LeaderRef: Sendable, Hashable {
        let userId: String
        let teamName: String
        let displayValue: String
    }

    struct StandingsRow: Sendable, Identifiable, Hashable {
        let userId: String
        let teamName: String
        let value: Double
        let displayValue: String
        var id: String { userId }
    }

    enum UserPlacement: Sendable, Hashable {
        case leading
        case tied(otherCount: Int)
        case behind(by: String)
        case won(amount: Double)  // category settled
        case notApplicable
        case pending
    }
}

@MainActor
enum PayoutCalculator {

    /// Builds projections for every configured category. Pure
    /// derivation from the existing stores — no network. Categories
    /// the data doesn't support (position MVPs without per-player
    /// scoring) come back with `unavailableReason` set.
    static func project(
        payouts: LeaguePayouts,
        standings: [StandingsTeam],
        matchupHistory: [MatchupHistoryRecord],
        winnersBracket: [PlayoffBracketMatch]?,
        rosters: [Roster],
        playerStore: PlayerStore,
        playerPointsStore: PlayerPointsStore,
        userId: String?
    ) -> [PayoutProjection] {
        payouts.categories.map { category in
            switch category.kind {
            case .champion:
                bracketPlacement(category: category, placement: 1, winnersBracket: winnersBracket, standings: standings, userId: userId)
            case .runnerUp:
                bracketPlacement(category: category, placement: 2, winnersBracket: winnersBracket, standings: standings, userId: userId)
            case .thirdPlace:
                bracketPlacement(category: category, placement: 3, winnersBracket: winnersBracket, standings: standings, userId: userId)
            case .seasonHighPF:
                seasonHighPF(category: category, standings: standings, userId: userId)
            case .weeklyHighScore:
                weeklyHigh(category: category, matchupHistory: matchupHistory, standings: standings, userId: userId)
            case .positionMVP(let pos):
                positionMVP(
                    category: category,
                    position: pos,
                    rosters: rosters,
                    standings: standings,
                    playerStore: playerStore,
                    playerPointsStore: playerPointsStore,
                    userId: userId
                )
            }
        }
    }

    // MARK: - Position MVP

    /// "MVP" is the single PLAYER at the given position with the most
    /// season starter-points. Owner of that player at the time of
    /// computation wins the pot.
    ///
    /// Importantly, only points scored while STARTING count toward
    /// the total — the owner had to play them. PlayerPointsStore
    /// already enforces this by aggregating from `starters_points`
    /// only (bench points are ignored).
    private static func positionMVP(
        category: LeaguePayoutCategory,
        position: String,
        rosters: [Roster],
        standings: [StandingsTeam],
        playerStore: PlayerStore,
        playerPointsStore: PlayerPointsStore,
        userId: String?
    ) -> PayoutProjection {
        guard playerPointsStore.hasData else {
            return PayoutProjection(
                category: category,
                leader: nil,
                userPlacement: .pending,
                projectedAmount: 0,
                standings: nil,
                unavailableReason: "Per-player weekly scoring still loading…"
            )
        }

        // Filter PlayerPointsStore to players currently rostered in
        // this league at the target position. A player who's been
        // dropped or is on another league's roster doesn't qualify.
        let standingsByRosterId = Dictionary(uniqueKeysWithValues: standings.map { ($0.rosterId, $0) })
        var rows: [PayoutProjection.StandingsRow] = []
        var bestUserId: String?
        var bestRosterId: Int?
        var bestPlayerId: String?
        var bestTotal: Double = 0
        var bestPlayerLabel: String = ""

        for roster in rosters {
            guard let rosterTeam = standingsByRosterId[roster.rosterId] else { continue }
            // Walk every player on this roster (starters + bench +
            // taxi + reserve — the points cache already accounts for
            // who actually started which week).
            for pid in roster.players ?? [] {
                let pts = playerPointsStore.points(for: pid)
                guard pts > 0 else { continue }
                let pos = playerStore.player(for: pid)?.displayPosition ?? ""
                guard pos == position else { continue }

                if pts > bestTotal {
                    bestTotal = pts
                    bestUserId = rosterTeam.userId
                    bestRosterId = roster.rosterId
                    bestPlayerId = pid
                    let player = playerStore.player(for: pid)
                    bestPlayerLabel = player?.fullDisplayName ?? "Player #\(pid)"
                }

                // Aggregate per-team totals at this position for the
                // drill-down view (sum a manager's full position room,
                // not just the MVP player).
                if let row = rows.firstIndex(where: { $0.userId == rosterTeam.userId }) {
                    let updated = rows[row]
                    rows[row] = PayoutProjection.StandingsRow(
                        userId: updated.userId,
                        teamName: updated.teamName,
                        value: updated.value + pts,
                        displayValue: String(format: "%.1f", updated.value + pts)
                    )
                } else {
                    rows.append(PayoutProjection.StandingsRow(
                        userId: rosterTeam.userId,
                        teamName: rosterTeam.teamName,
                        value: pts,
                        displayValue: String(format: "%.1f", pts)
                    ))
                }
            }
        }

        // Sort drill-down rows by per-team total points at this
        // position (descending) so the manager whose lineup leans on
        // the MVP can see who's catching up.
        rows.sort { $0.value > $1.value }

        guard let bestUserId, let bestRosterId else {
            return PayoutProjection(
                category: category,
                leader: nil,
                userPlacement: .behind(by: ""),
                projectedAmount: 0,
                standings: rows.isEmpty ? nil : rows,
                unavailableReason: nil
            )
        }
        _ = bestRosterId  // owner roster captured for future drill-in
        _ = bestPlayerId

        let leaderTeam = standingsByRosterId.values.first { $0.userId == bestUserId }
        let isMine = bestUserId == userId
        let leaderDisplay = "\(bestPlayerLabel) · \(String(format: "%.1f", bestTotal)) pts"

        return PayoutProjection(
            category: category,
            leader: PayoutProjection.LeaderRef(
                userId: bestUserId,
                teamName: leaderTeam?.teamName ?? "Unknown",
                displayValue: leaderDisplay
            ),
            userPlacement: isMine ? .leading : .behind(by: ""),
            projectedAmount: isMine ? category.amount : 0,
            standings: rows,
            unavailableReason: nil
        )
    }

    // MARK: - Champion / runner-up / 3rd

    private static func bracketPlacement(
        category: LeaguePayoutCategory,
        placement: Int,
        winnersBracket: [PlayoffBracketMatch]?,
        standings: [StandingsTeam],
        userId: String?
    ) -> PayoutProjection {
        guard let bracket = winnersBracket,
              let placementMatch = bracket.first(where: { $0.placement == placement }) else {
            return PayoutProjection(
                category: category,
                leader: nil,
                userPlacement: .pending,
                projectedAmount: 0,
                standings: nil,
                unavailableReason: "Bracket not yet decided."
            )
        }

        let winnerRosterId: Int? = {
            switch placement {
            case 1, 3: return placementMatch.winnerRosterId
            case 2:    return placementMatch.team1RosterId == placementMatch.winnerRosterId
                              ? placementMatch.team2RosterId
                              : placementMatch.team1RosterId
            default: return nil
            }
        }()

        guard let rid = winnerRosterId,
              let team = standings.first(where: { $0.rosterId == rid }) else {
            return PayoutProjection(
                category: category,
                leader: nil,
                userPlacement: .pending,
                projectedAmount: 0,
                standings: nil,
                unavailableReason: "Bracket placement match still in progress."
            )
        }

        let isMine = team.userId == userId
        return PayoutProjection(
            category: category,
            leader: .init(userId: team.userId, teamName: team.teamName, displayValue: ""),
            userPlacement: isMine ? .won(amount: category.amount) : .behind(by: ""),
            projectedAmount: isMine ? category.amount : 0,
            standings: nil,
            unavailableReason: nil
        )
    }

    // MARK: - Season high PF

    private static func seasonHighPF(
        category: LeaguePayoutCategory,
        standings: [StandingsTeam],
        userId: String?
    ) -> PayoutProjection {
        let sorted = standings.sorted(by: { $0.fpts > $1.fpts })
        guard let top = sorted.first else {
            return PayoutProjection(
                category: category,
                leader: nil,
                userPlacement: .pending,
                projectedAmount: 0,
                standings: [],
                unavailableReason: nil
            )
        }

        let rows = sorted.map { team in
            PayoutProjection.StandingsRow(
                userId: team.userId,
                teamName: team.teamName,
                value: team.fpts,
                displayValue: String(format: "%.1f", team.fpts)
            )
        }

        let mine = sorted.first { $0.userId == userId }
        let placement: PayoutProjection.UserPlacement = {
            guard let mine else { return .notApplicable }
            if mine.userId == top.userId {
                let secondPlace = sorted.dropFirst().first
                let lead = (secondPlace?.fpts).map { mine.fpts - $0 } ?? 0
                return lead < 0.05 ? .tied(otherCount: 1) : .leading
            }
            let gap = top.fpts - mine.fpts
            return .behind(by: String(format: "%.1f pts", gap))
        }()

        let isLeading = mine?.userId == top.userId
        return PayoutProjection(
            category: category,
            leader: .init(
                userId: top.userId,
                teamName: top.teamName,
                displayValue: String(format: "%.1f PF", top.fpts)
            ),
            userPlacement: placement,
            projectedAmount: isLeading ? category.amount : 0,
            standings: rows,
            unavailableReason: nil
        )
    }

    // MARK: - Weekly high

    private static func weeklyHigh(
        category: LeaguePayoutCategory,
        matchupHistory: [MatchupHistoryRecord],
        standings: [StandingsTeam],
        userId: String?
    ) -> PayoutProjection {
        // Only count regular-season weeks (isPlayoff == false) and
        // skip preseason/empty-score weeks.
        let regular = matchupHistory.filter { !$0.isPlayoff && ($0.teamAPoints > 0 || $0.teamBPoints > 0) }
        var byWeek: [Int: [MatchupHistoryRecord]] = [:]
        for record in regular {
            byWeek[record.week, default: []].append(record)
        }

        var weeksWonByUser: [String: Int] = [:]
        for (_, records) in byWeek {
            // For each week, find the single highest score across all
            // teams (counting both sides of every matchup).
            var bestUser: String?
            var bestPts: Double = 0
            var ties = 0
            for record in records {
                if record.teamAPoints > bestPts {
                    bestPts = record.teamAPoints
                    bestUser = record.teamAUserId
                    ties = 0
                } else if abs(record.teamAPoints - bestPts) < 0.05 {
                    ties += 1
                }
                if record.teamBPoints > bestPts {
                    bestPts = record.teamBPoints
                    bestUser = record.teamBUserId
                    ties = 0
                } else if abs(record.teamBPoints - bestPts) < 0.05 {
                    ties += 1
                }
            }
            // Skip ties — no single winner for the week
            if let bestUser, ties == 0 {
                weeksWonByUser[bestUser, default: 0] += 1
            }
        }

        let rows = standings.map { team in
            PayoutProjection.StandingsRow(
                userId: team.userId,
                teamName: team.teamName,
                value: Double(weeksWonByUser[team.userId] ?? 0),
                displayValue: "\(weeksWonByUser[team.userId] ?? 0) wks"
            )
        }
        .sorted(by: { $0.value > $1.value })

        let mineWeeks = userId.flatMap { weeksWonByUser[$0] } ?? 0
        let topWeeks = rows.first?.value ?? 0
        let leaderRow = rows.first

        let placement: PayoutProjection.UserPlacement = {
            guard userId != nil else { return .notApplicable }
            if mineWeeks == 0 { return .behind(by: "0 wks") }
            if Double(mineWeeks) == topWeeks { return .leading }
            return .behind(by: "\(Int(topWeeks) - mineWeeks) wks")
        }()

        return PayoutProjection(
            category: category,
            leader: leaderRow.map { .init(userId: $0.userId, teamName: $0.teamName, displayValue: $0.displayValue) },
            userPlacement: placement,
            // Each weekly win pays the per-week amount, regardless of
            // overall standing — running tally for the user.
            projectedAmount: Double(mineWeeks) * category.amount,
            standings: rows,
            unavailableReason: nil
        )
    }
}
