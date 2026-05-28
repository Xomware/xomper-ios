import Foundation

/// One pick produced by the client-side `MockDraftEngine`. Engine-side
/// model — distinct from `MockedPick` in `Core/Models/MockDraftModels.swift`
/// which decodes the legacy backend wire shape. This struct carries
/// the engine's internal fields (score, personality, rosterId) that
/// the wire shape doesn't track.
struct EngineMockedPick: Sendable, Hashable, Identifiable {

    // MARK: - Pick coordinates

    /// 1-indexed overall pick number across the whole mock
    /// (`(round-1) * teams + slot`).
    let pickNo: Int
    /// 1-indexed round (1 ≤ round ≤ rounds).
    let round: Int
    /// 1-indexed slot within the round, matches the Sleeper
    /// `draftOrder` slot number for this team.
    let slot: Int

    // MARK: - Team

    /// Sleeper roster ID owning this slot.
    let rosterId: Int
    /// Sleeper user ID owning the roster — empty when the slot
    /// couldn't resolve to a user (rare commissioner-reshuffle case).
    let userId: String
    /// Display team name (`SleeperUser.teamName ?? displayName`).
    let teamName: String

    // MARK: - Player

    let playerId: String
    let playerName: String
    /// Position label — QB / RB / WR / TE for rookie pool. Used by
    /// the row to draw the colored chip.
    let position: String
    /// NFL team abbreviation, or empty string for free agents.
    let nflTeam: String
    /// FantasyCalc dynasty value at engine time.
    let value: Double

    // MARK: - Engine internals

    /// The final score the engine used to pick this player (after
    /// applying personality multipliers / jitter / etc). Equal to
    /// `value` for BPA. Surfaced in the row caption so users can
    /// see "fit ×1.34 → 8,234".
    let score: Double
    /// The personality that made this pick. For Pure mode every pick
    /// in a result shares one personality; for Mixed it varies per
    /// team.
    let personality: DraftPersonality

    // MARK: - Identifiable

    /// Identity by `pickNo` — picks are unique within a single mock.
    var id: Int { pickNo }
}
