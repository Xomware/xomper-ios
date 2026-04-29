import Foundation

/// Dynasty-superflex value for a single player, sourced from
/// FantasyCalc's public values API. We only model the fields we
/// actually consume on iOS — the response carries dozens of fields
/// per player; the lenient decoder ignores the rest.
///
/// Keyed by Sleeper player ID at the store level so it joins cleanly
/// against `roster.players` / `starters` / `taxi` / `reserve`.
struct PlayerValue: Codable, Sendable {
    /// Sleeper player ID. Matches `Player.playerId`.
    let sleeperId: String?
    /// Dynasty value (0..~10000 — Josh Allen ≈ 10000 at peak).
    let value: Int
    /// Position the value was computed against (QB/RB/WR/TE).
    let position: String?
    /// Overall rank across all positions for the league format.
    let overallRank: Int?
    /// Position rank.
    let positionRank: Int?
    /// 30-day value trend (positive = rising).
    let trend30Day: Int?

    enum TopLevelKeys: String, CodingKey {
        case player
        case value
        case overallRank
        case positionRank
        case trend30Day
    }

    enum PlayerKeys: String, CodingKey {
        case sleeperId
        case position
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopLevelKeys.self)
        let player = try? c.nestedContainer(keyedBy: PlayerKeys.self, forKey: .player)
        self.sleeperId = try? player?.decodeIfPresent(String.self, forKey: .sleeperId)
        self.position = try? player?.decodeIfPresent(String.self, forKey: .position)
        self.value = (try? c.decode(Int.self, forKey: .value)) ?? 0
        self.overallRank = try? c.decodeIfPresent(Int.self, forKey: .overallRank)
        self.positionRank = try? c.decodeIfPresent(Int.self, forKey: .positionRank)
        self.trend30Day = try? c.decodeIfPresent(Int.self, forKey: .trend30Day)
    }

    func encode(to encoder: Encoder) throws {
        // Encoding is unused (we only decode from FantasyCalc) — provide
        // a stub so Codable conformance is satisfied.
        var c = encoder.container(keyedBy: TopLevelKeys.self)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(overallRank, forKey: .overallRank)
        try c.encodeIfPresent(positionRank, forKey: .positionRank)
        try c.encodeIfPresent(trend30Day, forKey: .trend30Day)
    }
}
