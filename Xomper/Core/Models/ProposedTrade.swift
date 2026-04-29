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
        sideA.playerIds.isEmpty && sideB.playerIds.isEmpty
    }
}

struct TradeSide: Sendable, Hashable {
    let rosterId: Int
    let teamName: String
    var playerIds: [String]
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
    /// re-render.
    static func evaluate(
        _ trade: ProposedTrade,
        valuesStore: PlayerValuesStore
    ) -> TradeEvaluation {
        let aValue = trade.sideA.playerIds.reduce(0) { $0 + valuesStore.value(for: $1) }
        let bValue = trade.sideB.playerIds.reduce(0) { $0 + valuesStore.value(for: $1) }
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
