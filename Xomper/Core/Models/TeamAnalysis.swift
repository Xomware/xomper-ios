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
    static func build(
        rosters: [Roster],
        users: [SleeperUser],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore
    ) -> [TeamAnalysis] {
        let userById: [String: SleeperUser] = Dictionary(
            uniqueKeysWithValues: users.compactMap { user -> (String, SleeperUser)? in
                guard let uid = user.userId else { return nil }
                return (uid, user)
            }
        )

        return rosters.map { roster in
            let starters = Set(roster.starters ?? [])
            let taxi = Set(roster.taxi ?? [])
            let reserve = Set(roster.reserve ?? [])
            let allRostered = roster.players ?? []

            var qb = 0, rb = 0, wr = 0, te = 0
            var bench = 0, taxiSum = 0
            var rosteredPlayers: [TeamAnalysis.RosteredPlayer] = []

            for pid in allRostered {
                let value = valuesStore.value(for: pid)
                let player = playerStore.player(for: pid)
                let pos = player?.displayPosition
                    ?? valuesStore.position(for: pid)
                    ?? "?"
                let name = player?.fullDisplayName ?? "Player"
                let isStarter = starters.contains(pid)
                let isTaxi = taxi.contains(pid)

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

            return TeamAnalysis(
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
                players: rosteredPlayers
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
}
