import Foundation

/// Client-side draft grade for one team in a single year's rookie
/// draft. Pure value type; produced by `DraftGradeCalculator` from
/// `DraftHistoryRecord` + `PlayerValuesStore`. No backend / AI work
/// involved — every input is data we already have on device.
///
/// Used by `DraftGradesCard` in `DraftRecapView` to render a
/// structured grade panel above the AI-generated recap markdown.
struct DraftGrade: Sendable, Hashable, Identifiable {
    let rosterId: Int
    let userId: String
    let teamName: String
    let managerName: String
    let avatarId: String?
    let picks: [GradedPick]
    /// Sum of FantasyCalc value across this team's picks.
    let totalValue: Int
    /// Sum of (actualValue - expectedAtPickNo) across this team's picks.
    /// Positive = stole value, negative = reached.
    let valueOverExpected: Int
    /// Letter assigned after bucketing all teams in the room by
    /// `valueOverExpected`.
    let letter: String

    var id: Int { rosterId }
}

/// Per-pick grade attached to a `DraftGrade`. Carries the player
/// info pre-resolved so the view layer doesn't need to re-join
/// against PlayerValuesStore at render time.
struct GradedPick: Sendable, Hashable, Identifiable {
    let round: Int
    let slot: Int
    let pickNo: Int
    let playerId: String
    let playerName: String
    let position: String
    let nflTeam: String
    let value: Int
    /// Expected value at this overall pick number, derived from the
    /// actual draft (nth-highest value across all drafted players).
    let expectedValue: Int
    /// `value - expectedValue`. Positive = steal, negative = reach.
    var delta: Int { value - expectedValue }

    var id: Int { pickNo }
}

// MARK: - Calculator

enum DraftGradeCalculator {

    /// Build per-team grades from a year's draft picks + FantasyCalc
    /// values. Returns a roster-keyed dictionary so `DraftRecapView`
    /// can iterate teams in any order it wants.
    ///
    /// Algorithm:
    /// 1. For each pick, resolve `value = playerValues.value(playerId)`.
    /// 2. Build the expected-value curve by sorting **actual** pick
    ///    values descending. At overall pick N, expected[N] = the
    ///    Nth-highest value drafted. If a team took the best available
    ///    when their pick came up, `delta == 0`. Reaches go negative,
    ///    steals positive.
    /// 3. Group picks by `pickedByRosterId`, sum value + delta.
    /// 4. Rank teams by `valueOverExpected` desc, bucket into A+/A/A-/
    ///    B+/B/B-/C+/C/C-/D using even thirds of the spread.
    ///
    /// Need-fit bonus (penalty for doubling on a strong position,
    /// bonus for filling a thin one) is intentionally not modeled in
    /// v1 — pre-draft roster composition isn't reliably available at
    /// recap time. The value-over-expected number alone is the
    /// dominant signal for dynasty rookie drafts where positional
    /// scarcity is league-wide.
    @MainActor
    static func grade(
        picks: [DraftHistoryRecord],
        playerValues: PlayerValuesStore
    ) -> [Int: DraftGrade] {
        guard !picks.isEmpty else { return [:] }

        // 1. Resolve every pick's value once.
        let sortedPicks = picks.sorted { $0.pickNo < $1.pickNo }
        let resolved: [(record: DraftHistoryRecord, value: Int)] = sortedPicks.map { record in
            (record, playerValues.value(for: record.playerId))
        }

        #if DEBUG
        let zeroCount = resolved.filter { $0.value == 0 }.count
        if zeroCount > 0 {
            print("[DraftGrade] \(zeroCount)/\(resolved.count) picks have value=0")
            if let first = resolved.first(where: { $0.value == 0 }) {
                print("[DraftGrade] Example: \(first.record.playerName) (ID: \(first.record.playerId))")
            }
        }
        #endif

        // 2. Expected curve = actual values sorted desc.
        let expectedCurve = resolved.map(\.value).sorted(by: >)

        // Build GradedPick per record; pickNo is 1-based so index by
        // (pickNo - 1) into the expected curve.
        var picksByRoster: [Int: [GradedPick]] = [:]
        for (idx, entry) in resolved.enumerated() {
            let expected = idx < expectedCurve.count ? expectedCurve[idx] : 0
            let graded = GradedPick(
                round: entry.record.round,
                slot: entry.record.draftSlot,
                pickNo: entry.record.pickNo,
                playerId: entry.record.playerId,
                playerName: entry.record.playerName,
                position: entry.record.playerPosition,
                nflTeam: entry.record.playerTeam,
                value: entry.value,
                expectedValue: expected
            )
            picksByRoster[entry.record.pickedByRosterId, default: []].append(graded)
        }

        // 3. Aggregate per team.
        struct TeamAgg {
            let rosterId: Int
            let userId: String
            let teamName: String
            let managerName: String
            let avatarId: String?
            let picks: [GradedPick]
            let totalValue: Int
            let valueOverExpected: Int
        }

        let aggregates: [TeamAgg] = picksByRoster.compactMap { (rosterId, picks) in
            guard let firstRecord = sortedPicks.first(where: { $0.pickedByRosterId == rosterId }) else {
                return nil
            }
            let total = picks.reduce(0) { $0 + $1.value }
            let voe   = picks.reduce(0) { $0 + $1.delta }
            return TeamAgg(
                rosterId: rosterId,
                userId: firstRecord.pickedByUserId,
                teamName: firstRecord.pickedByTeamName,
                managerName: firstRecord.pickedByUsername,
                avatarId: nil,
                picks: picks.sorted { $0.pickNo < $1.pickNo },
                totalValue: total,
                valueOverExpected: voe
            )
        }

        // 4. Bucket into letters by ranking on valueOverExpected.
        let letters = bucketLetters(byValueOverExpected: aggregates.map(\.valueOverExpected))
        let ranked = aggregates.enumerated().sorted {
            $0.element.valueOverExpected > $1.element.valueOverExpected
        }
        var out: [Int: DraftGrade] = [:]
        for (rankIdx, item) in ranked.enumerated() {
            let agg = item.element
            let letter = rankIdx < letters.count ? letters[rankIdx] : "C"
            out[agg.rosterId] = DraftGrade(
                rosterId: agg.rosterId,
                userId: agg.userId,
                teamName: agg.teamName,
                managerName: agg.managerName,
                avatarId: agg.avatarId,
                picks: agg.picks,
                totalValue: agg.totalValue,
                valueOverExpected: agg.valueOverExpected,
                letter: letter
            )
        }
        return out
    }

    /// Assign letters across N teams ranked from best to worst on
    /// `valueOverExpected`. We spread A+/A/A-/B+/B/B-/C+/C/C-/D-like
    /// labels using thirds of the rank distribution — top third gets
    /// A-range, middle gets B-range, bottom gets C/D-range. Plus/
    /// minus suffixes within each band by sub-rank.
    private static func bucketLetters(byValueOverExpected values: [Int]) -> [String] {
        guard !values.isEmpty else { return [] }
        let n = values.count
        // The order here matches the rank order (best -> worst), so
        // index i corresponds to the i-th best team. We don't depend
        // on the underlying values being sorted — only on count.
        return (0..<n).map { idx in
            let band = idx * 3 / n  // 0=A, 1=B, 2=C/D
            let subIdx = (idx % (max(n / 3, 1))) * 3 / max(n / 3, 1) // 0=+, 1=blank, 2=-
            switch (band, subIdx) {
            case (0, 0): return "A+"
            case (0, 1): return "A"
            case (0, _): return "A-"
            case (1, 0): return "B+"
            case (1, 1): return "B"
            case (1, _): return "B-"
            case (2, 0): return "C+"
            case (2, 1): return "C"
            default:     return "C-"
            }
        }
    }
}
