import Foundation

/// One full client-side mock-draft result — the picks the engine
/// produced for either a single personality (Pure) or a per-team
/// personality assignment (Mixed). The view renders one of these per
/// `MockDraftCard`.
struct MockDraftResult: Sendable, Hashable, Identifiable {

    /// Which viewing mode produced this result. Pure → every team
    /// picks via the same personality; Mixed → per-team assignments
    /// stored in `personalityByRosterId`.
    enum Mode: String, Sendable, Hashable {
        case pure
        case mixed
    }

    /// Stable id for `ForEach`. Pure mocks key by personality; Mixed
    /// mocks key by seed since their personality is per-team.
    let id: String

    let mode: Mode

    /// Personality used for the whole mock when `mode == .pure`. Nil
    /// for Mixed mocks (read `personalityByRosterId` instead).
    let purePersonality: DraftPersonality?

    /// Picks in pickNo order. Length == rounds × teams in the happy
    /// path; smaller when pool exhaustion clipped the run.
    let picks: [EngineMockedPick]

    /// rosterId → personality assignment when `mode == .mixed`. Nil
    /// for Pure mocks.
    let personalityByRosterId: [Int: DraftPersonality]?

    /// RNG seed used to produce this mock. Deterministic mocks reuse
    /// the parent store's `currentSeed` even though they don't sample
    /// — keeps cache invalidation symmetric.
    let seed: UInt64

    /// True when the engine ran out of eligible rookies before
    /// filling all picks. The view surfaces this in the card header
    /// so users understand why a mock has fewer than 60 rows.
    let didExhaustPool: Bool

    /// Convenience: number of unique players picked. Matches
    /// `picks.count` in a healthy run since no player can be picked
    /// twice within a single mock.
    var uniquePlayerCount: Int {
        Set(picks.map(\.playerId)).count
    }

    /// Mocks with `mode == .mixed` only — list of (rosterId, teamName,
    /// personality) for the header. Sorted by slot so the mix reads
    /// like the live draft order.
    func mixedSummary(slotOrder: [Int: SlotTeam]) -> [(slot: Int, teamName: String, personality: DraftPersonality)] {
        guard let map = personalityByRosterId else { return [] }
        return slotOrder
            .compactMap { (slot, team) -> (Int, String, DraftPersonality)? in
                guard let p = map[team.rosterId] else { return nil }
                return (slot, team.teamName, p)
            }
            .sorted { $0.0 < $1.0 }
            .map { (slot: $0.0, teamName: $0.1, personality: $0.2) }
    }
}

/// One slot in the live draft order — slot number is the dictionary
/// key in `MockDraftEngine.run`. Carries the roster/user/team trio
/// the engine needs to attribute each pick.
struct SlotTeam: Sendable, Hashable {
    let rosterId: Int
    let userId: String
    let teamName: String
}
