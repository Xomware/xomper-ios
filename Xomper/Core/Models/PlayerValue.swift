import Foundation

/// Dynasty-superflex value for a single player, sourced from
/// FantasyCalc's public values API. We only model the fields we
/// actually consume on iOS — the response carries dozens of fields
/// per player; the lenient decoder ignores the rest.
///
/// Keyed by Sleeper player ID at the store level so it joins cleanly
/// against `roster.players` / `starters` / `taxi` / `reserve`.
struct PlayerValue: Codable, Sendable {
    /// Sleeper player ID. Matches `Player.playerId`. Nil for draft picks.
    let sleeperId: String?
    /// Dynasty value (0..~10000 — Josh Allen ≈ 10000 at peak).
    let value: Int
    /// Position the value was computed against (QB/RB/WR/TE/PICK).
    let position: String?
    /// Display name. Players: "Josh Allen". Picks: "2026 Mid 1st" /
    /// "2027 Early 2nd" / "2026 1.05" etc.
    let name: String?
    /// Overall rank across all positions for the league format.
    let overallRank: Int?
    /// Position rank.
    let positionRank: Int?
    /// 30-day value trend (positive = rising).
    let trend30Day: Int?

    /// Convenience: this entry is a draft pick rather than a player.
    /// FantasyCalc tags picks with `position == "PICK"` and a null
    /// `sleeperId`.
    var isPick: Bool {
        (sleeperId ?? "").isEmpty || (position?.uppercased() == "PICK")
    }

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
        case name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopLevelKeys.self)
        let player = try? c.nestedContainer(keyedBy: PlayerKeys.self, forKey: .player)
        self.sleeperId = try? player?.decodeIfPresent(String.self, forKey: .sleeperId)
        self.position = try? player?.decodeIfPresent(String.self, forKey: .position)
        self.name = try? player?.decodeIfPresent(String.self, forKey: .name)
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
