import Foundation

/// One rookie eligible for the engine's pool. Built by
/// `MockDraftStore.buildRookiePool` from the intersection of Sleeper
/// `yearsExp == 0` players + FantasyCalc dynasty values + skill
/// positions (QB/RB/WR/TE).
struct RookieCandidate: Sendable, Hashable {
    let playerId: String
    let fullName: String
    /// Position label — QB / RB / WR / TE (drives Win-Now multipliers).
    let position: String
    /// NFL team abbreviation, or empty string for free agents.
    let nflTeam: String
    /// FantasyCalc dynasty value. Drives all scoring formulas.
    let value: Double
}

/// Pure-Swift client-side mock-draft engine. No actors, no stores —
/// inputs in, picks out. Designed to be unit-testable with synthetic
/// pools and a fixed seed.
///
/// The engine takes a `personality` callback rather than a single
/// enum so Pure mode (constant personality) and Mixed mode (per-pick
/// lookup) share the same code path. The store builds the closure
/// appropriately for each mode.
enum MockDraftEngine {

    /// Win-Now position multipliers from `PLAN.md §3`. QB tightened
    /// to 0.85 in a superflex league since QB value is already
    /// inflated by 2-QB scoring — a flat 0.9 over-picks QBs.
    static let winNowMultipliers: [String: Double] = [
        "RB": 1.30,
        "WR": 1.20,
        "TE": 1.00,
        "QB": 0.85
    ]

    /// Team Fit needBoost clamp + curve exponent (k = 0.6 per the
    /// plan). Lifted to constants so tests can reference them.
    static let teamFitClampLow: Double = 0.6
    static let teamFitClampHigh: Double = 1.8
    static let teamFitExponent: Double = 0.6

    /// Wildcard top-N pool (uniform random within the top N by raw
    /// FantasyCalc value).
    static let wildcardTopN: Int = 8

    /// Hype Train: `value^1.20` + per-candidate jitter in
    /// `[-jitterFraction, +jitterFraction] * value`.
    static let hypeTrainExponent: Double = 1.20
    static let hypeTrainJitterFraction: Double = 0.01

    /// Tie-break tolerance: two scores within this relative threshold
    /// of each other count as a tie and break by value desc then
    /// playerId asc. 0.5% per the plan.
    static let tieThreshold: Double = 0.005

    /// Runs a full mock draft.
    ///
    /// - Parameters:
    ///   - rookies: pool of eligible rookies (already filtered to
    ///     skill positions + non-zero FantasyCalc value).
    ///   - slotOrder: `slot → SlotTeam` map. The engine iterates
    ///     `slot = 1...teams` so slots must be contiguous from 1.
    ///   - rounds: how many rounds to draft (5 in v1 → 60 picks at
    ///     12 teams).
    ///   - teamContext: per-roster per-position HPP snapshot, used
    ///     by Team Fit's `needBoost`.
    ///   - personality: `(pickNo) -> DraftPersonality`. Pure mode
    ///     returns a constant; Mixed mode looks up by rosterId.
    ///   - rng: seeded RNG for Wildcard / Hype Train jitter. Other
    ///     personalities don't touch it. Passed `inout` so callers
    ///     can observe state advancement (and tests can verify).
    ///
    /// - Returns: tuple of `(picks, didExhaustPool)`. Pool exhaustion
    ///   happens when the pool is smaller than `rounds × teams`; the
    ///   engine stops appending picks at that point.
    static func run(
        rookies: [RookieCandidate],
        slotOrder: [Int: SlotTeam],
        rounds: Int,
        teamContext: TeamContext,
        personality: (_ pickNo: Int, _ rosterId: Int) -> DraftPersonality,
        rng: inout SeededRNG
    ) -> (picks: [EngineMockedPick], didExhaustPool: Bool) {
        guard !rookies.isEmpty, rounds > 0, !slotOrder.isEmpty else {
            return ([], !rookies.isEmpty)
        }

        let slots = slotOrder.keys.sorted()
        let teams = slots.count

        var taken: Set<String> = []
        var picks: [EngineMockedPick] = []
        picks.reserveCapacity(rounds * teams)

        // Filter from the full rookie list each pick — a Set lookup
        // per candidate is O(1) and N (~50–80 rookies) is tiny.
        // Keeping `rookies` immutable avoids defensive copies.
        var pickNo = 0
        for round in 1...rounds {
            for slot in slots {
                pickNo += 1
                guard let team = slotOrder[slot] else { continue }
                let pers = personality(pickNo, team.rosterId)

                let available = rookies.filter { !taken.contains($0.playerId) }
                guard !available.isEmpty else {
                    return (picks, true)
                }

                guard let chosen = pickOne(
                    from: available,
                    personality: pers,
                    rosterId: team.rosterId,
                    teamContext: teamContext,
                    rng: &rng
                ) else {
                    return (picks, true)
                }

                taken.insert(chosen.candidate.playerId)
                picks.append(
                    EngineMockedPick(
                        pickNo: pickNo,
                        round: round,
                        slot: slot,
                        rosterId: team.rosterId,
                        userId: team.userId,
                        teamName: team.teamName,
                        playerId: chosen.candidate.playerId,
                        playerName: chosen.candidate.fullName,
                        position: chosen.candidate.position,
                        nflTeam: chosen.candidate.nflTeam,
                        value: chosen.candidate.value,
                        score: chosen.score,
                        personality: pers
                    )
                )
            }
        }

        return (picks, false)
    }

    // MARK: - Per-pick selection

    private struct ScoredCandidate {
        let candidate: RookieCandidate
        let score: Double
    }

    private static func pickOne(
        from available: [RookieCandidate],
        personality: DraftPersonality,
        rosterId: Int,
        teamContext: TeamContext,
        rng: inout SeededRNG
    ) -> ScoredCandidate? {
        switch personality {
        case .bpa:
            return bestByValue(available)

        case .winNow:
            let scored = available.map { c -> ScoredCandidate in
                let mult = winNowMultipliers[c.position] ?? 1.0
                return ScoredCandidate(candidate: c, score: c.value * mult)
            }
            return topByScore(scored)

        case .teamFit:
            let scored = available.map { c -> ScoredCandidate in
                let boost = needBoost(
                    rosterId: rosterId,
                    position: c.position,
                    teamContext: teamContext
                )
                return ScoredCandidate(candidate: c, score: c.value * boost)
            }
            return topByScore(scored)

        case .hypeTrain:
            let scored = available.map { c -> ScoredCandidate in
                let base = pow(c.value, hypeTrainExponent)
                let jitter = rng.nextDouble(
                    in: -hypeTrainJitterFraction..<hypeTrainJitterFraction
                ) * c.value
                return ScoredCandidate(candidate: c, score: base + jitter)
            }
            return topByScore(scored)

        case .wildcard:
            // Top-N by raw FantasyCalc value, then pick uniformly at
            // random. Score = value (we don't actually use a derived
            // score for Wildcard — the value IS the score).
            let sorted = available.sorted { $0.value > $1.value }
            let topN = Array(sorted.prefix(wildcardTopN))
            guard !topN.isEmpty else { return nil }
            let idx = rng.nextInt(in: 0..<topN.count)
            let chosen = topN[idx]
            return ScoredCandidate(candidate: chosen, score: chosen.value)
        }
    }

    // MARK: - Helpers

    /// `score = value` — used by BPA, and as the trivial top-by-value
    /// path with deterministic tie-breaking.
    private static func bestByValue(_ candidates: [RookieCandidate]) -> ScoredCandidate? {
        let scored = candidates.map { ScoredCandidate(candidate: $0, score: $0.value) }
        return topByScore(scored)
    }

    /// Picks the highest-scoring candidate with deterministic
    /// tie-breaking: any two scores within `tieThreshold` relative of
    /// each other are tied; ties break by `value` desc, then by
    /// `playerId` asc.
    private static func topByScore(_ scored: [ScoredCandidate]) -> ScoredCandidate? {
        guard let top = scored.max(by: { $0.score < $1.score }) else { return nil }
        // Collect all within tie threshold of the top score.
        let tieFloor = top.score * (1 - tieThreshold)
        let tied = scored.filter { $0.score >= tieFloor }
        guard tied.count > 1 else { return top }
        // Break ties deterministically.
        let sorted = tied.sorted { lhs, rhs in
            if lhs.candidate.value != rhs.candidate.value {
                return lhs.candidate.value > rhs.candidate.value
            }
            return lhs.candidate.playerId < rhs.candidate.playerId
        }
        return sorted.first!
    }

    /// Team Fit `needBoost` formula. Returns 1.0 in the fallback /
    /// missing-data case so Team Fit degrades to BPA.
    static func needBoost(
        rosterId: Int,
        position: String,
        teamContext: TeamContext
    ) -> Double {
        let teamPos = teamContext.teamPosHPP(rosterId: rosterId, position: position)
        let leagueAvg = teamContext.leagueAvg(position: position)
        guard leagueAvg > 0 else { return 1.0 }
        let ratio = leagueAvg / max(teamPos, 1)
        let raw = pow(ratio, teamFitExponent)
        return min(max(raw, teamFitClampLow), teamFitClampHigh)
    }
}
