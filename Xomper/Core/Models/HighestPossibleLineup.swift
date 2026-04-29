import Foundation

/// Computes "Highest Possible Points" (HPP) per team per week — the
/// maximum points a team's roster *could have scored* given the slot
/// configuration and the actual points each rostered player scored.
///
/// Used by #57's reverse-HPP draft order rule: managers who set bad
/// lineups have their actual points but a higher HPP, while managers
/// who maximized their starts have actual ≈ HPP. Sorting non-playoff
/// teams by HPP ascending rewards effort over tanking.
///
/// Algorithm: greedy assignment with slots sorted by restrictiveness
/// (specific positions before flex slots). Optimal for the standard
/// fantasy slot config; not exhaustive search but matches what
/// every fantasy "perfect lineup" tool does.
@MainActor
enum HighestPossibleCalculator {

    /// Slot labels Sleeper uses that DON'T count toward the active
    /// lineup — bench, IR, taxi, reserve.
    private static let nonStartingSlots: Set<String> = ["BN", "IR", "RES", "TAXI"]

    /// Slot label → set of position labels eligible for that slot.
    /// Covers Sleeper's full slot vocabulary across formats.
    private static let slotEligibility: [String: Set<String>] = [
        "QB":           ["QB"],
        "RB":           ["RB"],
        "WR":           ["WR"],
        "TE":           ["TE"],
        "K":            ["K"],
        "DEF":          ["DEF"],
        "DST":          ["DEF"],
        "FLEX":         ["RB", "WR", "TE"],
        "REC_FLEX":     ["WR", "TE"],
        "WRRB_FLEX":    ["RB", "WR"],
        "WRRB_WT":      ["RB", "WR", "TE"],
        "SUPER_FLEX":   ["QB", "RB", "WR", "TE"],
        "SUPER FLEX":   ["QB", "RB", "WR", "TE"],
        "Q/W/R/T":      ["QB", "RB", "WR", "TE"],
        "IDP_FLEX":     ["DL", "LB", "DB"],
        "DL":           ["DL", "DE", "DT"],
        "LB":           ["LB", "ILB", "OLB"],
        "DB":           ["DB", "CB", "S", "FS", "SS"],
    ]

    /// HPP for a single roster across the regular season. Returns 0
    /// if no per-week data has been fetched yet.
    static func seasonHPP(
        rosterId: Int,
        rosterPositions: [String],
        playerPointsStore: PlayerPointsStore,
        playerStore: PlayerStore,
        regularSeasonLastWeek: Int
    ) -> Double {
        var total: Double = 0
        for week in 1...max(regularSeasonLastWeek, 1) {
            let key = "\(week)-\(rosterId)"
            guard let weekPoints = playerPointsStore.weeklyRosterPoints[key],
                  !weekPoints.isEmpty else { continue }
            total += optimalLineupPoints(
                playerPoints: weekPoints,
                rosterPositions: rosterPositions,
                playerStore: playerStore
            )
        }
        return total
    }

    /// Optimal lineup points for a single week given:
    /// - `playerPoints`: every rostered player's score that week
    /// - `rosterPositions`: the league's slot config from
    ///   `league.rosterPositions` (e.g. ["QB", "RB", "RB", "WR",
    ///   "WR", "TE", "FLEX", "SUPER_FLEX", "BN", "BN", ...])
    /// - `playerStore`: position lookup
    static func optimalLineupPoints(
        playerPoints: [String: Double],
        rosterPositions: [String],
        playerStore: PlayerStore
    ) -> Double {
        // 1. Filter to active starting slots
        let activeSlots = rosterPositions.filter { !nonStartingSlots.contains($0) }
        guard !activeSlots.isEmpty else { return 0 }

        // 2. Resolve each slot's eligibility set
        let slots: [(slot: String, eligible: Set<String>)] = activeSlots.map { slot in
            (slot, slotEligibility[slot] ?? [slot])
        }

        // 3. Build candidate list — only players we have positions for
        struct Candidate {
            let id: String
            let pos: String
            let pts: Double
        }
        let candidates: [Candidate] = playerPoints.compactMap { pid, pts in
            guard let pos = playerStore.player(for: pid)?.displayPosition else { return nil }
            return Candidate(id: pid, pos: pos, pts: pts)
        }

        // 4. Sort slots by restrictiveness ascending (specific
        //    positions filled before flexes — greedy is optimal in
        //    this ordering for the standard fantasy slot lattice).
        let orderedSlots = slots.sorted { $0.eligible.count < $1.eligible.count }

        // 5. Greedy: each slot grabs the highest-scoring eligible
        //    unassigned candidate.
        var used: Set<String> = []
        var total: Double = 0
        for slotEntry in orderedSlots {
            let pick = candidates
                .filter { !used.contains($0.id) && slotEntry.eligible.contains($0.pos) }
                .max(by: { $0.pts < $1.pts })
            if let pick {
                used.insert(pick.id)
                total += pick.pts
            }
        }
        return total
    }
}
