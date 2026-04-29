import Foundation

/// Per-player aggregate stats for a single NFL regular season, decoded
/// from Sleeper's `/stats/nfl/regular/{season}` endpoint. Only the
/// fantasy-relevant fields are modeled — Sleeper returns dozens of
/// raw stats fields per player; the lenient decoder ignores the rest.
struct PlayerSeasonStats: Codable, Sendable {
    /// Games played in the season.
    let gamesPlayed: Int?
    /// Total fantasy points (PPR scoring).
    let pointsPPR: Double?
    /// Total fantasy points (Half-PPR scoring).
    let pointsHalfPPR: Double?
    /// Total fantasy points (Standard / non-PPR scoring).
    let pointsStandard: Double?

    enum CodingKeys: String, CodingKey {
        case gamesPlayed = "gp"
        case pointsPPR = "pts_ppr"
        case pointsHalfPPR = "pts_half_ppr"
        case pointsStandard = "pts_std"
    }

    /// Tolerant decoder — some players' entries omit fields entirely
    /// (rookies with no games, defensive players with no fantasy
    /// scoring). Treat any missing/malformed field as nil.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.gamesPlayed = try? c.decodeIfPresent(Int.self, forKey: .gamesPlayed)
        self.pointsPPR = try? c.decodeIfPresent(Double.self, forKey: .pointsPPR)
        self.pointsHalfPPR = try? c.decodeIfPresent(Double.self, forKey: .pointsHalfPPR)
        self.pointsStandard = try? c.decodeIfPresent(Double.self, forKey: .pointsStandard)
    }

    /// PPR points per game played, or nil if no games or no points.
    var avgPointsPPR: Double? {
        guard let gp = gamesPlayed, gp > 0, let pts = pointsPPR else { return nil }
        return pts / Double(gp)
    }

    /// Half-PPR points per game played, or nil if no games or no points.
    var avgPointsHalfPPR: Double? {
        guard let gp = gamesPlayed, gp > 0, let pts = pointsHalfPPR else { return nil }
        return pts / Double(gp)
    }
}
