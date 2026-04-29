import Foundation

/// A proposed trade between two teams in the home league. Each side
/// holds a roster of player IDs (extending later to draft picks per
/// the open question in #75).
///
/// Pure value type — held by the Trade tab's `@State`. Evaluator runs
/// in `TradeEvaluator.evaluate(_:against:)` and returns a fresh
/// `TradeEvaluation` on every change.
struct ProposedTrade: Sendable, Hashable {
    var sideA: TradeSide
    var sideB: TradeSide

    static let empty = ProposedTrade(
        sideA: TradeSide(rosterId: 0, teamName: "", playerIds: []),
        sideB: TradeSide(rosterId: 0, teamName: "", playerIds: [])
    )

    var isEmpty: Bool {
        sideA.isEmpty && sideB.isEmpty
    }
}

struct TradeSide: Sendable, Hashable {
    let rosterId: Int
    let teamName: String
    var playerIds: [String]
    /// Pick names from FantasyCalc (e.g. "2026 Mid 1st"). Picks are
    /// not roster-tied at the FantasyCalc level — the league
    /// commissioner enforces ownership in Sleeper. v1 trusts the
    /// user not to add picks they don't own.
    var pickNames: [String] = []

    var isEmpty: Bool { playerIds.isEmpty && pickNames.isEmpty }
}

// MARK: - Evaluation

/// Result of running `TradeEvaluator` over a `ProposedTrade`. Drives
/// the live evaluation strip + verdict pill in the trade builder.
struct TradeEvaluation: Sendable, Hashable {
    let sideAValue: Int
    let sideBValue: Int
    let delta: Int
    let percentGap: Double
    let verdict: Verdict

    /// Threshold below which a trade is considered "fair." Picked at
    /// 5% per the issue spec — tight enough that close trades don't
    /// auto-pass but loose enough to allow the typical
    /// star-for-depth packages.
    static let fairThreshold: Double = 0.05

    enum Verdict: Sendable, Hashable {
        case empty
        case fair
        case sideAWins(byPercent: Double)
        case sideBWins(byPercent: Double)

        var label: String {
            switch self {
            case .empty:
                return "Add players to evaluate"
            case .fair:
                return "Fair (within 5%)"
            case .sideAWins(let pct):
                return String(format: "Side A wins by %.0f%%", pct * 100)
            case .sideBWins(let pct):
                return String(format: "Side B wins by %.0f%%", pct * 100)
            }
        }

        var isFair: Bool {
            if case .fair = self { return true }
            return false
        }
    }
}

@MainActor
enum TradeEvaluator {

    /// Run the full evaluation against a `PlayerValuesStore` snapshot.
    /// Pure function — no side effects, safe to call on every UI
    /// re-render. Both player and pick values contribute to each side.
    static func evaluate(
        _ trade: ProposedTrade,
        valuesStore: PlayerValuesStore
    ) -> TradeEvaluation {
        let aValue = sideValue(trade.sideA, valuesStore: valuesStore)
        let bValue = sideValue(trade.sideB, valuesStore: valuesStore)
        let delta = aValue - bValue
        let larger = max(aValue, bValue)
        let gap = larger > 0 ? Double(abs(delta)) / Double(larger) : 0

        let verdict: TradeEvaluation.Verdict
        if trade.isEmpty {
            verdict = .empty
        } else if gap <= TradeEvaluation.fairThreshold {
            verdict = .fair
        } else if aValue > bValue {
            verdict = .sideAWins(byPercent: gap)
        } else {
            verdict = .sideBWins(byPercent: gap)
        }

        return TradeEvaluation(
            sideAValue: aValue,
            sideBValue: bValue,
            delta: delta,
            percentGap: gap,
            verdict: verdict
        )
    }

    static func sideValue(
        _ side: TradeSide,
        valuesStore: PlayerValuesStore
    ) -> Int {
        let players = side.playerIds.reduce(0) { $0 + valuesStore.value(for: $1) }
        let picks = side.pickNames.reduce(0) { $0 + valuesStore.pickValue(for: $1) }
        return players + picks
    }

    /// Suggest add-ons from the *lighter* side that would close the
    /// gap. Returns up to `limit` players ranked by how close they
    /// bring the trade to fair, but never overshoots beyond the fair
    /// threshold (overshoot would just flip the imbalance).
    ///
    /// Excludes players already in either side of the trade and
    /// players the lighter side has already promised away.
    static func suggestBalance(
        for trade: ProposedTrade,
        evaluation: TradeEvaluation,
        rosters: [Roster],
        valuesStore: PlayerValuesStore,
        playerStore: PlayerStore,
        limit: Int = 5
    ) -> [SuggestedAddOn] {
        guard !evaluation.verdict.isFair, !trade.isEmpty else { return [] }

        let lighterSide: TradeSide
        let lighterValue: Int
        let heavierValue: Int
        switch evaluation.verdict {
        case .sideAWins:
            lighterSide = trade.sideB
            lighterValue = evaluation.sideBValue
            heavierValue = evaluation.sideAValue
        case .sideBWins:
            lighterSide = trade.sideA
            lighterValue = evaluation.sideAValue
            heavierValue = evaluation.sideBValue
        default:
            return []
        }

        let neededValue = heavierValue - lighterValue
        // Acceptable range — any single add-on should leave the trade
        // within fair_threshold on either side. So the candidate's
        // value must be ≥ minimum that keeps the gap closing without
        // overshooting fair on the other side.
        let upperBound = neededValue + Int(Double(heavierValue) * TradeEvaluation.fairThreshold)
        let lowerBound = neededValue - Int(Double(heavierValue) * TradeEvaluation.fairThreshold)

        guard let roster = rosters.first(where: { $0.rosterId == lighterSide.rosterId }) else {
            return []
        }

        let alreadyInTrade = Set(trade.sideA.playerIds + trade.sideB.playerIds)

        let candidates: [SuggestedAddOn] = (roster.players ?? []).compactMap { pid in
            guard !alreadyInTrade.contains(pid) else { return nil }
            let value = valuesStore.value(for: pid)
            guard value > 0 else { return nil }
            let player = playerStore.player(for: pid)
            return SuggestedAddOn(
                playerId: pid,
                playerName: player?.fullDisplayName ?? "Player #\(pid)",
                position: player?.displayPosition ?? "?",
                value: value,
                gapClosed: abs(value - neededValue)
            )
        }

        // Prefer add-ons within the band first; if nothing fits the
        // band, fall back to closest-to-needed regardless.
        let inBand = candidates
            .filter { $0.value >= lowerBound && $0.value <= upperBound }
            .sorted(by: { $0.gapClosed < $1.gapClosed })

        if !inBand.isEmpty {
            return Array(inBand.prefix(limit))
        }

        return Array(
            candidates
                .sorted(by: { $0.gapClosed < $1.gapClosed })
                .prefix(limit)
        )
    }
}

struct SuggestedAddOn: Sendable, Hashable, Identifiable {
    let playerId: String
    let playerName: String
    let position: String
    let value: Int
    /// |candidate.value − neededValue|. Lower = closer to a perfectly
    /// balanced trade after this add-on is included.
    let gapClosed: Int

    var id: String { playerId }
}

/// A pre-built fair-value trade that improves the user's weakest
/// position. Generated by `RecommendedTradeBuilder`.
struct RecommendedTrade: Sendable, Hashable, Identifiable {
    /// Stable identity for ForEach — partner roster + give/receive
    /// player ids joined.
    let id: String
    let partnerRosterId: Int
    let partnerTeamName: String
    /// Player you'd give up (currently surplus on a strong position).
    let give: PlayerSummary
    /// Player you'd receive (their surplus on your weak position).
    let receive: PlayerSummary
    /// How much this trade lifts your weak position toward league avg.
    /// Used to rank suggestions.
    let myImprovement: Int
    /// Final value gap between sides as a percent of the larger side.
    /// All recommendations are within `TradeEvaluation.fairThreshold`.
    let percentGap: Double

    struct PlayerSummary: Sendable, Hashable {
        let playerId: String
        let name: String
        let position: String
        let value: Int
    }
}

@MainActor
enum RecommendedTradeBuilder {

    /// Find fair-value trades that improve the user's weakest
    /// position(s). Algorithm:
    ///
    /// 1. Compute league averages per position.
    /// 2. Identify my weak positions (≤85% of league avg) and surplus
    ///    positions (≥105% of league avg).
    /// 3. For each potential partner team:
    ///    - Find positions where THEY are surplus and I am weak.
    ///    - For each such position, take their highest-value player
    ///      at that spot.
    ///    - Find one of my surplus-position players whose value is
    ///      within `fairThreshold` of theirs.
    /// 4. Rank surviving pairs by my-improvement (their player's
    ///    value at my weak position, capped at the gap to league avg).
    ///
    /// Returns up to `limit` non-duplicate recommendations.
    static func recommend(
        myAnalysis: TeamAnalysis,
        analyses: [TeamAnalysis],
        rosters: [Roster],
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore,
        limit: Int = 5
    ) -> [RecommendedTrade] {
        let leagueAverages = TeamAnalysisBuilder.leagueAverageAxes(analyses)
        let avgByPos: [String: Int] = Dictionary(
            uniqueKeysWithValues: leagueAverages.map { ($0.label, $0.value) }
        )

        // Map my axes by label for quick weak/strong detection.
        let myByPos: [String: Int] = Dictionary(
            uniqueKeysWithValues: myAnalysis.hexAxes.map { ($0.label, $0.value) }
        )

        let positionLabels = ["QB", "RB", "WR", "TE"]
        let weakPositions = positionLabels.filter { pos in
            let mine = Double(myByPos[pos] ?? 0)
            let avg = Double(avgByPos[pos] ?? 1)
            return avg > 0 && mine / avg <= 0.85
        }
        let strongPositions = positionLabels.filter { pos in
            let mine = Double(myByPos[pos] ?? 0)
            let avg = Double(avgByPos[pos] ?? 1)
            return avg > 0 && mine / avg >= 1.05
        }

        guard !weakPositions.isEmpty, !strongPositions.isEmpty else { return [] }

        // Resolve roster for me + partners
        let myRoster = rosters.first { $0.rosterId == myAnalysis.rosterId }
        let partners = analyses.filter { $0.rosterId != myAnalysis.rosterId }

        var seenPairs: Set<String> = []
        var candidates: [RecommendedTrade] = []

        for partner in partners {
            let partnerByPos: [String: Int] = Dictionary(
                uniqueKeysWithValues: partner.hexAxes.map { ($0.label, $0.value) }
            )
            let partnerRoster = rosters.first { $0.rosterId == partner.rosterId }
            guard let partnerRoster else { continue }

            // For each of my weak positions, see if partner is surplus there.
            for weak in weakPositions {
                let partnerStrength = Double(partnerByPos[weak] ?? 0)
                let avg = Double(avgByPos[weak] ?? 1)
                guard avg > 0, partnerStrength / avg >= 1.05 else { continue }

                // Get partner's top-value player at this weak-for-me position.
                guard let theirPlayer = topPlayer(
                    at: weak,
                    onRoster: partnerRoster,
                    playerStore: playerStore,
                    valuesStore: valuesStore
                ) else { continue }

                // Find one of my players from a strong position whose
                // value lines up with theirs (within fair threshold).
                for strong in strongPositions {
                    guard let myRoster else { continue }
                    let myCandidates = playersAtPosition(
                        strong,
                        onRoster: myRoster,
                        playerStore: playerStore,
                        valuesStore: valuesStore
                    )
                    .sorted(by: { $0.value > $1.value })

                    guard let mine = myCandidates.first(where: { candidate in
                        let larger = max(candidate.value, theirPlayer.value)
                        guard larger > 0 else { return false }
                        let gap = Double(abs(candidate.value - theirPlayer.value)) / Double(larger)
                        return gap <= TradeEvaluation.fairThreshold
                    }) else { continue }

                    let pairKey = "\(partner.rosterId):\(mine.playerId):\(theirPlayer.playerId)"
                    if seenPairs.contains(pairKey) { continue }
                    seenPairs.insert(pairKey)

                    let larger = max(mine.value, theirPlayer.value)
                    let gap = larger > 0 ? Double(abs(mine.value - theirPlayer.value)) / Double(larger) : 0

                    candidates.append(
                        RecommendedTrade(
                            id: pairKey,
                            partnerRosterId: partner.rosterId,
                            partnerTeamName: partner.teamName,
                            give: mine,
                            receive: theirPlayer,
                            // Improvement capped at gap-to-league-avg
                            // so a star coming in at a weak spot doesn't
                            // over-rank when I'm already close to avg.
                            myImprovement: min(theirPlayer.value, max(0, (avgByPos[weak] ?? 0) - (myByPos[weak] ?? 0))),
                            percentGap: gap
                        )
                    )
                }
            }
        }

        // Rank by impact on weakest position, descending.
        return Array(
            candidates
                .sorted(by: { $0.myImprovement > $1.myImprovement })
                .prefix(limit)
        )
    }

    private static func topPlayer(
        at position: String,
        onRoster roster: Roster,
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore
    ) -> RecommendedTrade.PlayerSummary? {
        playersAtPosition(position, onRoster: roster, playerStore: playerStore, valuesStore: valuesStore)
            .max(by: { $0.value < $1.value })
    }

    private static func playersAtPosition(
        _ position: String,
        onRoster roster: Roster,
        playerStore: PlayerStore,
        valuesStore: PlayerValuesStore
    ) -> [RecommendedTrade.PlayerSummary] {
        (roster.players ?? []).compactMap { pid in
            let value = valuesStore.value(for: pid)
            guard value > 0 else { return nil }
            let player = playerStore.player(for: pid)
            let pos = player?.displayPosition ?? valuesStore.position(for: pid) ?? "?"
            guard pos == position else { return nil }
            return RecommendedTrade.PlayerSummary(
                playerId: pid,
                name: player?.fullDisplayName ?? "Player #\(pid)",
                position: pos,
                value: value
            )
        }
    }
}
