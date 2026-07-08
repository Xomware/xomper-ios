import Foundation

/// Per-team aggregate of dynasty value broken down by position group +
/// roster slot. Drives the hexagon chart on TeamAnalyzerView.
///
/// Values are summed across the team's roster (starters + bench +
/// taxi + reserve). Position is resolved via `Player.displayPosition`
/// from the global `PlayerStore` — so accuracy depends on player
/// data being loaded.
struct TeamAnalysis: Sendable, Hashable {
    let rosterId: Int
    let teamName: String
    let userId: String
    let avatarId: String?

    /// Sum of dynasty values per position group. Six axes for the
    /// hexagon chart.
    let qbValue: Int
    let rbValue: Int
    let wrValue: Int
    let teValue: Int
    /// Players on bench (not in starters / taxi / reserve).
    let benchValue: Int
    /// Players on taxi squad.
    let taxiValue: Int

    /// Individual players on this roster, sorted by value descending.
    let players: [RosteredPlayer]

    /// Team needs — positions where this team is weak relative to
    /// league average or has low depth. Sorted by severity.
    let needs: [TeamNeed]

    var totalValue: Int {
        qbValue + rbValue + wrValue + teValue + benchValue + taxiValue
    }

    /// Returns the values in the canonical hexagon order so the chart
    /// view can iterate without remembering keys.
    var hexAxes: [HexAxis] {
        [
            HexAxis(label: "QB", value: qbValue),
            HexAxis(label: "RB", value: rbValue),
            HexAxis(label: "WR", value: wrValue),
            HexAxis(label: "TE", value: teValue),
            HexAxis(label: "Bench", value: benchValue),
            HexAxis(label: "Taxi", value: taxiValue),
        ]
    }

    /// Players grouped by position for expandable display.
    func playersByPosition(_ position: String) -> [RosteredPlayer] {
        players.filter { $0.position == position }
    }

    struct HexAxis: Sendable, Hashable {
        let label: String
        let value: Int
    }

    /// A single rostered player with value info.
    struct RosteredPlayer: Sendable, Hashable, Identifiable {
        let playerId: String
        let name: String
        let position: String
        let value: Int
        let isStarter: Bool
        let isTaxi: Bool

        var id: String { playerId }
    }
}

@MainActor
enum TeamAnalysisBuilder {

    /// Builds analyses for every roster in the league. Players with
    /// unknown positions or no value contribute zero — surfaced as a
    /// "Uncategorized" warning on the view if the gap is large.
    ///
    /// Pass `rosterPositions` from the league to enable needs analysis.
    static func build(
        rosters: [Roster],
        users: [SleeperUser],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore,
        rosterPositions: [String]? = nil
    ) -> [TeamAnalysis] {
        let userById: [String: SleeperUser] = Dictionary(
            uniqueKeysWithValues: users.compactMap { user -> (String, SleeperUser)? in
                guard let uid = user.userId else { return nil }
                return (uid, user)
            }
        )

        // First pass: build team data without needs (needs require averages)
        var teamDataList: [(TeamAnalysis, [String: Int])] = []

        for roster in rosters {
            let starters = Set(roster.starters ?? [])
            let taxi = Set(roster.taxi ?? [])
            let reserve = Set(roster.reserve ?? [])
            let allRostered = roster.players ?? []

            var qb = 0, rb = 0, wr = 0, te = 0
            var bench = 0, taxiSum = 0
            var rosteredPlayers: [TeamAnalysis.RosteredPlayer] = []
            var positionCounts: [String: Int] = [:]  // Count players at each position

            for pid in allRostered {
                let value = valuesStore.value(for: pid)
                let player = playerStore.player(for: pid)
                let pos = player?.displayPosition
                    ?? valuesStore.position(for: pid)
                    ?? "?"
                let name = player?.fullDisplayName ?? "Player"
                let isStarter = starters.contains(pid)
                let isTaxi = taxi.contains(pid)

                // Count positions (only non-taxi players with value)
                if value > 0 && !isTaxi {
                    positionCounts[pos, default: 0] += 1
                }

                // Add to players list (even if value is 0)
                if value > 0 {
                    rosteredPlayers.append(TeamAnalysis.RosteredPlayer(
                        playerId: pid,
                        name: name,
                        position: pos,
                        value: value,
                        isStarter: isStarter,
                        isTaxi: isTaxi
                    ))
                }

                guard value > 0 else { continue }

                if isTaxi {
                    taxiSum += value
                    continue  // taxi never counts toward starter buckets
                }

                let onBench = !isStarter && !reserve.contains(pid)

                switch pos {
                case "QB":
                    if onBench { bench += value } else { qb += value }
                case "RB":
                    if onBench { bench += value } else { rb += value }
                case "WR":
                    if onBench { bench += value } else { wr += value }
                case "TE":
                    if onBench { bench += value } else { te += value }
                default:
                    // FLEX-eligible / unknown — treat as bench when
                    // not in a fixed slot. Avoids polluting position
                    // axes with mis-positioned values.
                    bench += value
                }
            }

            // Sort players by value descending
            rosteredPlayers.sort { $0.value > $1.value }

            let owner = roster.ownerId.flatMap { userById[$0] }
            let teamName = owner?.teamName
                ?? owner?.resolvedDisplayName
                ?? "Roster #\(roster.rosterId)"

            let analysis = TeamAnalysis(
                rosterId: roster.rosterId,
                teamName: teamName,
                userId: roster.ownerId ?? "",
                avatarId: owner?.avatar,
                qbValue: qb,
                rbValue: rb,
                wrValue: wr,
                teValue: te,
                benchValue: bench,
                taxiValue: taxiSum,
                players: rosteredPlayers,
                needs: []  // Placeholder, computed below
            )
            teamDataList.append((analysis, positionCounts))
        }

        // Second pass: compute league averages and needs
        let preliminaryTeams = teamDataList.map { $0.0 }
        let leagueAverages = leagueAverageAxes(preliminaryTeams)

        return teamDataList.map { (team, positionCounts) in
            let needs = computeNeeds(
                team: team,
                leagueAverages: leagueAverages,
                positionCounts: positionCounts,
                rosterPositions: rosterPositions
            )
            return TeamAnalysis(
                rosterId: team.rosterId,
                teamName: team.teamName,
                userId: team.userId,
                avatarId: team.avatarId,
                qbValue: team.qbValue,
                rbValue: team.rbValue,
                wrValue: team.wrValue,
                teValue: team.teValue,
                benchValue: team.benchValue,
                taxiValue: team.taxiValue,
                players: team.players,
                needs: needs
            )
        }
    }

    /// League-wide max per axis. The chart normalizes each team's
    /// polygon vertices against these so the outer ring = "best in
    /// league at this position" and a team's filled shape shows
    /// relative strength at a glance.
    static func axisMaxes(_ teams: [TeamAnalysis]) -> [String: Int] {
        var max: [String: Int] = [
            "QB": 0, "RB": 0, "WR": 0, "TE": 0, "Bench": 0, "Taxi": 0
        ]
        for team in teams {
            for axis in team.hexAxes {
                if axis.value > (max[axis.label] ?? 0) {
                    max[axis.label] = axis.value
                }
            }
        }
        return max
    }

    /// League-wide average per axis. Drives the "league average"
    /// overlay polygon on the hex chart and the per-position bars in
    /// the League tab — gives the user a baseline to read relative
    /// strength against without doing mental math from raw maxes.
    /// Returned in the canonical hex-axis order so it can be rendered
    /// alongside any team's `hexAxes`.
    static func leagueAverageAxes(_ teams: [TeamAnalysis]) -> [TeamAnalysis.HexAxis] {
        guard !teams.isEmpty else {
            return ["QB", "RB", "WR", "TE", "Bench", "Taxi"]
                .map { TeamAnalysis.HexAxis(label: $0, value: 0) }
        }
        let count = Double(teams.count)
        var sums: [String: Int] = [
            "QB": 0, "RB": 0, "WR": 0, "TE": 0, "Bench": 0, "Taxi": 0
        ]
        for team in teams {
            for axis in team.hexAxes {
                sums[axis.label, default: 0] += axis.value
            }
        }
        return ["QB", "RB", "WR", "TE", "Bench", "Taxi"].map { label in
            TeamAnalysis.HexAxis(
                label: label,
                value: Int(Double(sums[label] ?? 0) / count)
            )
        }
    }

    /// Compute needs for a single team given league averages.
    /// A position is a "need" if the team's value is below 80% of
    /// league average OR if they have thin depth (fewer starters
    /// than typical starting slots require).
    static func computeNeeds(
        team: TeamAnalysis,
        leagueAverages: [TeamAnalysis.HexAxis],
        positionCounts: [String: Int],
        rosterPositions: [String]?
    ) -> [TeamNeed] {
        var needs: [TeamNeed] = []

        // Map label to average value
        let avgByPos: [String: Int] = Dictionary(
            uniqueKeysWithValues: leagueAverages.compactMap { axis in
                ["QB", "RB", "WR", "TE"].contains(axis.label) ? (axis.label, axis.value) : nil
            }
        )

        // Count required starters per position from league settings
        let requiredStarters = countRequiredStarters(rosterPositions: rosterPositions)

        // Check each position
        let positionValues: [(String, Int)] = [
            ("QB", team.qbValue),
            ("RB", team.rbValue),
            ("WR", team.wrValue),
            ("TE", team.teValue)
        ]

        for (pos, value) in positionValues {
            let avg = avgByPos[pos] ?? 0
            let count = positionCounts[pos] ?? 0
            let required = requiredStarters[pos] ?? 0

            // Calculate how far below average (as percentage)
            let ratio = avg > 0 ? Double(value) / Double(avg) : 1.0

            // Determine severity
            var severity: TeamNeed.Severity = .none
            var reason = ""

            if ratio < 0.65 {
                severity = .critical
                reason = "Well below league average"
            } else if ratio < 0.80 {
                severity = .high
                reason = "Below league average"
            } else if count < required && count > 0 {
                // Has fewer quality starters than needed
                severity = .moderate
                reason = "Thin depth (\(count) rostered, \(required) slots)"
            } else if ratio < 0.90 && count <= required {
                severity = .low
                reason = "Slightly below average"
            }

            if severity != .none {
                needs.append(TeamNeed(
                    position: pos,
                    severity: severity,
                    reason: reason,
                    valueVsAvg: ratio
                ))
            }
        }

        // Sort by severity (critical first)
        return needs.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    /// Count how many starting slots each position needs.
    /// Parses rosterPositions like ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "BN"...]
    private static func countRequiredStarters(rosterPositions: [String]?) -> [String: Int] {
        guard let positions = rosterPositions else {
            // Default dynasty superflex: 1 QB, 2 RB, 2 WR, 1 TE + FLEX
            return ["QB": 1, "RB": 2, "WR": 2, "TE": 1]
        }

        var counts: [String: Int] = ["QB": 0, "RB": 0, "WR": 0, "TE": 0]
        var flexCount = 0
        var superflexCount = 0

        for pos in positions {
            switch pos.uppercased() {
            case "QB": counts["QB", default: 0] += 1
            case "RB": counts["RB", default: 0] += 1
            case "WR": counts["WR", default: 0] += 1
            case "TE": counts["TE", default: 0] += 1
            case "FLEX", "REC_FLEX": flexCount += 1  // RB/WR/TE eligible
            case "SUPER_FLEX", "SUPERFLEX": superflexCount += 1  // QB/RB/WR/TE eligible
            default: break  // BN, IR, TAXI, etc.
            }
        }

        // FLEX adds to RB/WR/TE depth needs (they compete for flex)
        // We add fractional credit: if you have 2 FLEX, each position
        // effectively needs ~0.67 more depth. Simplify to +1 per 2 flex.
        let flexBonus = flexCount / 2
        counts["RB", default: 0] += flexBonus
        counts["WR", default: 0] += flexBonus
        counts["TE", default: 0] += flexBonus

        // SUPERFLEX adds QB depth need primarily
        counts["QB", default: 0] += superflexCount

        return counts
    }
}

// MARK: - Team Need

/// Represents a positional need for a team.
struct TeamNeed: Sendable, Hashable, Identifiable {
    let position: String
    let severity: Severity
    let reason: String
    /// Team's value at this position divided by league average (0.0-1.0+)
    let valueVsAvg: Double

    var id: String { position }

    enum Severity: Int, Sendable, Hashable {
        case none = 0
        case low = 1
        case moderate = 2
        case high = 3
        case critical = 4

        var label: String {
            switch self {
            case .none: return ""
            case .low: return "Low"
            case .moderate: return "Need"
            case .high: return "High Need"
            case .critical: return "Critical"
            }
        }
    }
}
