import Foundation

/// Pre-computed positional snapshot of the league at engine time.
/// Built once on the `MainActor`, then passed by value into
/// `MockDraftEngine.run` (which is pure / non-actor-isolated).
///
/// All the read-side per-roster math the engine needs lives here so
/// the engine itself stays a pure function of its inputs. Specifically:
///
/// - `posHPPByRoster[rosterId][position]` — that roster's
///   highest-possible regular-season points contributed by `position`
///   (the chosen optimal player at each weekly slot, attributed by
///   the player's position).
/// - `leagueAvgByPos[position]` — average of `teamPosHPP` across all
///   rosters. Drives the `needBoost` formula in `Team Fit`.
///
/// The builder is on `MainActor` because it reads from `LeagueStore`,
/// `HistoryStore`, `PlayerStore`, and `PlayerPointsStore` — all of
/// which are actor-isolated.
struct TeamContext: Sendable {

    /// Per-roster per-position HPP totals. Keys are roster IDs; inner
    /// keys are position labels (`"QB"`, `"RB"`, `"WR"`, `"TE"`).
    /// Missing positions implicitly = 0 — Team Fit reads via a default.
    let posHPPByRoster: [Int: [String: Double]]

    /// League average per position. `posHPPByRoster.values.reduce + avg`
    /// — pre-baked so the engine doesn't recompute on every pick.
    let leagueAvgByPos: [String: Double]

    /// True when the builder fell back to "all rosters get the
    /// no-boost identity" because no weekly points were available
    /// (preseason boot, fresh league, etc.). Team Fit then degrades
    /// to ≈ BPA — useful signal for the view to surface a banner.
    let isFallback: Bool

    /// Convenience accessor that returns `posHPPByRoster[roster][pos]`
    /// with a 0 default. Used in the `needBoost` formula.
    func teamPosHPP(rosterId: Int, position: String) -> Double {
        posHPPByRoster[rosterId]?[position] ?? 0
    }

    /// Convenience: league average for a position, with a 0 default.
    func leagueAvg(position: String) -> Double {
        leagueAvgByPos[position] ?? 0
    }
}

// MARK: - Builder

@MainActor
extension TeamContext {

    /// Builds a `TeamContext` from the live stores. Iterates each
    /// regular-season week × roster, calls the per-position HPP
    /// helper on `HighestPossibleCalculator`, and accumulates the
    /// per-position totals. Then averages across rosters for the
    /// league baseline.
    ///
    /// - Parameters:
    ///   - rosterIds: full set of rosters in the league (size 12 for
    ///     ours, but generic).
    ///   - leagueStore: provides `myLeague.rosterPositions` (slot
    ///     vocabulary for the optimal-lineup calc).
    ///   - playerStore: position lookup keyed by Sleeper player ID.
    ///   - playerPointsStore: per-week per-roster point dictionaries.
    ///   - regularSeasonLastWeek: cutoff week (inclusive) for the
    ///     HPP sum. Typically week 14 in a 14-week regular season.
    ///
    /// Falls back to `isFallback = true` with `leagueAvg = teamPosHPP`
    /// for every team (so needBoost = 1.0 everywhere) when either:
    /// - `rosterPositions` is missing, OR
    /// - `weeklyRosterPoints` is empty.
    static func build(
        rosterIds: [Int],
        leagueStore: LeagueStore,
        playerStore: PlayerStore,
        playerPointsStore: PlayerPointsStore,
        regularSeasonLastWeek: Int
    ) -> TeamContext {
        let rosterPositions = leagueStore.myLeague?.rosterPositions ?? []
        // Type is `[String]?` on League; default to empty so the
        // `isEmpty` guard catches both the nil and empty paths.
        let hasWeeklyData = !playerPointsStore.weeklyRosterPoints.isEmpty

        guard !rosterPositions.isEmpty, hasWeeklyData, !rosterIds.isEmpty else {
            // No usable data — return a zeroed snapshot. Team Fit's
            // `needBoost` formula degrades to 1.0 when both team and
            // league are 0 / equal, which is what we want.
            return TeamContext(
                posHPPByRoster: [:],
                leagueAvgByPos: [:],
                isFallback: true
            )
        }

        var posHPPByRoster: [Int: [String: Double]] = [:]
        for rosterId in rosterIds {
            var totals: [String: Double] = [:]
            for week in 1...max(regularSeasonLastWeek, 1) {
                let key = "\(week)-\(rosterId)"
                guard let weekPoints = playerPointsStore.weeklyRosterPoints[key],
                      !weekPoints.isEmpty else { continue }
                let weekly = HighestPossibleCalculator.optimalLineupPointsByPosition(
                    playerPoints: weekPoints,
                    rosterPositions: rosterPositions,
                    playerStore: playerStore
                )
                for (pos, pts) in weekly {
                    totals[pos, default: 0] += pts
                }
            }
            posHPPByRoster[rosterId] = totals
        }

        // League average per position: sum across rosters / roster
        // count. Rosters that genuinely have 0 at a position still
        // count toward the divisor — they pull the average down,
        // which makes the needBoost slightly more aggressive on weak
        // positions. That's what we want.
        var leagueAvgByPos: [String: Double] = [:]
        let denom = Double(rosterIds.count)
        var sums: [String: Double] = [:]
        for rosterId in rosterIds {
            let totals = posHPPByRoster[rosterId] ?? [:]
            for (pos, pts) in totals {
                sums[pos, default: 0] += pts
            }
        }
        for (pos, sum) in sums {
            leagueAvgByPos[pos] = denom > 0 ? sum / denom : 0
        }

        return TeamContext(
            posHPPByRoster: posHPPByRoster,
            leagueAvgByPos: leagueAvgByPos,
            isFallback: false
        )
    }
}
